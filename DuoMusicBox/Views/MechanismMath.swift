import Foundation

/// Phase 2 机械 3D 的纯数学层：不依赖 SceneKit / UIKit，可直接单元测试。
///
/// 与 Phase 1 的坐标约定严格一致（见 CylinderView 的注释）：
/// - 滚筒横轴（x）= 音高：左 C5 → 右 C6，共 Melody.pitchCount 列。
/// - 滚筒圆周方向 = 时间步：音钉在鼓面上的角度只由 (step, stepCount) 决定；
///   播放位置 stepFloat 只通过鼓体旋转进入画面，与音频调度同源（PlaybackMath.rotationDegrees）。
/// - 正向（音钉落位）与逆向（点按反解）共用本文件同一组公式，保证互逆。
public enum MechanismMath {
    /// 3D 场景中滚筒的半径与轴向长度（场景单位，与 MechanismSceneView 共用同一组尺寸）。
    public static let drumRadius = 1.0
    public static let drumLength = 3.3

    // MARK: - 音钉落位（正向）

    /// 第 step 步在鼓面上的角度（弧度）：步与步等分整圈，step 0 在角度 0。
    /// 鼓体子节点的局部坐标以此为准；世界角度 = 本地角度 − 鼓体旋转角，
    /// 当 stepFloat 到达 step 时世界角度为 0，即音钉正对前方拨弦线——与 Phase 1
    /// “d = mod(step − stepFloat, n)，d = 0 时钉在拨弦线”的约定等价。
    public static func pinAngleRadians(step: Int, stepCount: Int) -> Double {
        guard stepCount > 0 else { return 0 }
        return 2 * Double.pi * Double(step) / Double(stepCount)
    }

    /// 音钉在滚筒子坐标系中的位置：x 由音高列决定（列中心），y/z 由步角度决定，
    /// 点恒在半径 radius 的圆柱面上。角度以 +Z（正对观者）为 0、向 +Y 为正。
    public static func pinLocalPosition(pitchIndex: Int, step: Int, stepCount: Int,
                                        radius: Double = drumRadius,
                                        length: Double = drumLength)
        -> (x: Double, y: Double, z: Double) {
        let colW = length / Double(Melody.pitchCount)
        let x = -length / 2 + colW * (Double(pitchIndex) + 0.5)
        let a = pinAngleRadians(step: step, stepCount: stepCount)
        return (x, radius * sin(a), radius * cos(a))
    }

    /// 鼓体旋转角（弧度）：直接来自 PlaybackMath.rotationDegrees，不引入第二个时钟。
    /// 符号约定见 pinAngleRadians 的注释——鼓体绕 +X 转此角时，
    /// 即将触发的音钉从上向前下方滚动，抵达正前方时发声，与 Phase 1 画面运动方向一致。
    public static func drumRotationRadians(rotationDegrees: Double) -> Double {
        rotationDegrees * Double.pi / 180
    }

    // MARK: - 点按反解（逆向，与落位互逆）

    /// 把滚筒子坐标系中的命中点反解为 (pitch, step)：pitch 取所在音高列，
    /// step 取角度最近的步。与 pinLocalPosition 严格互逆——对任意 (pitch, step)
    /// 先正向落位再反解，必回到原格（有单元测试覆盖）。
    /// 点在转轴附近（径向距离过小）时角度无意义，返回 nil。
    public static func pitchAndStep(localX: Double, localY: Double, localZ: Double,
                                    stepCount: Int,
                                    radius: Double = drumRadius,
                                    length: Double = drumLength)
        -> (pitch: Int, step: Int)? {
        guard stepCount > 0, length > 0 else { return nil }
        let radial = hypot(localY, localZ)
        guard radial > radius * 0.3 else { return nil }
        let colW = length / Double(Melody.pitchCount)
        let pitch = min(Melody.pitchCount - 1, max(0, Int((localX + length / 2) / colW)))
        var angle = atan2(localY, localZ)
        if angle < 0 { angle += 2 * Double.pi }
        let stepFloat = angle / (2 * Double.pi) * Double(stepCount)
        var step = Int(stepFloat.rounded()) % stepCount
        if step < 0 { step += stepCount }
        return (pitch, step)
    }

    // MARK: - 齿轮传动（与 Phase 1 GearView 的公式逐字对应）

    /// 大齿轮与滚筒同轴同速。
    public static func bigGearDegrees(cylinderRotation: Double) -> Double {
        cylinderRotation
    }

    /// 小齿轮按齿数比反向加速，+12° 为装配相位（与 GearView 一致）。
    public static func smallGearDegrees(cylinderRotation: Double,
                                        bigTeeth: Int = 12, smallTeeth: Int = 8) -> Double {
        guard smallTeeth > 0 else { return 0 }
        return -cylinderRotation * Double(bigTeeth) / Double(smallTeeth) + 12
    }

    /// 调速器转速为滚筒的 6 倍（与 GearView 一致）。
    public static func governorDegrees(cylinderRotation: Double) -> Double {
        cylinderRotation * 6
    }

    /// 屏幕顺时针角度（SwiftUI rotationEffect 的约定）→ SceneKit 绕 +Z 的弧度：
    /// 从 +Z 看过去 SceneKit 正角为逆时针，故取负，保证 3D 齿轮转向与 Phase 1 画面一致。
    public static func sceneRotationZ(clockwiseDegrees: Double) -> Double {
        -clockwiseDegrees * Double.pi / 180
    }

    // MARK: - 音梳振动

    /// 梳齿被拨动后的可见振动时长（秒），超出即归零。
    public static let toothVibrationDuration = 0.30

    /// 梳齿振动角偏移（弧度）：快速正弦 + 指数衰减，约 0.25 秒内衰减到不可见。
    /// elapsed < 0 或超过振动时长时为 0；幅度被 exp 包络严格限制（有单元测试覆盖）。
    public static func toothOscillation(elapsed: Double) -> Double {
        guard elapsed >= 0, elapsed <= toothVibrationDuration else { return 0 }
        let amplitude = 0.07
        let decay = exp(-elapsed / 0.085)
        return amplitude * decay * sin(2 * Double.pi * 22 * elapsed)
    }

    // MARK: - 发条

    /// 发条量表指针角度（屏幕顺时针度）：储能 0 → −135°，满 → +135°，与量表常识一致。
    public static func springIndicatorDegrees(charge: Double) -> Double {
        let c = min(1, max(0, charge))
        return -135 + c * 270
    }
}
