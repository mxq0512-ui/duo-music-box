import Foundation

/// 数字礼物的数据模型（Phase 1 只做本地数据与草稿存储）。
/// 内含完整旋律快照：Phase 4 的网页礼物只需要把一个 GiftPackage 编码成链接载荷，
/// 收礼人端无 App 也能重建旋律——所以快照必须自包含，不能只存 melodyId 引用。
public struct GiftPackage: Codable, Equatable, Identifiable {
    public var id: UUID
    /// 来源旋律在旋律库中的 id（可能已被删除，故另存快照与名称）。
    public var melodyId: UUID
    public var melodyName: String
    public var melodySnapshot: Melody
    public var title: String
    public var message: String
    public var createdAt: Date

    public init(id: UUID = UUID(),
                melody: Melody,
                title: String,
                message: String,
                createdAt: Date = Date()) {
        self.id = id
        self.melodyId = melody.id
        self.melodyName = melody.name
        self.melodySnapshot = melody
        self.title = title
        self.message = message
        self.createdAt = createdAt
    }
}

/// 礼物草稿的本地存储：Documents/duo-gifts.json。Phase 4 再在此之上加链接生成与失效机制。
public final class GiftStore: ObservableObject {
    @Published public private(set) var gifts: [GiftPackage] = []

    private let fileURL: URL

    public init(documentsDirectory: URL? = nil) {
        let dir = documentsDirectory
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = dir.appendingPathComponent("duo-gifts.json")
        loadFromDisk()
    }

    @discardableResult
    public func add(_ gift: GiftPackage) -> GiftPackage {
        gifts.insert(gift, at: 0)
        persist()
        return gift
    }

    public func delete(id: UUID) {
        let before = gifts.count
        gifts.removeAll { $0.id == id }
        if gifts.count != before { persist() }
    }

    private func loadFromDisk() {
        // 与 persist() 的 .iso8601 编码策略保持一致，否则日期字段解码失败。
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? decoder.decode([GiftPackage].self, from: data) else {
            gifts = []
            return
        }
        gifts = decoded
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(gifts) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
