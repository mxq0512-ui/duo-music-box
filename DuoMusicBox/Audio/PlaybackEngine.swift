import Foundation
import QuartzCore

/// 播放相关的纯逻辑：不依赖 UIKit / AVFoundation，可直接单元测试。
/// 约定：一步 = 一个八分音符（Melody.stepsPerBeat = 2）；滚筒转满一圈 = stepCount 步。
public enum PlaybackMath {
    /// 一步的时长（秒）。
    public static func stepDuration(tempoBPM: Double) -> TimeInterval {
        guard tempoBPM > 0 else { return 0.5 }
        return 60.0 / tempoBPM / Double(Melody.stepsPerBeat)
    }

    /// 整圈播放时长（秒）。
    public static func totalDuration(stepCount: Int, tempoBPM: Double) -> TimeInterval {
        stepDuration(tempoBPM: tempoBPM) * Double(max(0, stepCount))
    }

    /// 连续步进位置 → 当前格（向下取整后对 stepCount 取模，结果在 0 ..< stepCount）。
    public static func loopStep(stepFloat: Double, stepCount: Int) -> Int {
        guard stepCount > 0 else { return 0 }
        let floored = Int(floor(stepFloat))
        let m = floored % stepCount
        return m >= 0 ? m : m + stepCount
    }

    /// 连续步进位置 → 滚筒旋转角度（度，0 ..< 360）。这是滚筒/齿轮动画的唯一角度来源。
    public static func rotationDegrees(stepFloat: Double, stepCount: Int) -> Double {
        guard stepCount > 0 else { return 0 }
        let r = stepFloat.truncatingRemainder(dividingBy: Double(stepCount))
        let positive = r >= 0 ? r : r + Double(stepCount)
        return positive / Double(stepCount) * 360.0
    }

    /// 发条储能 → 速度系数：储能 ≥ 25% 时全速；以下线性变慢；0 时停转。
    /// 这是真实八音盒的行为：发条将尽时调速器拖不动，曲速渐慢直至停。
    public static func tempoFactor(springCharge: Double) -> Double {
        let c = min(1, max(0, springCharge))
        if c >= 0.25 { return 1 }
        if c <= 0 { return 0 }
        return c / 0.25
    }

    /// 实际生效速度（BPM）。
    public static func effectiveTempo(baseTempo: Double, springCharge: Double) -> Double {
        baseTempo * tempoFactor(springCharge: springCharge)
    }
}

/// 播放引擎：以宿主时钟为基准做前视调度（lookahead scheduling）。
///
/// 单一事实来源：内部维护连续位置 stepFloat，发布的 currentStep 与 cylinderRotation
/// 全部由它推导（见 PlaybackMath），音频调度也用同一步进计数——声音、滚筒、音梳
/// 永远不可能互相漂移。调度用 25ms 定时器，每次把未来约 180ms 内的音符按宿主时间
/// 排进 AVAudioPlayerNode，保证节奏不受 UI 帧率影响。
public final class PlaybackEngine: ObservableObject {
    /// 音频引擎归播放引擎持有，视图层只通过 playback.audio 取用机械音效。
    public let audio = MusicBoxAudioEngine()

    @Published public private(set) var isPlaying = false
    @Published public private(set) var currentStep = 0
    /// 滚筒当前旋转角度（度，0 ..< 360），由 stepFloat 推导。
    @Published public private(set) var cylinderRotation: Double = 0
    /// 发条储能 0...1：播放消耗、上发条补充；低于 25% 曲速渐慢，耗尽停转。
    @Published public var springCharge: Double = 0.8
    /// 当前速度（BPM）。装载旋律时取旋律自带速度，之后可由用户滑杆调整。
    @Published public var tempoBPM: Double = 100

    public private(set) var melody: Melody = Melody.blankTemplate

    private var timer: Timer?
    private var stepFloat: Double = 0
    private var nextStepToSchedule = 0
    private var lastTickTime: CFTimeInterval = 0

