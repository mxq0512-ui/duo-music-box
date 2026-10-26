import Foundation
import Combine
import CoreTransferable
import UniformTypeIdentifiers

/// 数字礼物的数据模型。
/// 内含完整旋律快照：礼物文件（专有类型 .duogift，内容仍是 JSON）经微信/隔空
/// 投送/信息分享；对方点开文件选「用 DUO MUSIC BOX 打开」即自动导入，也可在
/// 礼物页「导入礼物」手动选入——所以快照必须自包含，不能只存 melodyId 引用。
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

    /// 分享时的文件名：带旋律名方便在聊天与文件列表里辨认；扩展名 .duogift 是
    /// 本 App 的专有礼物类型（Info.plist 有对应声明），系统据此把文件与本 App 关联。
    public var shareFileName: String {
        let blocked = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let safeName = melodyName.components(separatedBy: blocked).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return safeName.isEmpty ? "八音盒礼物.duogift" : "八音盒礼物-\(safeName).duogift"
    }

    /// 并入本地：礼物进 GiftStore，旋律快照进 MelodyStore（同 id 同内容复用、
    /// 同 id 异内容存副本、新 id 原样存入），返回给用户看的结果说明。
    public func importInto(giftStore: GiftStore, melodyStore: MelodyStore) -> String {
        giftStore.add(self)
        let snapshot = melodySnapshot
        if let existing = melodyStore.melody(id: snapshot.id) {
            if existing != snapshot {
                var copy = snapshot
                copy.id = UUID()
                melodyStore.save(copy)
            }
        } else {
            melodyStore.save(snapshot)
        }
        return "已导入礼物《\(title)》——旋律《\(melodyName)》已存入旋律库，去欣赏页即可聆听。"
    }
}

extension UTType {
    /// 本 App 的礼物文件类型，内容仍是 JSON；Info.plist 里有对应的导出类型声明
    /// 与文档类型声明，系统据此在分享面板与「打开方式」里识别礼物文件。
    public static var duoGift: UTType {
        UTType(exportedAs: "com.jacky.duomusicbox.gift", conformingTo: .json)
    }
}

/// 系统分享面板支持：ShareLink 直接分享 GiftPackage。
/// 走文件型表示（FileRepresentation）：分享出去的是一个有正式文件名的真实文件，
/// 而不是无名的内存数据——分享面板的标题正常显示文件名，微信等以文件为单位的
/// 入口也更容易出现；对方收到文件后可直接选「用本 App 打开」。
extension GiftPackage: Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .duoGift) { gift in
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(gift.shareFileName)
            try gift.exportData().write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

/// 「打开方式」投递箱：用户从微信/文件点开礼物文件时，App 入口先把解码好的
/// 礼物暂存于此并切到礼物页，由持有 GiftStore 的 GiftView 取走完成导入。
public final class GiftInbox: ObservableObject {
    public static let shared = GiftInbox()
    @Published public var pending: GiftPackage?
    public init() {}
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
