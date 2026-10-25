import Foundation

/// 八个音高：C 大调 C5–C6。
/// rawValue 即 pitchIndex：0 在滚筒最左列（最低音 C5），7 在最右列（最高音 C6）。
/// 音高在滚筒上的轴向位置、音梳齿的排列、音频合成的频率全部以此为准，永不重排。
public enum Pitch: Int, CaseIterable, Codable, Equatable {
    case c5 = 0, d5, e5, f5, g5, a5, b5, c6

    public var index: Int { rawValue }

    /// 等平均律频率（Hz），A4 = 440。
    public var frequency: Double {
        switch self {
        case .c5: return 523.25
        case .d5: return 587.33
        case .e5: return 659.25
        case .f5: return 698.46
        case .g5: return 783.99
        case .a5: return 880.00
        case .b5: return 987.77
        case .c6: return 1046.50
        }
    }

    public var noteName: String {
        switch self {
        case .c5: return "C5"
        case .d5: return "D5"
        case .e5: return "E5"
        case .f5: return "F5"
        case .g5: return "G5"
        case .a5: return "A5"
        case .b5: return "B5"
        case .c6: return "C6"
        }
    }

    public var solfege: String {
        switch self {
        case .c5: return "Do"
        case .d5: return "Re"
        case .e5: return "Mi"
        case .f5: return "Fa"
        case .g5: return "Sol"
        case .a5: return "La"
        case .b5: return "Ti"
        case .c6: return "Do′"
        }
    }

    public static func at(index: Int) -> Pitch? { Pitch(rawValue: index) }
}

/// 一颗音钉 = 一次拨弦事件。
/// - pitchIndex: 滚筒轴向位置（0 = C5 … 7 = C6）
/// - step: 滚筒圆周位置（第几时间步，0 ..< Melody.stepCount）
/// - durationSteps: 音符持续步数（长音用它表达，例如《小星星》结尾的 G 持续 4 步）
/// - velocity: 力度 0...1，影响音量层
public struct NoteEvent: Codable, Equatable, Identifiable {
    public var pitchIndex: Int
    public var step: Int
    public var durationSteps: Int
    public var velocity: Double

    public var id: String { "\(pitchIndex)-\(step)" }

    public init(pitchIndex: Int, step: Int, durationSteps: Int = 1, velocity: Double = 0.85) {
        self.pitchIndex = pitchIndex
        self.step = step
        self.durationSteps = max(1, durationSteps)
        self.velocity = min(1, max(0, velocity))
    }
}

/// 一首旋律的全部数据。音频调度、滚筒动画、音钉编辑器、本地保存共享同一份 Melody，
/// 不允许任何模块私自维护第二份时间线。
public struct Melody: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var tempoBPM: Double
    public var stepCount: Int
    public var events: [NoteEvent]

    /// 每拍包含的时间步数：一步 = 一个八分音符。
    public static let stepsPerBeat = 2
    /// 滚筒音高列数（C5–C6）。
    public static let pitchCount = 8

    public init(id: UUID = UUID(),
                name: String,
                tempoBPM: Double = 100,
                stepCount: Int = 16,
                events: [NoteEvent] = []) {
        self.id = id
        self.name = name
        self.tempoBPM = min(200, max(40, tempoBPM))
        self.stepCount = min(64, max(8, stepCount))
        self.events = events.sorted { ($0.step, $0.pitchIndex) < ($1.step, $1.pitchIndex) }
    }

    // MARK: - 查询（纯函数）

    public func note(pitchIndex: Int, step: Int) -> NoteEvent? {
        events.first { $0.pitchIndex == pitchIndex && $0.step == step }
    }

    public func hasNote(pitchIndex: Int, step: Int) -> Bool {
        note(pitchIndex: pitchIndex, step: step) != nil
    }

    /// 某一步上要发声的全部音符（按音高升序），播放调度与音梳高亮共用。
    public func events(atStep step: Int) -> [NoteEvent] {
        events.filter { $0.step == step }.sorted { $0.pitchIndex < $1.pitchIndex }
    }

    public var isEmpty: Bool { events.isEmpty }

    // MARK: - 纯函数式编辑（返回新值，方便测试与撤销）

    /// 在 (pitch, step) 放一颗音钉；同格已有音钉时替换之。越界直接返回自身。
    public func addingNote(pitchIndex: Int, step: Int, durationSteps: Int = 1, velocity: Double = 0.85) -> Melody {
        guard (0..<Self.pitchCount).contains(pitchIndex), (0..<stepCount).contains(step) else { return self }
        var copy = self
        copy.events.removeAll { $0.pitchIndex == pitchIndex && $0.step == step }
        let clampedDuration = max(1, min(durationSteps, stepCount - step))
        copy.events.append(NoteEvent(pitchIndex: pitchIndex, step: step,
                                     durationSteps: clampedDuration, velocity: velocity))
        copy.events.sort { ($0.step, $0.pitchIndex) < ($1.step, $1.pitchIndex) }
        return copy
    }

    /// 拆除 (pitch, step) 上的音钉；没有则返回自身。
    public func removingNote(pitchIndex: Int, step: Int) -> Melody {
        guard hasNote(pitchIndex: pitchIndex, step: step) else { return self }
        var copy = self
        copy.events.removeAll { $0.pitchIndex == pitchIndex && $0.step == step }
        return copy
    }

    /// 点按滚筒网格的语义：有钉则拆、无钉则装。
    public func togglingNote(pitchIndex: Int, step: Int, durationSteps: Int = 1, velocity: Double = 0.85) -> Melody {
        hasNote(pitchIndex: pitchIndex, step: step)
            ? removingNote(pitchIndex: pitchIndex, step: step)
            : addingNote(pitchIndex: pitchIndex, step: step, durationSteps: durationSteps, velocity: velocity)
    }

    public func renamed(_ newName: String) -> Melody {
        var copy = self
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { copy.name = trimmed }
        return copy
    }

    public func withTempo(_ bpm: Double) -> Melody {
        var copy = self
        copy.tempoBPM = min(200, max(40, bpm))
        return copy
    }

    /// 调整时间步总数（16 → 32 扩展用）；超出新范围的音钉会被丢弃。
    public func resized(stepCount newCount: Int) -> Melody {
        var copy = self
        copy.stepCount = min(64, max(8, newCount))
        copy.events.removeAll { $0.step >= copy.stepCount }
        return copy
    }
}

