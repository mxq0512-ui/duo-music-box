import Foundation
import CoreTransferable
import UniformTypeIdentifiers

/// 数字礼物的数据模型。
/// 内含完整旋律快照：礼物文件（.json）经微信/隔空投送/信息分享，对方在礼物页
/// 「导入礼物」即可打开——所以快照必须自包含，不能只存 melodyId 引用。
/// 网页礼物（收礼人无 App 也能打开）仍是后续线上阶段。
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

    // MARK: - 分享 / 导入（礼物文件）

    /// 编码为可分享的礼物文件数据。编码策略与 GiftStore 持久化一致
    /// （iso8601 日期 + sortedKeys），草稿文件与分享文件可互通。
    public func exportData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    /// 从礼物文件数据解码（导入对方分享来的礼物）。
    public static func decode(data: Data) throws -> GiftPackage {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(GiftPackage.self, from: data)
    }
}

/// 系统分享面板支持：ShareLink 直接分享 GiftPackage，导出为礼物文件（.json）。
extension GiftPackage: Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { gift in
            try gift.exportData()
        }
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
