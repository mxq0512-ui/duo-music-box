import Foundation

/// 旋律库：JSON 持久化到 Documents/duo-melodies.json。
/// 首次启动（文件不存在）时播种预置旋律；之后一切以磁盘文件为准，
/// 用户删光也不会被"复活"（除非删掉 App 重装）。
public final class MelodyStore: ObservableObject {
    @Published public private(set) var melodies: [Melody] = []

    private let fileURL: URL

    /// - Parameter documentsDirectory: 默认系统 Documents；测试时可注入临时目录。
    public init(documentsDirectory: URL? = nil) {
        let dir = documentsDirectory
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = dir.appendingPathComponent("duo-melodies.json")
        loadFromDisk()
    }

    // MARK: - 读

    public func melody(id: UUID) -> Melody? {
        melodies.first { $0.id == id }
    }

    // MARK: - 写

    /// 按 id 新增或覆盖保存，返回实际落盘的旋律。
    @discardableResult
    public func save(_ melody: Melody) -> Melody {
        if let idx = melodies.firstIndex(where: { $0.id == melody.id }) {
            melodies[idx] = melody
        } else {
            melodies.append(melody)
        }
        persist()
        return melody
    }

    public func rename(id: UUID, to newName: String) {
        guard let idx = melodies.firstIndex(where: { $0.id == id }) else { return }
        let renamed = melodies[idx].renamed(newName)
        guard renamed.name != melodies[idx].name else { return }
        melodies[idx] = renamed
        persist()
    }

    public func delete(id: UUID) {
        let before = melodies.count
        melodies.removeAll { $0.id == id }
        if melodies.count != before { persist() }
    }

    // MARK: - 磁盘

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            melodies = Melody.presets
            persist()
            markAllPresetsKnown()
            return
        }
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([Melody].self, from: data) {
            // Phase 3 迁移：未被用户改动过的旧版（16 步）预置换成 64 步现行版，
            // 用户改过的与自建的一律不动；有变更才回写（迁移逻辑见 Melody.refreshingLegacyPresets）。
            let migrated = Melody.refreshingLegacyPresets(decoded)
            // Phase 4 增量补入：100 首新目录只补"从未见过"的，用户删过的预置
            // 其 ID 已在"见过"集合里，不会被强行复活。
            let expanded = appendingNewCatalogPresets(to: migrated)
            melodies = expanded
            if expanded != decoded { persist() }
        } else {
            // 文件损坏时不崩溃：退回预置，但保留损坏文件不覆盖，方便排查。
            melodies = Melody.presets
        }
    }

    // MARK: - 目录增量补入（Phase 4）

    /// UserDefaults 键：记录"已经见过"的预置 ID 集合（墓碑表）。
    private static let knownPresetIDsKey = "duo.knownPresetIDs.v1"

    /// 本版本之前出厂的预置 ID（Phase 3 及更早，共 3 首）。UserDefaults 尚无记录
    /// （老用户升级）时以这三个为初始"见过"集合——它们正是老用户库里已有的预置。
    private static let legacyPresetIDStrings: Set<String> = [
        "11111111-1111-1111-1111-111111111111",
        "22222222-2222-2222-2222-222222222222",
        "33333333-3333-3333-3333-333333333333",
    ]

    private func markAllPresetsKnown() {
        UserDefaults.standard.set(Melody.presets.map { $0.id.uuidString },
                                  forKey: Self.knownPresetIDsKey)
    }

    /// 把从未见过的目录旋律追加到列表末尾，并把全部现行预置 ID 记入"见过"集合。
    private func appendingNewCatalogPresets(to list: [Melody]) -> [Melody] {
        let defaults = UserDefaults.standard
        let known = Set(defaults.stringArray(forKey: Self.knownPresetIDsKey)
                        ?? Array(Self.legacyPresetIDStrings))
        let present = Set(list.map { $0.id.uuidString })
        let fresh = Melody.libraryCatalog.filter {
            !known.contains($0.id.uuidString) && !present.contains($0.id.uuidString)
        }
        defaults.set(Array(known.union(Melody.presets.map { $0.id.uuidString })),
                     forKey: Self.knownPresetIDsKey)
        return list + fresh
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(melodies) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
