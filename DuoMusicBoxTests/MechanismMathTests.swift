import XCTest
@testable import DuoMusicBox

/// MechanismMath 是 Phase 2 机械 3D 的纯逻辑层：
/// 音钉落位、点按反解、齿轮传动比、梳齿振动包络、发条量表全部在此推导，
/// 场景层（MechanismSceneView）只做赋值。因此只需测这一层，
/// 就能保证"3D 里的钉、声音、编曲器里的格"是同一套数学。
final class MechanismMathTests: XCTestCase {

    /// 同步不变量（2026-10-26 真机不同步回归）：第 s 步发声的一刻
    /// （stepFloat == s），该步音钉的世界角度必须恰为梳齿接触角。
    /// 世界角度 = 本地角度 − 鼓体欧拉角（MechanismMath 注释约定）。
    func testPinReachesCombContactAngleExactlyWhenItSounds() {
        for stepCount in [16, 64] {
            for s in [0, 1, 7, stepCount / 2, stepCount - 1] {
                let rotation = PlaybackMath.rotationDegrees(stepFloat: Double(s), stepCount: stepCount)
                let world = MechanismMath.pinAngleRadians(step: s, stepCount: stepCount)
                    - MechanismMath.drumEulerX(rotationDegrees: rotation)
                var degrees = (world * 180 / Double.pi).truncatingRemainder(dividingBy: 360)
                if degrees < 0 { degrees += 360 }
                XCTAssertEqual(degrees, MechanismMath.combContactAngleDegrees, accuracy: 1e-9,
                               "step \(s)/\(stepCount): pin world angle \(degrees) != contact angle")
            }
        }
    }


    // MARK: - 音钉落位

    func testPinAngle() {
        XCTAssertEqual(MechanismMath.pinAngleRadians(step: 0, stepCount: 16), 0, accuracy: 1e-12)
        XCTAssertEqual(MechanismMath.pinAngleRadians(step: 4, stepCount: 16), Double.pi / 2, accuracy: 1e-12)
        XCTAssertEqual(MechanismMath.pinAngleRadians(step: 8, stepCount: 16), Double.pi, accuracy: 1e-12)
        XCTAssertEqual(MechanismMath.pinAngleRadians(step: 1, stepCount: 32), Double.pi / 16, accuracy: 1e-12,
                       "32 步时每步 11.25°")
        XCTAssertEqual(MechanismMath.pinAngleRadians(step: 3, stepCount: 0), 0, "零步数不崩溃")
    }

    func testPinLocalPositionOnCylinderSurface() {
        // 任意 (pitch, step)：点恒在半径 R 的圆柱面上，且 x 落在鼓长范围内、低音在左高音在右。
        for stepCount in [16, 32] {
            for pitch in 0..<Melody.pitchCount {
                for step in [0, 1, stepCount / 2, stepCount - 1] {
                    let pos = MechanismMath.pinLocalPosition(pitchIndex: pitch, step: step, stepCount: stepCount)
                    XCTAssertEqual(hypot(pos.y, pos.z), MechanismMath.drumRadius, accuracy: 1e-9,
                                   "音钉必须贴在鼓面上")
                    XCTAssertGreaterThanOrEqual(pos.x, -MechanismMath.drumLength / 2)
                    XCTAssertLessThanOrEqual(pos.x, MechanismMath.drumLength / 2)
                }
            }
        }
        let low = MechanismMath.pinLocalPosition(pitchIndex: 0, step: 0, stepCount: 16)
        let high = MechanismMath.pinLocalPosition(pitchIndex: 7, step: 0, stepCount: 16)
        XCTAssertLessThan(low.x, high.x, "C5 在左、C6 在右，与 Phase 1 列序一致")
        // step 0 的钉在正前方（拨弦线）：y = 0、z = +R。
        XCTAssertEqual(low.y, 0, accuracy: 1e-12)
        XCTAssertEqual(low.z, MechanismMath.drumRadius, accuracy: 1e-12)
    }

    // MARK: - 点按反解（与落位互逆）

