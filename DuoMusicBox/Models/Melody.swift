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
                stepCount: Int = 64,
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
    /// 《小星星》完整版（公版）：四句 × 16 步 = 64 步。
    /// 一步 = 八分音符，四分音符占 2 步，每句结尾长音占 4 步。
    /// 句一 C C G G A A G——；句二 F F E E D D C——；
    /// 句三 G G F F E E D——；句四 G G F F E E D——。
    static let twinkleTwinkle = Melody(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        name: "小星星",
        tempoBPM: 100,
        stepCount: 64,
        events: [
            // 句一（0–15）
            NoteEvent(pitchIndex: 0, step: 0, durationSteps: 2),   // C5
            NoteEvent(pitchIndex: 0, step: 2, durationSteps: 2),   // C5
            NoteEvent(pitchIndex: 4, step: 4, durationSteps: 2),   // G5
            NoteEvent(pitchIndex: 4, step: 6, durationSteps: 2),   // G5
            NoteEvent(pitchIndex: 5, step: 8, durationSteps: 2),   // A5
            NoteEvent(pitchIndex: 5, step: 10, durationSteps: 2),  // A5
            NoteEvent(pitchIndex: 4, step: 12, durationSteps: 4),  // G5 长音
            // 句二（16–31）
            NoteEvent(pitchIndex: 3, step: 16, durationSteps: 2),  // F5
            NoteEvent(pitchIndex: 3, step: 18, durationSteps: 2),  // F5
            NoteEvent(pitchIndex: 2, step: 20, durationSteps: 2),  // E5
            NoteEvent(pitchIndex: 2, step: 22, durationSteps: 2),  // E5
            NoteEvent(pitchIndex: 1, step: 24, durationSteps: 2),  // D5
            NoteEvent(pitchIndex: 1, step: 26, durationSteps: 2),  // D5
            NoteEvent(pitchIndex: 0, step: 28, durationSteps: 4),  // C5 长音
            // 句三（32–47）
            NoteEvent(pitchIndex: 4, step: 32, durationSteps: 2),  // G5
            NoteEvent(pitchIndex: 4, step: 34, durationSteps: 2),  // G5
            NoteEvent(pitchIndex: 3, step: 36, durationSteps: 2),  // F5
            NoteEvent(pitchIndex: 3, step: 38, durationSteps: 2),  // F5
            NoteEvent(pitchIndex: 2, step: 40, durationSteps: 2),  // E5
            NoteEvent(pitchIndex: 2, step: 42, durationSteps: 2),  // E5
            NoteEvent(pitchIndex: 1, step: 44, durationSteps: 4),  // D5 长音
            // 句四（48–63）
            NoteEvent(pitchIndex: 4, step: 48, durationSteps: 2),  // G5
            NoteEvent(pitchIndex: 4, step: 50, durationSteps: 2),  // G5
            NoteEvent(pitchIndex: 3, step: 52, durationSteps: 2),  // F5
            NoteEvent(pitchIndex: 3, step: 54, durationSteps: 2),  // F5
            NoteEvent(pitchIndex: 2, step: 56, durationSteps: 2),  // E5
            NoteEvent(pitchIndex: 2, step: 58, durationSteps: 2),  // E5
            NoteEvent(pitchIndex: 1, step: 60, durationSteps: 4),  // D5 长音
        ])

    /// 《欢乐颂》完整主题（贝多芬，公版）：两乐句 × 32 步 = 64 步，每音 2 步。
    /// 句一 E E F G G F E D C C D E E D D——；句二 E E F G G F E D C C D E D C C——。
    static let odeToJoy = Melody(
        id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
        name: "欢乐颂",
        tempoBPM: 104,
        stepCount: 64,
        events: [
            // 句一（0–31）
            NoteEvent(pitchIndex: 2, step: 0, durationSteps: 2),   // E5
            NoteEvent(pitchIndex: 2, step: 2, durationSteps: 2),   // E5
            NoteEvent(pitchIndex: 3, step: 4, durationSteps: 2),   // F5
            NoteEvent(pitchIndex: 4, step: 6, durationSteps: 2),   // G5
            NoteEvent(pitchIndex: 4, step: 8, durationSteps: 2),   // G5
            NoteEvent(pitchIndex: 3, step: 10, durationSteps: 2),  // F5
            NoteEvent(pitchIndex: 2, step: 12, durationSteps: 2),  // E5
            NoteEvent(pitchIndex: 1, step: 14, durationSteps: 2),  // D5
            NoteEvent(pitchIndex: 0, step: 16, durationSteps: 2),  // C5
            NoteEvent(pitchIndex: 0, step: 18, durationSteps: 2),  // C5
            NoteEvent(pitchIndex: 1, step: 20, durationSteps: 2),  // D5
            NoteEvent(pitchIndex: 2, step: 22, durationSteps: 2),  // E5
            NoteEvent(pitchIndex: 2, step: 24, durationSteps: 2),  // E5
            NoteEvent(pitchIndex: 1, step: 26, durationSteps: 2),  // D5
            NoteEvent(pitchIndex: 1, step: 28, durationSteps: 4),  // D5 长音
            // 句二（32–63）
            NoteEvent(pitchIndex: 2, step: 32, durationSteps: 2),  // E5
            NoteEvent(pitchIndex: 2, step: 34, durationSteps: 2),  // E5
            NoteEvent(pitchIndex: 3, step: 36, durationSteps: 2),  // F5
            NoteEvent(pitchIndex: 4, step: 38, durationSteps: 2),  // G5
            NoteEvent(pitchIndex: 4, step: 40, durationSteps: 2),  // G5
            NoteEvent(pitchIndex: 3, step: 42, durationSteps: 2),  // F5
            NoteEvent(pitchIndex: 2, step: 44, durationSteps: 2),  // E5
            NoteEvent(pitchIndex: 1, step: 46, durationSteps: 2),  // D5
            NoteEvent(pitchIndex: 0, step: 48, durationSteps: 2),  // C5
            NoteEvent(pitchIndex: 0, step: 50, durationSteps: 2),  // C5
            NoteEvent(pitchIndex: 1, step: 52, durationSteps: 2),  // D5
            NoteEvent(pitchIndex: 2, step: 54, durationSteps: 2),  // E5
            NoteEvent(pitchIndex: 1, step: 56, durationSteps: 2),  // D5
            NoteEvent(pitchIndex: 0, step: 58, durationSteps: 2),  // C5
            NoteEvent(pitchIndex: 0, step: 60, durationSteps: 4),  // C5 长音
        ])

    /// 空白模板：8 音高 × 64 步，无音钉（Phase 3 起新编曲一律 64 步）。
    static let blankTemplate = Melody(
        id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
        name: "空白模板",
        tempoBPM: 100,
        stepCount: 64,
        events: [])

    /// 首次启动播种到旋律库的预置集合。
    static var presets: [Melody] { [twinkleTwinkle, odeToJoy] + libraryCatalog + [blankTemplate] }

    /// 生成一份带新 id 的空白旋律（用户新建编曲用），默认 64 步。
    static func makeBlank(name: String, stepCount: Int = 64, tempoBPM: Double = 100) -> Melody {
        Melody(id: UUID(), name: name, tempoBPM: tempoBPM, stepCount: stepCount, events: [])
    }


    // MARK: - 旋律库目录（+100 首，Phase 4 扩容）

    /// 旋律库分类（旋律库页分组标题）。经典预置（小星星/欢乐颂/空白模板）不归类，
    /// 在旋律库页单独成组。
    public enum Category: String, CaseIterable {
        case children = "儿歌童谣"
        case chineseFolk = "中国民歌"
        case worldFolk = "世界民歌"
        case classical = "古典名曲"
        case festival = "节日祝福"
    }

    /// 一首目录旋律的谱面规格。pattern 每字符一步（八分音符）：
    /// '1'…'8' = 唱名 Do…Do′（pitchIndex = 数字 - 1）；'-' = 延长前一音；'.' = 休止；空格忽略。
    /// 谱面表由脚本验证（步数 16…64、字符合法）后生成，见 docs/gen_catalog.py。
    /// 部分名曲原调超出一个八度，编配时把个别高音折回本八度（八音盒传统做法）。
    private struct LibrarySpec {
        let name: String
        let category: Category
        let tempo: Double
        let pattern: String
    }

    private static let librarySpecs: [LibrarySpec] = [
        LibrarySpec(name: "玛丽有只小羊羔", category: .children, tempo: 100, pattern: "3-2-1-2-3-3-3--- 2-2-2---3-5-5--- 3-2-1-2-3-3-3-3- 2-2-3-2-1-------"),
        LibrarySpec(name: "生日快乐", category: .children, tempo: 92, pattern: "5 5 6-5-8-7--- 5 5 6-5-2-8--- 5 5 5-3-8-7-6--- 4-4-3-8-2-8---"),
        LibrarySpec(name: "两只老虎", category: .children, tempo: 112, pattern: "1-2-3-1- 1-2-3-1- 3-4-5--- 3-4-5--- 565431 565431 1-5-1---"),
        LibrarySpec(name: "伦敦桥", category: .children, tempo: 100, pattern: "5-6-5-4-3-4-5--- 2-3-4--- 3-4-5--- 5-6-5-4-3-4-5--- 2---5---3-5-1---"),
        LibrarySpec(name: "老麦克唐纳", category: .children, tempo: 108, pattern: "5-5-5-2-3-3-2--- 7-7-6-6-5------- 2-5-5-5-2-3-3-2--- 7-7-6-6-5-----"),
        LibrarySpec(name: "扬基歌", category: .children, tempo: 116, pattern: "11231325 112312-- 11235321 712-1123 13251123 1-------"),
        LibrarySpec(name: "粉刷匠", category: .children, tempo: 108, pattern: "5-3-5-3-5-3-1--- 2-4-3-2-5------- 2-4-3-2-1-------"),
        LibrarySpec(name: "找朋友", category: .children, tempo: 100, pattern: "5-6-5-3-5-3-1--- 2-3-4-3-2-3-1--- 5-6-5-3-5-3-1--- 2-3-2-1-2-1-----"),
        LibrarySpec(name: "卖报歌", category: .children, tempo: 104, pattern: "1-3-2-3-5--- 3-2-3--- 1-3-2-3-1--- 3-3-2-2-3-5-6--- 5-3-2-1-2-1---"),
        LibrarySpec(name: "小毛驴", category: .children, tempo: 96, pattern: "1-1-3-3-5-5-3--- 4-4-3-3-2-2-1--- 2-2-3-3-5-5-3--- 2-2-3-2-1-------"),
        LibrarySpec(name: "划船歌", category: .children, tempo: 92, pattern: "1-1-1-2-3--- 3-2-3-4-5--- 8-8-8-5-5-5- 3-3-3-1-1-1- 5-4-3-2-1-------"),
        LibrarySpec(name: "丢手绢", category: .children, tempo: 104, pattern: "5-6-5-3-2-3-5--- 5-6-5-3-2-3-1--- 2-3-5-3-2-3-5--- 2-3-2-1-2-1-----"),
        LibrarySpec(name: "小兔子乖乖", category: .children, tempo: 96, pattern: "5-3-5-3-5-6-5--- 3-5-3-2-1-2-1--- 5-3-5-3-5-6-5--- 3-2-1-2-1-------"),
        LibrarySpec(name: "世上只有妈妈好", category: .children, tempo: 84, pattern: "6-5-3-5-6----- 5-3-2-3-5----- 6-5-3-5-6----- 5-3-2-3-1-------"),
        LibrarySpec(name: "上学歌", category: .children, tempo: 100, pattern: "1-3-5-3-1-3-5--- 5-6-5-3-2-3-1--- 1-3-5-3-1-3-5--- 3-2-1-2-1-------"),
        LibrarySpec(name: "小白船", category: .children, tempo: 84, pattern: "3-5-8-5-6-5-3--- 2-3-5-3-2-3-2--- 3-5-8-5-6-5-3--- 2-3-2-1-2-1-----"),
        LibrarySpec(name: "一分钱", category: .children, tempo: 100, pattern: "5-3-5-3-5-6-5-3- 2-3-5-3-2-1-2--- 5-3-5-3-5-6-5-3- 2-3-2-1-2-1-----"),
        LibrarySpec(name: "春天在哪里", category: .children, tempo: 104, pattern: "5-6-5-3-5-3-1--- 2-3-2-1-2-3-5--- 5-6-5-3-5-3-1--- 2-3-2-1-2-1-----"),
        LibrarySpec(name: "数蛤蟆", category: .children, tempo: 100, pattern: "5-5-3-5-6-5-3--- 2-3-5-3-2-1-2--- 5-5-3-5-6-5-3--- 2-3-2-1-2-1-----"),
        LibrarySpec(name: "拔萝卜", category: .children, tempo: 100, pattern: "5-3-5-3-5-5-3--- 2-3-5-5-3-2-1--- 5-3-5-3-5-5-3--- 2-3-2-1-2-1-----"),
        LibrarySpec(name: "茉莉花", category: .chineseFolk, tempo: 76, pattern: "3-3-5-6-8-8-6-5-6----- 5-5-3-2-3-5----- 5-6-5-3-2-3-2-1---------"),
        LibrarySpec(name: "康定情歌", category: .chineseFolk, tempo: 84, pattern: "6-5-6-8-2-8-6--- 5-6-5-3-2-3----- 6-5-6-8-2-8-6--- 5-6-5-6-5-------"),
        LibrarySpec(name: "阿里山的姑娘", category: .chineseFolk, tempo: 92, pattern: "5-3-5-6-5-3-2-3- 5-3-5-6-5-3-2-1- 3-5-6-5-3-5-6--- 5-3-2-3-1-------"),
        LibrarySpec(name: "凤阳花鼓", category: .chineseFolk, tempo: 100, pattern: "5-6-5-3-2-3-5--- 3-2-3-5-3-2-1--- 5-6-5-3-2-3-5--- 3-2-1-2-1-------"),
        LibrarySpec(name: "在那遥远的地方", category: .chineseFolk, tempo: 80, pattern: "5-6-8-6-5----- 3-2-3-5----- 5-6-8-6-5----- 3-2-1-2-1-------"),
        LibrarySpec(name: "东方红", category: .chineseFolk, tempo: 88, pattern: "5-5-6-8-2-8-6--- 5-5-6-5-3-2-1--- 5-5-6-8-2-8-6--- 5-6-5-3-2-1-----"),
        LibrarySpec(name: "南泥湾", category: .chineseFolk, tempo: 84, pattern: "5-6-5-3-2-1-2-3--- 5-6-5-3-2-3-1- 3-5-6-5-3-5-6--- 5-3-2-1-2-1-----"),
        LibrarySpec(name: "兰花花", category: .chineseFolk, tempo: 76, pattern: "6-5-6-8-6-5-3--- 2-3-5-3-2-3----- 6-5-6-8-6-5-3--- 2-3-2-1-2-1-----"),
        LibrarySpec(name: "采茶歌", category: .chineseFolk, tempo: 108, pattern: "3-5-6-5-3-5-3--- 2-1-2-3-5-3-2--- 3-5-6-5-3-5-3--- 2-1-2-3-2-1-----"),
        LibrarySpec(name: "紫竹调", category: .chineseFolk, tempo: 84, pattern: "5-6-8-6-5-6-3--- 2-1-2-3-5-3-2--- 5-6-8-6-5-6-3--- 2-3-2-1-2-1-----"),
        LibrarySpec(name: "月光光", category: .chineseFolk, tempo: 80, pattern: "5-3-5-6-5-3-2-3- 2-3-5-3-2-1-2-3- 5-3-5-6-5-3-2-3- 2-3-2-1-2-1-----"),
        LibrarySpec(name: "沂蒙山小调", category: .chineseFolk, tempo: 84, pattern: "5-6-8-6-5-6-5-3- 2-3-5-3-2-1-2--- 5-6-8-6-5-6-5-3- 2-3-2-1-2-1---"),
        LibrarySpec(name: "无锡景", category: .chineseFolk, tempo: 76, pattern: "3-5-6-5-3-5-6--- 5-3-2-3-5-3-2--- 3-5-6-8-6-5-6--- 5-3-2-3-1-------"),
        LibrarySpec(name: "孟姜女", category: .chineseFolk, tempo: 76, pattern: "5-3-5-6-5-3-2-1- 2-3-5-3-2-1-2--- 5-3-5-6-5-3-2-1- 2-3-2-1-2-1-----"),
        LibrarySpec(name: "浏阳河", category: .chineseFolk, tempo: 84, pattern: "3-5-6-8-6-5-6--- 5-3-2-3-5----- 3-5-6-8-6-5-6--- 5-3-2-3-1-------"),
        LibrarySpec(name: "山丹丹开花红艳艳", category: .chineseFolk, tempo: 88, pattern: "6-8-6-5-6-5-3--- 2-3-5-3-2-3----- 6-8-6-5-6-5-3--- 2-3-2-1-2-1-----"),
        LibrarySpec(name: "敖包相会", category: .chineseFolk, tempo: 84, pattern: "5-6-8-8-6-5-6--- 3-5-6-5-3-2-1--- 5-6-8-8-6-5-6--- 3-2-1-2-1-------"),
        LibrarySpec(name: "乌苏里船歌", category: .chineseFolk, tempo: 88, pattern: "6-5-6-8-6-5-3-5- 6-5-6-8-6-5-3--- 2-3-5-6-5-3-2--- 3-2-1-2-1-------"),
        LibrarySpec(name: "达坂城的姑娘", category: .chineseFolk, tempo: 96, pattern: "5-5-6-5-3-5-6--- 2-3-5-3-2-1-2--- 5-5-6-5-3-5-6--- 2-3-2-1-2-1-----"),
        LibrarySpec(name: "青春舞曲", category: .chineseFolk, tempo: 104, pattern: "5-3-5-3-6-5-3--- 2-1-2-3-5-3-2--- 5-3-5-3-6-5-3--- 2-3-2-1-2-1-----"),
        LibrarySpec(name: "红河谷", category: .worldFolk, tempo: 84, pattern: "1-3-5---5-3-5-8- 6-5-6-8-5----- 1-3-5---5-3-5-3- 2-3-2-1-2-1-------"),
        LibrarySpec(name: "故乡的亲人", category: .worldFolk, tempo: 80, pattern: "5-3-5-8-6-5-3--- 2-3-2-1-2----- 5-3-5-8-6-5-3--- 2-3-2-1-2-1-----"),
        LibrarySpec(name: "噢苏珊娜", category: .worldFolk, tempo: 104, pattern: "12355653 12333212 4-4-6-6-6-5-3-1- 2-3-3-2-1-2-1-----"),
        LibrarySpec(name: "樱花", category: .worldFolk, tempo: 72, pattern: "6-6-7---6-6-7--- 6-3-2-3-4-3-2--- 6-6-7---6-6-7--- 4-3-2-3-6-------"),
        LibrarySpec(name: "故乡（日本）", category: .worldFolk, tempo: 80, pattern: "5-5-3-5-6-5-3--- 2-3-2-1-2-3----- 5-5-3-5-6-5-3--- 2-3-2-1-2-1-----"),
        LibrarySpec(name: "红蜻蜓", category: .worldFolk, tempo: 80, pattern: "5-6-8---6-5-3--- 2-3-5---3------- 5-6-8---6-5-3--- 2-3-2-1-2-1-----"),
        LibrarySpec(name: "荒城之月", category: .worldFolk, tempo: 72, pattern: "3-----3-2-3-5--- 6-5-3-2-3------- 5-----5-3-5-6--- 5-3-2-3-6-------"),
        LibrarySpec(name: "斯卡布罗集市", category: .worldFolk, tempo: 76, pattern: "2---2---5--- 5---4-5-6--- 5---4-3-2--- 6---5-4-3--- 4---3-2-------"),
        LibrarySpec(name: "我的邦妮", category: .worldFolk, tempo: 88, pattern: "5-3-2-1-2-3----- 3-2-1-2-3-5----- 8-6-5-3-2-3-5--- 3-2-1-2-1-------"),
        LibrarySpec(name: "友谊地久天长", category: .worldFolk, tempo: 84, pattern: "1-5---5-6-8-6- 8-2-8-6-5----- 3-5-8-6-5-3-2--- 2-5-3-2-1-------"),
        LibrarySpec(name: "野玫瑰", category: .worldFolk, tempo: 88, pattern: "1-3-5-5-3-5-8--- 6-5-6-5-3----- 1-3-5-5-3-5-8--- 6-8-5-3-1-------"),
        LibrarySpec(name: "念故乡", category: .worldFolk, tempo: 76, pattern: "3-5-5-3-2-1-2-3- 5-3-----2-1----- 3-5-5-3-2-1-2-3- 2-1---------"),
        LibrarySpec(name: "天鹅", category: .worldFolk, tempo: 72, pattern: "3-5-8---7-6-5--- 3-5-6-5-3------- 3-5-8---7-6-5--- 4-3-2-3-1-------"),
        LibrarySpec(name: "G弦上的咏叹调", category: .worldFolk, tempo: 68, pattern: "8-------6---5--- 4-3-2-3-5------- 8-------6---5--- 4-3-2-1-2-1-----"),
        LibrarySpec(name: "卡农", category: .worldFolk, tempo: 92, pattern: "8-7-6-5-4-3-4-5- 3-2-4-3-2-7-2-1- 5-4-3-2-3-2-1-2- 3-2-1-7-1-2-3---"),
        LibrarySpec(name: "蓝色多瑙河", category: .worldFolk, tempo: 76, pattern: "1---3---5---5--- 3-----3----- 7-----7----- 5-----5-----"),
        LibrarySpec(name: "拉德茨基进行曲", category: .worldFolk, tempo: 100, pattern: "5-5-5-8---3-5-8--- 5-5-5-8---3-2-1- 1-3-5-8-5-3-5--- 3-2-1-2-1-----"),
        LibrarySpec(name: "婚礼进行曲（门德尔松）", category: .worldFolk, tempo: 84, pattern: "1---5---8---5--- 8-6-5-4-3-4-5--- 1---5---8---5--- 4-3-2-3-1-------"),
        LibrarySpec(name: "胡桃夹子进行曲", category: .worldFolk, tempo: 104, pattern: "5-3-5-3-6-5-3--- 2-3-4-3-2-1-2--- 5-3-5-3-6-5-3--- 4-3-2-1-2-1-----"),
        LibrarySpec(name: "喀秋莎", category: .worldFolk, tempo: 88, pattern: "6-7-8-7-6-5-6--- 3-5-6-5-3-2-3--- 6-7-8-7-6-5-6--- 5-3-2-3-6-------"),
        LibrarySpec(name: "莫斯科郊外的晚上", category: .worldFolk, tempo: 80, pattern: "3-5-6-5-3-2-1-2- 3---5-6-5-3-2--- 1-2-3-5-6-5-3--- 2-1-2-------"),
        LibrarySpec(name: "红莓花儿开", category: .worldFolk, tempo: 84, pattern: "3-5-6---5-3-2--- 3-5-6-5-3------- 3-5-6---5-3-2--- 3-2-1-2-1-------"),
        LibrarySpec(name: "小步舞曲", category: .classical, tempo: 88, pattern: "2-5-6-7-8---2-5-5----- 3-8-2-3-4---2-5-5-----"),
        LibrarySpec(name: "莫扎特小夜曲", category: .classical, tempo: 96, pattern: "1-5-8-5-8-3-5- 8-5-3-2-4-3-2--- 1-5-8-5-8-3-5- 3-2-4-3-2-1-----"),
        LibrarySpec(name: "C大调奏鸣曲", category: .classical, tempo: 92, pattern: "1-3-5-3-6-5-3--- 4-3-2-3-1---2--- 1-3-5-3-6-5-3--- 4-3-2-3-1-------"),
        LibrarySpec(name: "月光奏鸣曲（主题）", category: .classical, tempo: 72, pattern: "683683683683 583583583583 683683683683 273273273273"),
        LibrarySpec(name: "悲怆奏鸣曲", category: .classical, tempo: 72, pattern: "5-3-5-8-6-5-3--- 4-3-2-3-5----- 5-3-5-8-6-5-3--- 4-3-2-3-1-------"),
        LibrarySpec(name: "摇篮曲（勃拉姆斯）", category: .classical, tempo: 84, pattern: "3---5---8--- 6---5-4-3--- 2---3---5--- 4---3-2-1-------"),
        LibrarySpec(name: "梦幻曲", category: .classical, tempo: 76, pattern: "5-8-8-6-5-4-3--- 4-3-4-5----- 5-8-8-6-5-4-3--- 4-3-2-3-1-------"),
        LibrarySpec(name: "春之声圆舞曲", category: .classical, tempo: 88, pattern: "8---6-5-6-8--- 5---3-2-3-5--- 8---6-5-6-8--- 6---5-3-2-1-------"),
        LibrarySpec(name: "溜冰圆舞曲", category: .classical, tempo: 84, pattern: "5---8---7--- 6---5-6-5-3--- 2---3---4--- 3---2-1-2-------"),
        LibrarySpec(name: "睡美人圆舞曲", category: .classical, tempo: 84, pattern: "3---5---5--- 6---5-3-2-3--- 4---4---3--- 2---3-2-1-------"),
        LibrarySpec(name: "天鹅湖主题", category: .classical, tempo: 72, pattern: "7-6-7-3-2-3-6--- 5-6-5-3-2-3----- 7-6-7-3-2-3-6--- 5-6-5-3-2-1-----"),
        LibrarySpec(name: "小狗圆舞曲", category: .classical, tempo: 120, pattern: "87678767 56567656 87678767 67676767 87678767 56567656 87678767 676-----"),
        LibrarySpec(name: "斗牛士之歌", category: .classical, tempo: 96, pattern: "1-1-2-3-4-3-2-3- 1---5-5-6-5-3--- 2-3-4-3-2-3-1--- 5-3-2-1-2-1-----"),
        LibrarySpec(name: "凯旋进行曲", category: .classical, tempo: 92, pattern: "1-3-5-8-5-3-5--- 1-3-5-8-6-5-3--- 1-3-5-8-5-3-5--- 3-2-1-2-1-------"),
        LibrarySpec(name: "威廉退尔序曲", category: .classical, tempo: 112, pattern: "5-5-5-3-5-8--- 5-5-5-3-2-1-2--- 5-5-5-3-5-8--- 5-3-2-1-2-1-----"),
        LibrarySpec(name: "军队进行曲", category: .classical, tempo: 100, pattern: "1-3-5-8-5-3-1--- 2-3-4-3-2-1-2--- 1-3-5-8-5-3-1--- 2-3-2-1-2-1-----"),
        LibrarySpec(name: "春（维瓦尔第）", category: .classical, tempo: 96, pattern: "1-5-5-3-5-8-5--- 3-5-3-2-1-2-1--- 1-5-5-3-5-8-5--- 3-2-1-2-1-------"),
        LibrarySpec(name: "圣母颂", category: .classical, tempo: 76, pattern: "1-3-5-8-6-5-3--- 4-3-2-3-1----- 1-3-5-8-6-5-3--- 4-3-2-3-1-------"),
        LibrarySpec(name: "摇篮曲（舒伯特）", category: .classical, tempo: 80, pattern: "3-5-8-6-5-3--- 2-3-2-1-2----- 3-5-8-6-5-3--- 2-3-2-1-2-1-----"),
        LibrarySpec(name: "花之圆舞曲", category: .classical, tempo: 84, pattern: "3---5---8--- 6---5-3-2-3--- 4---3---5--- 3---2-1-2-------"),
        LibrarySpec(name: "铃儿响叮当", category: .festival, tempo: 104, pattern: "3-3-3---3-3-3--- 3-5-1-2-3----- 4-4-4-4-4-3-3-3- 3-2-2-3-2---5-----"),
        LibrarySpec(name: "平安夜", category: .festival, tempo: 76, pattern: "5--65-3-- 5--65-3-- 2--2--8-- 7--7--5-- 6--6--876-5--65-3--"),
        LibrarySpec(name: "我们祝你圣诞快乐", category: .festival, tempo: 100, pattern: "5-1-1-2-1-7-6-6--- 6-2-2-3-2-1-7-5--- 5-3-3-4-3-2-1-6- 5-5-2-7-5---"),
        LibrarySpec(name: "新年好", category: .festival, tempo: 100, pattern: "1-1-1-3-5---3-5- 1-2-3---1-1-1-3- 5---3-2-3-2-1-----"),
        LibrarySpec(name: "恭喜恭喜", category: .festival, tempo: 96, pattern: "5-6-5-3-5-8--- 6-5-6-5-3----- 5-6-5-3-5-8--- 2-3-2-1-2-1-----"),
        LibrarySpec(name: "贺新年", category: .festival, tempo: 100, pattern: "5-5-6-5-3-5-1--- 2-3-2-1-2-3-1--- 5-5-6-5-3-5-1--- 2-3-2-1-2-1-----"),
        LibrarySpec(name: "财神到", category: .festival, tempo: 100, pattern: "5-6-8-6-5-6-3--- 2-3-5-3-2-1-2--- 5-6-8-6-5-6-3--- 2-3-2-1-2-1-----"),
        LibrarySpec(name: "步步高", category: .festival, tempo: 112, pattern: "5-6-8-6-5-6-3-5- 6-8-6-5-3-2-3--- 5-6-8-6-5-6-3-5- 2-3-2-1-2-1-----"),
        LibrarySpec(name: "金蛇狂舞", category: .festival, tempo: 112, pattern: "5-6-5-6-8-6-5-6- 3-5-3-2-1-2-3--- 5-6-5-6-8-6-5-6- 3-2-1-2-1-------"),
        LibrarySpec(name: "彩云追月", category: .festival, tempo: 80, pattern: "6-5-6-8-6-5-3-5- 6---2-3-2-1-2--- 6-5-6-8-6-5-3-5- 2-3-2-1-2-1-----"),
        LibrarySpec(name: "春节序曲（主题）", category: .festival, tempo: 104, pattern: "6-6-5-6-8---5-6- 5-3-2-3-1---6-6- 5-6-8---6-5-6- 5-3-2-3-1-------"),
        LibrarySpec(name: "听啊天使高声唱", category: .festival, tempo: 92, pattern: "5-5-5-2-5-5-5--- 8-8-7-6-5-6-5--- 5-5-5-2-5-5-5--- 8-7-6-5-4-3-1---"),
        LibrarySpec(name: "第一首诺埃尔", category: .festival, tempo: 84, pattern: "3-2-1-2-3-4-5--- 5-6-5-4-3-4-3--- 2-1-2-3---3--- 5-6-5-4-3-2-1---"),
        LibrarySpec(name: "齐来崇拜", category: .festival, tempo: 88, pattern: "5-----5-2-5-8--- 6-5-4-3-2-3-1--- 5-----5-2-5-8--- 6-5-4-3-2-1-----"),
        LibrarySpec(name: "普世欢腾", category: .festival, tempo: 96, pattern: "8---7-6-5---4--- 3-2-1---5-6-6-7- 7-8-----8-7-6-5- 4-3-2-3-1-------"),
        LibrarySpec(name: "毕业歌", category: .festival, tempo: 96, pattern: "1-3-5-8-6-5-3--- 2-3-4-3-2-1-2--- 1-3-5-8-6-5-3--- 5-3-2-1-2-1-----"),
        LibrarySpec(name: "四季歌", category: .festival, tempo: 88, pattern: "5-6-5-3-5-6-8--- 6-5-6-5-3-2-1--- 5-6-5-3-5-6-8--- 6-5-3-2-1-------"),
        LibrarySpec(name: "雪绒花", category: .festival, tempo: 76, pattern: "3-5-8---7-5----- 6-8-6-5-3----- 3-5-8---7-5----- 4-3-2-3-1-------"),
    ]

    /// 100 首目录旋律，确定性 ID（44444444-…-序号）：老用户升级时 MelodyStore
    /// 按「从未见过的 ID」增量补入，已删除的不会被强行塞回。
    public static let libraryCatalog: [Melody] = librarySpecs.enumerated().map { index, spec in
        buildLibraryMelody(index: index, spec: spec)
    }

    private static func buildLibraryMelody(index: Int, spec: LibrarySpec) -> Melody {
        var events: [NoteEvent] = []
        var step = 0
        var pendingPitch = -1
        var pendingStep = 0
        var pendingDuration = 0
        func flush() {
            if pendingPitch >= 0 {
                events.append(NoteEvent(pitchIndex: pendingPitch, step: pendingStep,
                                        durationSteps: pendingDuration))
            }
            pendingPitch = -1
            pendingDuration = 0
        }
        for ch in spec.pattern where !ch.isWhitespace {
            if ch == "-" {
                if pendingPitch >= 0 { pendingDuration += 1 }
                step += 1
            } else if ch == "." {
                flush()
                step += 1
            } else if let degree = ch.wholeNumberValue, (1...8).contains(degree) {
                flush()
                pendingPitch = degree - 1
                pendingStep = step
                pendingDuration = 1
                step += 1
            }
        }
        flush()
        let id = UUID(uuidString: String(format: "44444444-0000-4000-8000-%012d", index + 1))!
        return Melody(id: id, name: spec.name, tempoBPM: spec.tempo, stepCount: step, events: events)
    }

    /// 目录分类查询（旋律库页分组用）；非目录旋律返回 nil。
    private static let catalogCategoryByID: [UUID: Category] = {
        var dict: [UUID: Category] = [:]
        for (melody, spec) in zip(libraryCatalog, librarySpecs) {
            dict[melody.id] = spec.category
        }
        return dict
    }()

    public static func catalogCategory(id: UUID) -> Category? { catalogCategoryByID[id] }

    /// 谱例（欣赏页「照着钉」图例 + 编曲页参考谱的同一份名单）：
    /// 挑最耳熟、钉位分布清晰的几首，渲染成音钉图供照着摆钉。
    public static var scoreExamples: [Melody] {
        let pickedNames = ["玛丽有只小羊羔", "生日快乐", "茉莉花", "卡农", "铃儿响叮当"]
        return [twinkleTwinkle, odeToJoy]
            + pickedNames.compactMap { name in libraryCatalog.first { $0.name == name } }
    }

    // MARK: - 旧版预置迁移（Phase 1/2 的 16 步版本 → Phase 3 的 64 步版本）

    /// Phase 3 之前的预置定义（16 步），逐字保留以便识别「从未被用户改动过」的旧预置。
    static var legacyPresets: [Melody] { [legacyTwinkle, legacyOde, legacyBlank] }

    private static let legacyTwinkle = Melody(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        name: "小星星",
        tempoBPM: 100,
        stepCount: 16,
        events: [
            NoteEvent(pitchIndex: 0, step: 0, durationSteps: 2),
            NoteEvent(pitchIndex: 0, step: 2, durationSteps: 2),
            NoteEvent(pitchIndex: 4, step: 4, durationSteps: 2),
            NoteEvent(pitchIndex: 4, step: 6, durationSteps: 2),
            NoteEvent(pitchIndex: 5, step: 8, durationSteps: 2),
            NoteEvent(pitchIndex: 5, step: 10, durationSteps: 2),
            NoteEvent(pitchIndex: 4, step: 12, durationSteps: 4),
        ])

    private static let legacyOde = Melody(
        id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
        name: "欢乐颂（片段）",
        tempoBPM: 104,
        stepCount: 16,
        events: [
            NoteEvent(pitchIndex: 2, step: 0, durationSteps: 2),
            NoteEvent(pitchIndex: 2, step: 2, durationSteps: 2),
            NoteEvent(pitchIndex: 3, step: 4, durationSteps: 2),
            NoteEvent(pitchIndex: 4, step: 6, durationSteps: 2),
            NoteEvent(pitchIndex: 4, step: 8, durationSteps: 2),
            NoteEvent(pitchIndex: 3, step: 10, durationSteps: 2),
            NoteEvent(pitchIndex: 2, step: 12, durationSteps: 2),
            NoteEvent(pitchIndex: 1, step: 14, durationSteps: 2),
        ])

    private static let legacyBlank = Melody(
        id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
        name: "空白模板",
        tempoBPM: 100,
        stepCount: 16,
        events: [])

    /// 把旋律库中「与旧版预置逐字相同」的条目换成现行预置（同 id）。
    /// 用户改动过的预置（内容与旧定义有任何差异）与用户自建旋律一律原样保留；
    /// 迁移天然幂等：换完后条目不再等于旧定义，重复调用无副作用。
    static func refreshingLegacyPresets(_ melodies: [Melody]) -> [Melody] {
        melodies.map { entry in
            guard legacyPresets.contains(entry),
                  let current = presets.first(where: { $0.id == entry.id }) else { return entry }
            return current
        }
    }
}
