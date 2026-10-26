import XCTest
@testable import DuoMusicBox

/// PlaybackMath 是播放步进/角度/发条-速度关系的纯逻辑层：
/// 音频调度、滚筒角度、当前步高亮全部由它推导，因此只需测这一层，
/// 就能保证"声音与机械运动同步"这条核心验收标准在逻辑上成立。
final class PlaybackMathTests: XCTestCase {

    func testStepDuration() {
        // 一步 = 八分音符：120 BPM 时一拍 0.5s，一步 0.25s。
        XCTAssertEqual(PlaybackMath.stepDuration(tempoBPM: 120), 0.25, accuracy: 1e-9)
        XCTAssertEqual(PlaybackMath.stepDuration(tempoBPM: 60), 0.5, accuracy: 1e-9)
        XCTAssertGreaterThan(PlaybackMath.stepDuration(tempoBPM: 0), 0, "非法速度也要有兜底")
    }

    func testTotalDuration() {
        // 16 步 @100 BPM：16 × 0.3 = 4.8s 一圈。
        XCTAssertEqual(PlaybackMath.totalDuration(stepCount: 16, tempoBPM: 100), 4.8, accuracy: 1e-9)
    }

    func testLoopStep() {
        XCTAssertEqual(PlaybackMath.loopStep(stepFloat: 0, stepCount: 16), 0)
        XCTAssertEqual(PlaybackMath.loopStep(stepFloat: 3.9, stepCount: 16), 3)
        XCTAssertEqual(PlaybackMath.loopStep(stepFloat: 16.0, stepCount: 16), 0, "满一圈回到第 0 步")
        XCTAssertEqual(PlaybackMath.loopStep(stepFloat: 17.3, stepCount: 16), 1)
        XCTAssertEqual(PlaybackMath.loopStep(stepFloat: 33.0, stepCount: 16), 1)
        XCTAssertEqual(PlaybackMath.loopStep(stepFloat: 5, stepCount: 0), 0, "零步数不崩溃")
    }

    func testRotationDegrees() {
        XCTAssertEqual(PlaybackMath.rotationDegrees(stepFloat: 0, stepCount: 16), 0, accuracy: 1e-9)
        XCTAssertEqual(PlaybackMath.rotationDegrees(stepFloat: 4, stepCount: 16), 90, accuracy: 1e-9)
        XCTAssertEqual(PlaybackMath.rotationDegrees(stepFloat: 8, stepCount: 16), 180, accuracy: 1e-9)
        XCTAssertEqual(PlaybackMath.rotationDegrees(stepFloat: 16, stepCount: 16), 0, accuracy: 1e-9,
                       "转满一圈角度归零（模 360）")
        XCTAssertEqual(PlaybackMath.rotationDegrees(stepFloat: 20, stepCount: 16), 90, accuracy: 1e-9)
        XCTAssertEqual(PlaybackMath.rotationDegrees(stepFloat: 2, stepCount: 32), 22.5, accuracy: 1e-9,
                       "32 步时每步 11.25°")
    }

    func testRotationMatchesStepFloatProportion() {
        // 任意位置：角度 / 360 == 圈内步进比例 —— 滚筒绘制 pinY 与此共用同一比例关系。
        for stepFloat in [0.0, 1.5, 7.25, 15.99, 16.0, 40.4] {
            let deg = PlaybackMath.rotationDegrees(stepFloat: stepFloat, stepCount: 16)
            XCTAssertGreaterThanOrEqual(deg, 0)
            XCTAssertLessThan(deg, 360)
        }
    }

    func testTempoFactorSpringCurve() {
        XCTAssertEqual(PlaybackMath.tempoFactor(springCharge: 1.0), 1.0, accuracy: 1e-9)
        XCTAssertEqual(PlaybackMath.tempoFactor(springCharge: 0.25), 1.0, accuracy: 1e-9,
                       "储能 ≥25% 全速")
        XCTAssertEqual(PlaybackMath.tempoFactor(springCharge: 0.125), 0.5, accuracy: 1e-9,
                       "12.5% 时半速（渐慢区线性）")
        XCTAssertEqual(PlaybackMath.tempoFactor(springCharge: 0.0), 0.0, accuracy: 1e-9,
                       "耗尽停转")
        XCTAssertEqual(PlaybackMath.tempoFactor(springCharge: -0.5), 0.0, accuracy: 1e-9,
                       "负储能钳制为 0")
        XCTAssertEqual(PlaybackMath.tempoFactor(springCharge: 1.5), 1.0, accuracy: 1e-9,
                       "过充钳制为全速")
    }

    func testEffectiveTempo() {
        XCTAssertEqual(PlaybackMath.effectiveTempo(baseTempo: 120, springCharge: 0.125), 60, accuracy: 1e-9)
        XCTAssertEqual(PlaybackMath.effectiveTempo(baseTempo: 100, springCharge: 0.8), 100, accuracy: 1e-9)
        XCTAssertEqual(PlaybackMath.effectiveTempo(baseTempo: 100, springCharge: 0), 0, accuracy: 1e-9)
    }

    /// 速度区间（用户定版 100–200）：滑杆与装载旋律共用同一钳制口径。
    func testTempoRangeClamp() {
        XCTAssertEqual(PlaybackEngine.tempoRange.lowerBound, 100)
        XCTAssertEqual(PlaybackEngine.tempoRange.upperBound, 200)
        XCTAssertEqual(PlaybackEngine.clampedTempo(72), 100, "慢板预置（如平安夜 72）抬到下限")
        XCTAssertEqual(PlaybackEngine.clampedTempo(100), 100)
        XCTAssertEqual(PlaybackEngine.clampedTempo(160), 160)
        XCTAssertEqual(PlaybackEngine.clampedTempo(200), 200)
        XCTAssertEqual(PlaybackEngine.clampedTempo(240), 200, "超上限钳到 200")
    }
}
