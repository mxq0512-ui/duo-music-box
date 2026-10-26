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
    /// 速度可调区间（用户定版）：100...200 BPM。低于 100 整体听感拖沓，故设下限；
    /// 滑杆范围与装载旋律时的速度钳制都走这里，全 App 只有一个口径。
    public static let tempoRange: ClosedRange<Double> = 100...200

    public static func clampedTempo(_ bpm: Double) -> Double {
        min(tempoRange.upperBound, max(tempoRange.lowerBound, bpm))
    }

    /// 当前速度（BPM）。装载旋律时取旋律自带速度（钳制进 tempoRange），之后可由用户滑杆调整。
    @Published public var tempoBPM: Double = 100 {
        didSet {
            let clamped = Self.clampedTempo(tempoBPM)
            if clamped != tempoBPM { tempoBPM = clamped }
        }
    }

    /// 一次"步触发"快照：某一步抵达拨弦线的瞬间，被拨动的全部音高。
    /// 只读观察口，供 Phase 2 的 3D 音梳振动等纯视觉效果订阅；
    /// 在 tick() 里 stepFloat 跨过步界时发布，与 currentStep 同步、与音频调度同源，
    /// 音频调度本身不依赖它，它的发布时机也不影响任何已排程的声音。
    public struct StepTrigger: Equatable {
        public let step: Int
        public let pitchIndices: [Int]
        /// 触发时刻（CACurrentMediaTime 时钟域，与 SceneKit 渲染回调的时间同域）。
        public let time: CFTimeInterval

        public init(step: Int, pitchIndices: [Int], time: CFTimeInterval) {
            self.step = step
            self.pitchIndices = pitchIndices
            self.time = time
        }
    }

    /// 最近一次步触发（无音符的步不发布）。暂停/停止/换旋律时复位。
    @Published public private(set) var lastStepTrigger: StepTrigger?

    public private(set) var melody: Melody = Melody.blankTemplate

    private var timer: Timer?
    private var stepFloat: Double = 0
    private var nextStepToSchedule = 0
    private var lastTickTime: CFTimeInterval = 0
    /// 上次已发布触发快照的步；-1 表示尚未触发（跨步检测用）。
    private var lastTriggeredStep = -1

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
        lastTriggeredStep = -1
        lastStepTrigger = nil
        publishPosition()
        if wasPlaying { play() }
    }

    /// 编曲时同步最新草稿（不打断播放位置）；步数变化时保守复位进度。
    public func syncMelody(_ updated: Melody) {
        if updated.stepCount != melody.stepCount {
            stepFloat = 0
            nextStepToSchedule = 0
            lastTriggeredStep = -1
            lastStepTrigger = nil
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
        // 恢复时整格的音符会重新发声，触发快照也要允许同一格再次发布。
        lastTriggeredStep = -1
        publishPosition()
    }

    public func stop() {
        if isPlaying { pause() }
        stepFloat = 0
        nextStepToSchedule = 0
        lastTriggeredStep = -1
        lastStepTrigger = nil
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
            // 触发快照与发声共用同一闸门：储能耗尽、声音停下时视觉也不触发。
            publishTriggerIfStepChanged(now: now)
        }
        // 储能耗尽时 stepFloat 不再前进（曲速渐慢直至停的状态层体现），
        // 但定时器继续跑：用户一上发条即可自动恢复，无需重新按播放。
        publishPosition()
    }

    /// 步触发快照的发布：stepFloat 跨入新的一格且该格有音符时发布一次。
    /// 与 scheduleAhead 的发声时机对齐（音符在 stepFloat 抵达该格时发声），
    /// 但只是观察，不参与调度。步进因钳制 dt 至多跨一格的常态下不会漏步；
    /// 万一跨过整格，只补发布当前格（视觉效果，不值得为它引入队列）。
    private func publishTriggerIfStepChanged(now: CFTimeInterval) {
        // 直接由 stepFloat 推导（不读 currentStep）：本方法在 publishPosition 之前调用，
        // 用同一条 PlaybackMath 公式保证与随后发布的位置严格一致。
        let step = PlaybackMath.loopStep(stepFloat: stepFloat, stepCount: melody.stepCount)
        guard step != lastTriggeredStep else { return }
        lastTriggeredStep = step
        let events = melody.events(atStep: step)
        guard !events.isEmpty else { return }
        lastStepTrigger = StepTrigger(step: step,
                                      pitchIndices: events.map(\.pitchIndex),
                                      time: now)
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