    func testPinRoundTrip() {
        // 核心契约：任意格先正向落位、再反解，必须回到原格——
        // 3D 点按与编曲网格因此不可能错位。
        let cells16: [(Int, Int)] = [(0, 0), (7, 15), (3, 5), (5, 11), (0, 15), (7, 0), (2, 8)]
        for (pitch, step) in cells16 {
            let pos = MechanismMath.pinLocalPosition(pitchIndex: pitch, step: step, stepCount: 16)
            let back = MechanismMath.pitchAndStep(localX: pos.x, localY: pos.y, localZ: pos.z, stepCount: 16)
            XCTAssertEqual(back?.pitch, pitch, "16 步 pitch \(pitch) step \(step) 反解 pitch 不符")
            XCTAssertEqual(back?.step, step, "16 步 pitch \(pitch) step \(step) 反解 step 不符")
        }
        let cells32: [(Int, Int)] = [(0, 0), (7, 31), (4, 17), (1, 30)]
        for (pitch, step) in cells32 {
            let pos = MechanismMath.pinLocalPosition(pitchIndex: pitch, step: step, stepCount: 32)
            let back = MechanismMath.pitchAndStep(localX: pos.x, localY: pos.y, localZ: pos.z, stepCount: 32)
            XCTAssertEqual(back?.pitch, pitch)
            XCTAssertEqual(back?.step, step)
        }
        // Phase 3：64 步全格往返（表格与滚筒在最密步距下仍须格格对齐）
        for step in 0..<64 {
            for pitch in [0, 3, 7] {
                let pos = MechanismMath.pinLocalPosition(pitchIndex: pitch, step: step, stepCount: 64)
                let back = MechanismMath.pitchAndStep(localX: pos.x, localY: pos.y, localZ: pos.z, stepCount: 64)
                XCTAssertEqual(back?.pitch, pitch, "64 步 pitch \(pitch) step \(step) 反解 pitch 不符")
                XCTAssertEqual(back?.step, step, "64 步 pitch \(pitch) step \(step) 反解 step 不符")
            }
        }
    }

    // MARK: - 刻度环密度（Phase 3）

    func testStepRingStride() {
        XCTAssertEqual(MechanismMath.stepRingStride(stepCount: 8), 1)
        XCTAssertEqual(MechanismMath.stepRingStride(stepCount: 16), 1)
        XCTAssertEqual(MechanismMath.stepRingStride(stepCount: 32), 2)
        XCTAssertEqual(MechanismMath.stepRingStride(stepCount: 64), 4)
        XCTAssertEqual(MechanismMath.stepRingStride(stepCount: 0), 1, "零步数也不得返回 0（stride by 0 会崩溃）")
    }

    func testPitchAndStepEdgeCases() {
        // 转轴正中心：角度无意义 → nil，不乱报格。
        XCTAssertNil(MechanismMath.pitchAndStep(localX: 0, localY: 0, localZ: 0, stepCount: 16))
        // 零步数 → nil。
        XCTAssertNil(MechanismMath.pitchAndStep(localX: 0, localY: 0, localZ: 1, stepCount: 0))
        // 鼓面之外左右越界：pitch 钳制到边缘列（与 Phase 1 pitchAt 的钳制行为一致）。
        let left = MechanismMath.pitchAndStep(localX: -99, localY: 0, localZ: 1, stepCount: 16)
        XCTAssertEqual(left?.pitch, 0)
        let right = MechanismMath.pitchAndStep(localX: 99, localY: 0, localZ: 1, stepCount: 16)
        XCTAssertEqual(right?.pitch, Melody.pitchCount - 1)
        // 鼓面正后方（角度 π）：第 stepCount/2 步。
        let back = MechanismMath.pitchAndStep(localX: 0, localY: 0, localZ: -1, stepCount: 16)
        XCTAssertEqual(back?.step, 8)
        // 鼓面正下方（角度 3π/2）：第 12 步（角度自 +Z 向 +Y 计，经过顶部 π/2、后方 π）。
        let bottom = MechanismMath.pitchAndStep(localX: 0, localY: -1, localZ: 0, stepCount: 16)
        XCTAssertEqual(bottom?.step, 12)
    }

    // MARK: - 齿轮传动（公式与 Phase 1 GearView 逐字对应）

    func testGearAngles() {
        XCTAssertEqual(MechanismMath.bigGearDegrees(cylinderRotation: 0), 0, accuracy: 1e-12)
        XCTAssertEqual(MechanismMath.bigGearDegrees(cylinderRotation: 90), 90, accuracy: 1e-12,
                       "大齿轮与滚筒同轴同速")
        XCTAssertEqual(MechanismMath.smallGearDegrees(cylinderRotation: 0), 12, accuracy: 1e-12,
                       "装配相位 +12°")
        XCTAssertEqual(MechanismMath.smallGearDegrees(cylinderRotation: 90), -123, accuracy: 1e-12,
                       "-90 × 12/8 + 12 = -123：反向、1.5 倍速")
        XCTAssertEqual(MechanismMath.smallGearDegrees(cylinderRotation: 60, bigTeeth: 12, smallTeeth: 6),
                       -108, accuracy: 1e-12, "齿数比可换：-60 × 2 + 12")
        XCTAssertEqual(MechanismMath.governorDegrees(cylinderRotation: 30), 180, accuracy: 1e-12,
                       "调速器 6 倍速")
        XCTAssertEqual(MechanismMath.governorDegrees(cylinderRotation: 60), 360, accuracy: 1e-12)
    }