// MARK: - 预置旋律（全部公版旋律 / 程序内写死，无任何外部素材）

public extension Melody {
    /// 《小星星》前 16 步：C C G G A A G——
    /// 一步 = 八分音符，四分音符占 2 步，结尾长音 G 占 4 步，正好填满 16 步。
    static let twinkleTwinkle = Melody(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        name: "小星星",
        tempoBPM: 100,
        stepCount: 16,
        events: [
            NoteEvent(pitchIndex: 0, step: 0, durationSteps: 2),   // C5
            NoteEvent(pitchIndex: 0, step: 2, durationSteps: 2),   // C5
            NoteEvent(pitchIndex: 4, step: 4, durationSteps: 2),   // G5
            NoteEvent(pitchIndex: 4, step: 6, durationSteps: 2),   // G5
            NoteEvent(pitchIndex: 5, step: 8, durationSteps: 2),   // A5
            NoteEvent(pitchIndex: 5, step: 10, durationSteps: 2),  // A5
            NoteEvent(pitchIndex: 4, step: 12, durationSteps: 4),  // G5 长音
        ])

    /// 《欢乐颂》片段（贝多芬，公版）：E E F G G F E D，每音 2 步，共 16 步。
    static let odeToJoy = Melody(
        id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
        name: "欢乐颂（片段）",
        tempoBPM: 104,
        stepCount: 16,
        events: [
            NoteEvent(pitchIndex: 2, step: 0, durationSteps: 2),   // E5
            NoteEvent(pitchIndex: 2, step: 2, durationSteps: 2),   // E5
            NoteEvent(pitchIndex: 3, step: 4, durationSteps: 2),   // F5
            NoteEvent(pitchIndex: 4, step: 6, durationSteps: 2),   // G5
            NoteEvent(pitchIndex: 4, step: 8, durationSteps: 2),   // G5
            NoteEvent(pitchIndex: 3, step: 10, durationSteps: 2),  // F5
            NoteEvent(pitchIndex: 2, step: 12, durationSteps: 2),  // E5
            NoteEvent(pitchIndex: 1, step: 14, durationSteps: 2),  // D5
        ])

    /// 空白模板：8 音高 × 16 步，无音钉。
    static let blankTemplate = Melody(
        id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
        name: "空白模板",
        tempoBPM: 100,
        stepCount: 16,
        events: [])

    /// 首次启动播种到旋律库的预置集合。
    static var presets: [Melody] { [twinkleTwinkle, odeToJoy, blankTemplate] }

    /// 生成一份带新 id 的空白旋律（用户新建编曲用）。
    static func makeBlank(name: String, stepCount: Int = 16, tempoBPM: Double = 100) -> Melody {
        Melody(id: UUID(), name: name, tempoBPM: tempoBPM, stepCount: stepCount, events: [])
    }
}