    /// 发条消耗速率：一格满储能（1.0）约可播 180 秒。
    private static let springDrainPerSecond = 1.0 / 180.0
    /// 前视调度窗口（秒）。
    private static let lookaheadSeconds = 0.18

    public init() {}

    deinit { timer?.invalidate() }

    // MARK: - 旋律装载

    /// 装载新旋律并复位到开头；若正在播放则无缝继续播新旋律。
    public func setMelody(_ newMelody: Melody) {
        let wasPlaying = isPlaying
        if wasPlaying { pause() }
        melody = newMelody
        tempoBPM = newMelody.tempoBPM
        stepFloat = 0
        nextStepToSchedule = 0
        publishPosition()
        if wasPlaying { play() }
    }

    /// 编曲时同步最新草稿（不打断播放位置）；步数变化时保守复位进度。
    public func syncMelody(_ updated: Melody) {
        if updated.stepCount != melody.stepCount {
            stepFloat = 0
            nextStepToSchedule = 0
        }
        melody = updated
    }

    // MARK: - 播放控制

    public func play() {
        guard !isPlaying, melody.stepCount > 0 else { return }
        audio.startIfNeeded()
        isPlaying = true
        lastTickTime = CACurrentMediaTime()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.025, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer?.tolerance = 0.005
    }

    public func pause() {
        guard isPlaying else { return }
        isPlaying = false
        timer?.invalidate()
        timer = nil
        audio.stopAllScheduled()
        // 暂停量化到当前格开头：恢复时整格重播，避免半格错位。
        stepFloat = floor(stepFloat)
        nextStepToSchedule = Int(stepFloat)
        publishPosition()
    }

    public func stop() {
        if isPlaying { pause() }
        stepFloat = 0
        nextStepToSchedule = 0
        publishPosition()
    }

    public func replay() {
        stop()
        play()
    }

    public func togglePlay() {
        if isPlaying { pause() } else { play() }
    }

    // MARK: - 发条

    public func addCharge(_ amount: Double) {
        springCharge = min(1, max(0, springCharge + amount))
    }

    // MARK: - 调度核心

    private func tick() {
        let now = CACurrentMediaTime()
        var dt = now - lastTickTime
        lastTickTime = now
        dt = min(max(dt, 0), 0.1) // 后台切回时钳制，避免位置跳变

        let effective = PlaybackMath.effectiveTempo(baseTempo: tempoBPM, springCharge: springCharge)
        if effective > 0.5 {
            let sd = PlaybackMath.stepDuration(tempoBPM: effective)
            stepFloat += dt / sd
            springCharge = max(0, springCharge - dt * Self.springDrainPerSecond)
            scheduleAhead(now: now, stepDuration: sd)
        }
        // 储能耗尽时 stepFloat 不再前进（曲速渐慢直至停的状态层体现），
        // 但定时器继续跑：用户一上发条即可自动恢复，无需重新按播放。
        publishPosition()
    }

    private func scheduleAhead(now: CFTimeInterval, stepDuration sd: Double) {
        let horizon = stepFloat + min(Self.lookaheadSeconds / sd, 3)
        while Double(nextStepToSchedule) < horizon {
            let s = nextStepToSchedule
            let loop = PlaybackMath.loopStep(stepFloat: Double(s), stepCount: melody.stepCount)
            let when = now + (Double(s) - stepFloat) * sd
            for event in melody.events(atStep: loop) {
                audio.play(pitchIndex: event.pitchIndex, velocity: event.velocity, atHostSeconds: when)
            }
            nextStepToSchedule += 1
        }
    }

    private func publishPosition() {
        currentStep = PlaybackMath.loopStep(stepFloat: stepFloat, stepCount: melody.stepCount)
        cylinderRotation = PlaybackMath.rotationDegrees(stepFloat: stepFloat, stepCount: melody.stepCount)
    }
}
