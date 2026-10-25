import AVFoundation
import Foundation
import QuartzCore

/// 八音盒音频引擎：AVAudioEngine + AVAudioPlayerNode。
///
/// 所有声音都在启动时程序合成，工程不包含任何音频文件，也就没有素材版权问题：
/// - 音色：基频 + 非谐泛音列（3.98×、9.24×、16.8×，模拟金属音梳的非谐振动），
///   快速起音、各自独立的指数衰减，整体余韵约 1.2–1.8 秒；起音瞬间叠一丝拨弦噪声。
/// - 机械声：放钉 click、上发条 ratchet（棘轮咔哒串）、开盒轻响（低频木质轻叩 + 气声）。
/// 每个音高预合成 3 个力度层 buffer，按 velocity 选层调度。
public final class MusicBoxAudioEngine: ObservableObject {
    public let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format: AVAudioFormat

    /// [pitchIndex][velocityLayer]，力度层增益见 velocityGains。
    private var toneBuffers: [[AVAudioPCMBuffer]] = []
    private var clickBuffer: AVAudioPCMBuffer?
    private var ratchetBuffer: AVAudioPCMBuffer?
    private var lidBuffer: AVAudioPCMBuffer?

    private static let velocityGains: [Float] = [0.5, 0.78, 1.0]

    public init() {
        let outputFormat = engine.outputNode.outputFormat(forBus: 0)
        if outputFormat.sampleRate > 0 {
            format = outputFormat
        } else {
            // 极少数情况下引擎未就绪时格式采样率为 0，退回标准格式。
            format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        synthesizeAll()
        configureSession()
        startIfNeeded()
    }

    // MARK: - 对外接口

    /// 确保引擎与播放节点处于运行状态（幂等）。
    public func startIfNeeded() {
        if !engine.isRunning { try? engine.start() }
        if !player.isPlaying { player.play() }
    }

    /// 在指定宿主时间（CACurrentMediaTime 同一时钟域的秒数）发声；
    /// hostSeconds 为 nil 或已过期则立即发声。
    public func play(pitchIndex: Int, velocity: Double = 0.85, atHostSeconds hostSeconds: Double? = nil) {
        guard toneBuffers.indices.contains(pitchIndex) else { return }
        startIfNeeded()
        let layer = velocity < 0.68 ? 0 : (velocity < 0.9 ? 1 : 2)
        let buffer = toneBuffers[pitchIndex][layer]
        if let hostSeconds, hostSeconds > CACurrentMediaTime() + 0.005 {
            player.scheduleBuffer(buffer, at: AVAudioTime(hostTime: Self.hostTime(forSeconds: hostSeconds)))
        } else {
            player.scheduleBuffer(buffer, at: nil)
        }
    }

    /// 放钉/拆钉的清脆 click（编曲操作反馈）。
    public func playClick() { scheduleMechanical(clickBuffer) }

    /// 上发条棘轮声（WindingControl 每转过约 30° 触发一次）。
    public func playRatchet() { scheduleMechanical(ratchetBuffer) }

    /// 开盒/合盒的轻响。
    public func playLidSound() { scheduleMechanical(lidBuffer) }

    /// 立即停掉所有已排队未发出的声音（暂停时用）。
    public func stopAllScheduled() {
        player.stop()
    }

    // MARK: - 合成

    private func synthesizeAll() {
        toneBuffers = Pitch.allCases.map { pitch in
            Self.velocityGains.map { gain in
                synthesizeTone(frequency: pitch.frequency, gain: gain)
            }
        }
        clickBuffer = synthesizeClick()
        ratchetBuffer = synthesizeRatchet()
        lidBuffer = synthesizeLid()
    }

    /// 八音盒单音：非谐泛音 + 分层衰减。返回单声道样本后复制到各声道。
    private func synthesizeTone(frequency f: Double, gain: Float) -> AVAudioPCMBuffer {
        let sr = format.sampleRate
        let seconds = 1.8
        let count = Int(sr * seconds)
        // (泛音比, 相对幅度, 衰减时间常数秒) —— 高频泛音衰减远快于基频，这是金属音梳的听感特征。
        let partials: [(ratio: Double, amp: Double, tau: Double)] = [
            (1.00, 1.00, 0.85),
            (2.01, 0.10, 0.45),
            (3.98, 0.34, 0.30),
            (9.24, 0.13, 0.13),
            (16.80, 0.05, 0.06),
        ]
        var samples = [Float](repeating: 0, count: count)
        var peak: Float = 0
        for i in 0..<count {
            let t = Double(i) / sr
            // 3ms 线性起音，避免爆音。
            let attack = Float(min(1.0, t / 0.003))
            var v = 0.0
            for p in partials {
                v += p.amp * sin(2 * Double.pi * f * p.ratio * t) * exp(-t / p.tau)
            }
            // 起音瞬间 6ms 的拨弦噪声（确定性伪噪声，可复现）。
            if t < 0.02 {
                v += 0.18 * Double(Self.pseudoNoise(i)) * exp(-t / 0.004)
            }
            let s = Float(v) * attack * gain
            samples[i] = s
            if abs(s) > peak { peak = abs(s) }
        }
        let scale: Float = peak > 0 ? (0.85 / peak) : 1
        for i in 0..<count { samples[i] *= scale }
        return makeBuffer(samples: samples)
    }

    /// click：6ms 噪声突起 + 2.4kHz 短促正弦，模拟金属钉落位。
    private func synthesizeClick() -> AVAudioPCMBuffer {
        let sr = format.sampleRate
        let count = Int(sr * 0.06)
        var samples = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let t = Double(i) / sr
            let noise = Double(Self.pseudoNoise(i &+ 4096)) * exp(-t / 0.006)
            let blip = 0.5 * sin(2 * Double.pi * 2400 * t) * exp(-t / 0.009)
            samples[i] = Float(0.6 * noise + blip) * 0.7
        }
        return makeBuffer(samples: samples)
    }

