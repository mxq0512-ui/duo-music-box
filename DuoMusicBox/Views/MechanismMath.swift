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

    // MARK: - 裸眼 3D 视差（陀螺仪倾斜 → 相机机位）

    /// 视差输入钳制：姿态增量（当前姿态 − 启动参考姿态）超过 ±0.45 rad（≈26°）不再放大偏移。
    /// 覆盖正常手持把玩的倾斜幅度，又保证极端姿态下画面不漂移失控。
    public static let parallaxMaxDelta = 0.45
    /// 相机机位（rig）最大横向偏移（场景单位）。
    public static let parallaxMaxOffsetX = 0.5
    /// 相机机位最大纵向偏移（场景单位）。
    public static let parallaxMaxOffsetY = 0.32
    /// 注视目标的跟随比例：目标只移动机位偏移的 35%，机位与目标之间的差速
    /// 让相机产生小幅摆头——近处滚筒与远处背板在屏幕上的位移差，就是裸眼 3D 的来源。
    public static let parallaxTargetShiftRatio = 0.35
    /// 视差平滑时间常数（秒）：渲染帧以一阶低通 exp(−dt/τ) 追赶目标偏移，
    /// 约 0.12 秒——足够跟手，又能滤掉手抖的高频噪声。
    public static let parallaxSmoothingTau = 0.12

    /// 姿态增量（弧度）→ 相机机位偏移（场景单位）：线性映射 + 输入/输出双钳制，纯函数。
    ///
    /// 符号约定（xArbitraryZVertical 参考系下 CMAttitude 的欧拉角分解）：
    /// - pitch：手机竖直握持时约 −π/2；上端向远离用户的方向倾（趋向平放、屏幕朝上）时
    ///   pitch 向 0 增大，即"顶部后仰" ⇒ pitchDelta > 0。本函数取正增益 ⇒ 机位上移（+y），
    ///   效果是从更上方俯视机芯，如探头望进盒内。
    /// - roll：手机上端向右倾（拧腕顺时针）时 roll 增大 ⇒ rollDelta > 0，
    ///   同取正增益 ⇒ 机位右移（+x）。
    /// 两轴同号即"视点随倾斜同向"的窗口隐喻。若真机手感方向相反，只需在本函数
    /// 翻转对应轴的符号——单元测试逐条锁定本约定，翻转时同步改测试即可。
    public static func parallaxOffset(pitchDelta: Double, rollDelta: Double) -> (x: Double, y: Double) {
        let p = normalizedParallaxDelta(pitchDelta)
        let r = normalizedParallaxDelta(rollDelta)
        return (r * parallaxMaxOffsetX, p * parallaxMaxOffsetY)
    }

    /// 注视目标的位移 = 机位偏移 × parallaxTargetShiftRatio（当前 35%）。
    public static func parallaxTargetShift(offset: (x: Double, y: Double)) -> (x: Double, y: Double) {
        (offset.x * parallaxTargetShiftRatio, offset.y * parallaxTargetShiftRatio)
    }

    /// 增量归一化：先钳制到 ±parallaxMaxDelta 再除以该值，结果落在 [−1, 1]；
    /// 非有限输入（姿态异常）按 0 处理，画面保持静止而不是跳飞。
    private static func normalizedParallaxDelta(_ delta: Double) -> Double {
        guard delta.isFinite else { return 0 }
        return min(parallaxMaxDelta, max(-parallaxMaxDelta, delta)) / parallaxMaxDelta
    }
}
