import AVFoundation
import Foundation
import QuartzCore

/// 八音盒音频引擎：AVAudioEngine + AVAudioPlayerNode。
///
/// 所有声音都在启动时程序合成，工程不包含任何音频文件，也就没有素材版权问题：
/// - 音色：基频 + 非谐泛音列（3.98×、9.24×、16.8×，模拟金属音梳的非谐振动），
///   快速起音、各自独立的指数衰减，整体余韵约 1.2–1.8 秒；起音瞬间叠一丝拨弦噪声。
/// - 机械声：放钉 click、上发条 ratchet（棘轮单齿咔哒）、开盒轻响（低频木质轻叩 + 气声）。
/// 每个音高预合成 3 个力度层 buffer，按 velocity 选层调度。
public final class MusicBoxAudioEngine: ObservableObject {
    public let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    /// 机械声专用播放节点（click / ratchet / 开盒声）。
    /// 必须与音符分开：AVAudioPlayerNode 对 at:nil 调度是排队顺序播放的，播放中
    /// 音符 buffer（余韵 1.2–1.8 秒）排成长队，机械声若共用一个节点会被压在队尾
    /// 迟迟不出声（用户实测：正在播放时转上发条没有声音）。独立节点后机械声永远
    /// 立即发声，与音乐并行混合。
    private let mechanicalPlayer = AVAudioPlayerNode()
    /// 音符专用小房间混响（机械声不经过，保持干脆）。
    /// 程序合成的干声偏"实验室"，一层 13% 的小房间混响把每个音放进
    /// 一个虚拟木盒/房间里，是音质提升里感知最强的一项（内置单元、无素材）。
    private let toneReverb = AVAudioUnitReverb()
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
        engine.attach(toneReverb)
        toneReverb.loadFactoryPreset(.smallRoom)
        toneReverb.wetDryMix = 13
        engine.connect(player, to: toneReverb, format: format)
        engine.connect(toneReverb, to: engine.mainMixerNode, format: format)
        engine.attach(mechanicalPlayer)
        engine.connect(mechanicalPlayer, to: engine.mainMixerNode, format: format)
        synthesizeAll()
        configureSession()
        startIfNeeded()
    }

    // MARK: - 对外接口

    /// 确保引擎与播放节点处于运行状态（幂等）。
    public func startIfNeeded() {
        if !engine.isRunning { try? engine.start() }
        if !player.isPlaying { player.play() }
        if !mechanicalPlayer.isPlaying { mechanicalPlayer.play() }
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

    /// 上发条棘轮声：单个齿的"咔哒"（WindingControl 每转过约 15° 触发一次，
    /// 声响密度严格跟随手的转速，声音与动作同步）。
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
                // 声像按音高展开（低音偏左、高音偏右，±0.22）：真实音梳的
                // 低音齿在左、高音齿在右，听者正对机芯时有自然的横向分布。
                let pan = -0.22 + 0.44 * Double(pitch.index) / Double(Pitch.allCases.count - 1)
                return synthesizeTone(frequency: pitch.frequency, gain: gain, pan: pan)
            }
        }
        clickBuffer = synthesizeClick()
        ratchetBuffer = synthesizeRatchet()
        lidBuffer = synthesizeLid()
    }

    /// 八音盒单音：非谐泛音 + 分层衰减。返回单声道样本后复制到各声道。
    private func synthesizeTone(frequency f: Double, gain: Float, pan: Double = 0) -> AVAudioPCMBuffer {
        let sr = format.sampleRate
        let seconds = 1.8
        let count = Int(sr * seconds)
        // (泛音比, 相对幅度, 衰减时间常数秒) —— 高频泛音衰减远快于基频，这是金属音梳的听感特征。
        let partials: [(ratio: Double, amp: Double, tau: Double)] = [
            (1.00, 1.00, 0.85),
            (2.01, 0.10, 0.45),
            (3.98, 0.34, 0.30),
            (5.41, 0.05, 0.18),
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
            // 木腔共鸣（烤入样本）：168Hz 盒体基频 + 336Hz 一层，衰减快、
            // 只在起音段存在——给每个音一个"装在木盒里"的身体感。
            v += 0.10 * sin(2 * Double.pi * 168 * t) * exp(-t / 0.085)
            v += 0.045 * sin(2 * Double.pi * 336 * t) * exp(-t / 0.05)
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
        return makeStereoBuffer(samples: samples, pan: pan)
    }

    /// 立体声写入：等功率声像（左 = cos、右 = sin），声像角由 pitch 决定。
    private func makeStereoBuffer(samples: [Float], pan: Double) -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount(samples.count)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let theta = (pan + 1) * Double.pi / 4
        let leftGain = Float(cos(theta))
        let rightGain = Float(sin(theta))
        if let data = buffer.floatChannelData {
            let channels = Int(format.channelCount)
            for i in 0..<samples.count {
                data[0][i] = samples[i] * leftGain
                if channels > 1 { data[1][i] = samples[i] * rightGain }
            }
        }
        return buffer
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

    /// ratchet：单个棘轮齿的"咔哒"，约 45ms。
    /// 旧版是一次触发预合成 7 连响（0.24 秒声列），声列按固定节奏走完，与手的实际
    /// 转速脱节——慢转时声音先跑完、快转时又叠在一起，用户反馈"上发条不同步声音"。
    /// 改为一齿一响：噪声冲击（齿尖弹入齿根）+ 2.1kHz 金属余响（棘爪簧片），
    /// 转得快响得密、停手即无声，声音严格由动作驱动。
    private func synthesizeRatchet() -> AVAudioPCMBuffer {
        let sr = format.sampleRate
        let count = Int(sr * 0.045)
        var samples = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let t = Double(i) / sr
            let impact = Double(Self.pseudoNoise(i &+ 8192)) * exp(-t / 0.0022)
            let ring = 0.35 * sin(2 * Double.pi * 2100 * t) * exp(-t / 0.009)
            samples[i] = Float(0.55 * impact + ring)
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
        mechanicalPlayer.scheduleBuffer(buffer, at: nil)
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