    func testSceneRotationZSign() {
        // SwiftUI 顺时针为正 → SceneKit 绕 +Z 为逆时针正，换算必须取负且过 π。
        XCTAssertEqual(MechanismMath.sceneRotationZ(clockwiseDegrees: 90), -Double.pi / 2, accuracy: 1e-12)
        XCTAssertEqual(MechanismMath.sceneRotationZ(clockwiseDegrees: -45), Double.pi / 4, accuracy: 1e-12)
        XCTAssertEqual(MechanismMath.drumRotationRadians(rotationDegrees: 180), Double.pi, accuracy: 1e-12)
    }

    // MARK: - 音梳振动包络

    func testToothOscillation() {
        XCTAssertEqual(MechanismMath.toothOscillation(elapsed: 0), 0, accuracy: 1e-12, "起振瞬间偏移为 0")
        XCTAssertEqual(MechanismMath.toothOscillation(elapsed: -0.1), 0, "未触发时为 0")
        XCTAssertEqual(MechanismMath.toothOscillation(elapsed: MechanismMath.toothVibrationDuration + 0.05),
                       0, "振动结束后归零")
        // 包络上界：任意时刻 |偏移| ≤ 0.07 × exp(−t/0.085)，且确实振得起来。
        for t in stride(from: 0.0, through: MechanismMath.toothVibrationDuration, by: 0.01) {
            XCTAssertLessThanOrEqual(abs(MechanismMath.toothOscillation(elapsed: t)),
                                     0.07 * exp(-t / 0.085) + 1e-12,
                                     "t=\(t) 超出衰减包络")
        }
        XCTAssertGreaterThan(abs(MechanismMath.toothOscillation(elapsed: 0.011)), 0.04,
                             "触发后应立刻有可见摆幅")
    }

    // MARK: - 发条量表

    func testSpringIndicator() {
        XCTAssertEqual(MechanismMath.springIndicatorDegrees(charge: 0), -135, accuracy: 1e-12)
        XCTAssertEqual(MechanismMath.springIndicatorDegrees(charge: 1), 135, accuracy: 1e-12)
        XCTAssertEqual(MechanismMath.springIndicatorDegrees(charge: 0.5), 0, accuracy: 1e-12, "半程指向上")
        XCTAssertEqual(MechanismMath.springIndicatorDegrees(charge: 2), 135, accuracy: 1e-12, "过充钳制")
        XCTAssertEqual(MechanismMath.springIndicatorDegrees(charge: -1), -135, accuracy: 1e-12, "负储能钳制")
    }

    // MARK: - 裸眼 3D 视差（陀螺仪倾斜映射；符号约定与 MechanismMath 实现注释一致）

    func testParallaxZeroDelta() {
        // 无倾斜 → 无偏移：模拟器/静止时画面与视差功能加入前完全一致。
        let offset = MechanismMath.parallaxOffset(pitchDelta: 0, rollDelta: 0)
        XCTAssertEqual(offset.x, 0, accuracy: 1e-12)
        XCTAssertEqual(offset.y, 0, accuracy: 1e-12)
        let shift = MechanismMath.parallaxTargetShift(offset: offset)
        XCTAssertEqual(shift.x, 0, accuracy: 1e-12)
        XCTAssertEqual(shift.y, 0, accuracy: 1e-12)
        // 姿态异常（非有限值）按静止处理，不把机位甩飞。
        let nonFinite = MechanismMath.parallaxOffset(pitchDelta: .nan, rollDelta: .infinity)
        XCTAssertEqual(nonFinite.x, 0, accuracy: 1e-12)
        XCTAssertEqual(nonFinite.y, 0, accuracy: 1e-12)
    }