    /// ratchet：一串 7 个递减的小咔哒，间隔 28ms，模拟棘轮逐齿滑过。
    private func synthesizeRatchet() -> AVAudioPCMBuffer {
        let sr = format.sampleRate
        let count = Int(sr * 0.24)
        var samples = [Float](repeating: 0, count: count)
        let clicks = 7
        for c in 0..<clicks {
            let start = Int(Double(c) * 0.028 * sr)
            let amp = 0.55 * (1.0 - Double(c) / Double(clicks) * 0.45)
            let len = Int(0.008 * sr)
            for j in 0..<len where start + j < count {
                let t = Double(j) / sr
                let v = Double(Self.pseudoNoise((start + j) &+ 8192)) * exp(-t / 0.0025)
                samples[start + j] += Float(amp * v)
            }
        }
        return makeBuffer(samples: samples)
    }

    /// 开盒轻响：160→70Hz 下滑正弦（木质轻叩）+ 一层柔和气声，总长 0.3s。
    private func synthesizeLid() -> AVAudioPCMBuffer {
        let sr = format.sampleRate
        let seconds = 0.3
        let count = Int(sr * seconds)
        var samples = [Float](repeating: 0, count: count)
        var phase = 0.0
        for i in 0..<count {
            let t = Double(i) / sr
            let freq = 160.0 - 90.0 * (t / seconds)
            phase += 2 * Double.pi * freq / sr
            let thock = sin(phase) * exp(-t / 0.07)
            let air = 0.25 * Double(Self.pseudoNoise(i &+ 16384)) * exp(-t / 0.05) * min(1, t / 0.01)
            samples[i] = Float(0.55 * thock + air) * 0.8
        }
        return makeBuffer(samples: samples)
    }

    // MARK: - 工具

    private func makeBuffer(samples: [Float]) -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount(samples.count)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let channels = Int(format.channelCount)
        for ch in 0..<channels {
            guard let data = buffer.floatChannelData?[ch] else { continue }
            for i in 0..<samples.count { data[i] = samples[i] }
        }
        return buffer
    }

    private func scheduleMechanical(_ buffer: AVAudioPCMBuffer?) {
        guard let buffer else { return }
        startIfNeeded()
        player.scheduleBuffer(buffer, at: nil)
    }

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
    }

    /// 确定性伪噪声（-1...1），保证每次合成结果一致、可测试。
    private static func pseudoNoise(_ i: Int) -> Float {
        let x = sin(Double(i) * 12.9898) * 43758.5453
        return Float(x - floor(x)) * 2 - 1
    }

    // MARK: - 宿主时间换算（mach_absolute_time 域）

    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t(numer: 0, denom: 0)
        mach_timebase_info(&info)
        return info
    }()

    /// 把"秒"（CACurrentMediaTime 时钟域，与 mach_absolute_time 同源）换算为 AVAudioTime 需要的宿主刻度。
    private static func hostTime(forSeconds seconds: Double) -> UInt64 {
        let nanos = seconds * 1_000_000_000
        return UInt64(nanos * Double(timebase.denom) / Double(timebase.numer))
    }
}
