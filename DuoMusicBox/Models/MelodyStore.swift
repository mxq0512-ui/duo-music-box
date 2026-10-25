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
            return
        }
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([Melody].self, from: data) {
            melodies = decoded
        } else {
            // 文件损坏时不崩溃：退回预置，但保留损坏文件不覆盖，方便排查。
            melodies = Melody.presets
        }
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(melodies) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