    func testParallaxSignConvention() {
        // 顶部后仰（趋向平放，pitch 增大）→ 机位上移，从更上方俯视机芯。
        let away = MechanismMath.parallaxOffset(pitchDelta: MechanismMath.parallaxMaxDelta, rollDelta: 0)
        XCTAssertEqual(away.y, MechanismMath.parallaxMaxOffsetY, accuracy: 1e-12)
        XCTAssertEqual(away.x, 0, accuracy: 1e-12, "纯 pitch 输入不产生横向偏移")
        // 顶部前倾（趋向竖直，pitch 减小）→ 机位下移。
        let toward = MechanismMath.parallaxOffset(pitchDelta: -MechanismMath.parallaxMaxDelta, rollDelta: 0)
        XCTAssertEqual(toward.y, -MechanismMath.parallaxMaxOffsetY, accuracy: 1e-12)
        // 上端右倾（roll 增大）→ 机位右移；左倾 → 左移。
        let right = MechanismMath.parallaxOffset(pitchDelta: 0, rollDelta: MechanismMath.parallaxMaxDelta)
        XCTAssertEqual(right.x, MechanismMath.parallaxMaxOffsetX, accuracy: 1e-12)
        XCTAssertEqual(right.y, 0, accuracy: 1e-12, "纯 roll 输入不产生纵向偏移")
        let left = MechanismMath.parallaxOffset(pitchDelta: 0, rollDelta: -MechanismMath.parallaxMaxDelta)
        XCTAssertEqual(left.x, -MechanismMath.parallaxMaxOffsetX, accuracy: 1e-12)
        // 半程增量 → 半程偏移（钳制区间内严格线性）。
        let half = MechanismMath.parallaxOffset(pitchDelta: MechanismMath.parallaxMaxDelta / 2,
                                                rollDelta: MechanismMath.parallaxMaxDelta / 2)
        XCTAssertEqual(half.y, MechanismMath.parallaxMaxOffsetY / 2, accuracy: 1e-12)
        XCTAssertEqual(half.x, MechanismMath.parallaxMaxOffsetX / 2, accuracy: 1e-12)
    }

    func testParallaxClamping() {
        // 超出 ±0.45 rad 的增量一律钳制在最大偏移，一轴饱和不影响另一轴。
        let wild = MechanismMath.parallaxOffset(pitchDelta: 2.0, rollDelta: -3.0)
        XCTAssertEqual(wild.y, MechanismMath.parallaxMaxOffsetY, accuracy: 1e-12)
        XCTAssertEqual(wild.x, -MechanismMath.parallaxMaxOffsetX, accuracy: 1e-12)
        let mixed = MechanismMath.parallaxOffset(pitchDelta: 99, rollDelta: MechanismMath.parallaxMaxDelta / 4)
        XCTAssertEqual(mixed.y, MechanismMath.parallaxMaxOffsetY, accuracy: 1e-12)
        XCTAssertEqual(mixed.x, MechanismMath.parallaxMaxOffsetX / 4, accuracy: 1e-12)
    }

    func testParallaxTargetShiftRatio() {
        // 注视目标只跟随机位的 35%：0.5 → 0.175、0.32 → 0.112，符号保持。
        let shift = MechanismMath.parallaxTargetShift(offset: (x: 0.5, y: 0.32))
        XCTAssertEqual(shift.x, 0.175, accuracy: 1e-12)
        XCTAssertEqual(shift.y, 0.112, accuracy: 1e-12)
        let negative = MechanismMath.parallaxTargetShift(offset: (x: -0.2, y: 0.1))
        XCTAssertEqual(negative.x, -0.07, accuracy: 1e-12)
        XCTAssertEqual(negative.y, 0.035, accuracy: 1e-12)
    }

    func testParallaxMonotonicity() {
        // 钳制区间内增量单调增 → 两轴偏移单调不减；内点严格递增。
        var lastX = -Double.infinity
        var lastY = -Double.infinity
        for delta in stride(from: -0.45, through: 0.45, by: 0.05) {
            let o = MechanismMath.parallaxOffset(pitchDelta: delta, rollDelta: delta)
            XCTAssertGreaterThanOrEqual(o.x, lastX, "roll \(delta) 处 x 不单调")
            XCTAssertGreaterThanOrEqual(o.y, lastY, "pitch \(delta) 处 y 不单调")
            lastX = o.x
            lastY = o.y
        }
        let q1 = MechanismMath.parallaxOffset(pitchDelta: 0.1125, rollDelta: 0.1125)
        let q2 = MechanismMath.parallaxOffset(pitchDelta: 0.225, rollDelta: 0.225)
        let q3 = MechanismMath.parallaxOffset(pitchDelta: 0.45, rollDelta: 0.45)
        XCTAssertLessThan(q1.x, q2.x)
        XCTAssertLessThan(q2.x, q3.x)
        XCTAssertLessThan(q1.y, q2.y)
        XCTAssertLessThan(q2.y, q3.y)
    }
}
