import SwiftUI
import UniformTypeIdentifiers

/// 数字礼物（界面六 Gift）：礼物包（旋律快照 + 标题 + 祝福）本地草稿 +
/// 系统分享文件 + 导入。
///
/// 分享走系统分享面板：把整个礼物导出为专有礼物文件（.duogift），经微信、隔空
/// 投送、信息发出；对方装有本 App 时，点开文件选「用 DUO MUSIC BOX 打开」即
/// 自动导入（或在礼物页「导入礼物」手动选入），旋律同时存入对方的旋律库。
/// 诚实边界：交接书 Phase 4 的"生成链接 → 浏览器免安装打开播放"需要线上服务
/// （链接存储、隐私、失效与滥用防护），仍未开通——这里不会生成假链接。
public struct GiftView: View {
    @ObservedObject public var store: MelodyStore
    @StateObject private var giftStore = GiftStore()
    /// 「打开方式」投递箱（App 入口从微信/文件点开礼物文件时投递到这里）。
    @ObservedObject private var inbox = GiftInbox.shared

    @State private var selectedMelodyId: UUID?
    @State private var title = ""
    @State private var message = ""
    @State private var justSaved = false
    @State private var showingImporter = false
    @State private var importNote: String?

    public init(store: MelodyStore) {
        self.store = store
    }

    private var selectedMelody: Melody? {
        if let id = selectedMelodyId, let m = store.melody(id: id) { return m }
        return store.melodies.first
    }

    private var resolvedTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "一份音乐礼物" : trimmed
    }

    /// 正在编辑的礼物（分享当前编排，无需先保存草稿）。
    private var draftGift: GiftPackage? {
        guard let melody = selectedMelody else { return nil }
        return GiftPackage(melody: melody, title: resolvedTitle, message: message)
    }

    public var body: some View {
        ZStack {
            WoodPanel(cornerRadius: 14, inner: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    explanation
                    form
                    savedDrafts
                }
                .padding(16)
            }
        }
        .onAppear {
            if selectedMelodyId == nil { selectedMelodyId = store.melodies.first?.id }
            consumePendingGift()
        }
        .onChange(of: inbox.pending?.id) { _, _ in
            consumePendingGift()
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.duoGift, .json]) { result in
            handleImport(result)
        }
    }

    /// 取走「打开方式」投递箱里的礼物并完成导入（从微信/文件点开礼物文件时）。
    private func consumePendingGift() {
        guard let gift = inbox.pending else { return }
        inbox.pending = nil
        importNote = gift.importInto(giftStore: giftStore, melodyStore: store)
        Haptics.medium()
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("把旋律装进八音盒，送给一个人")
                .font(Theme.plaqueFont(size: 15))
                .foregroundStyle(Theme.cream)
            Text("点「分享这份礼物」可经微信、隔空投送或信息把礼物文件发给对方；对方装有本 App 时，点开文件选「用 DUO MUSIC BOX 打开」即自动导入，也可在礼物页点「导入礼物」选入。免安装的网页链接仍在规划中。")
                .font(.system(size: 11))
                .foregroundStyle(Theme.creamDim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("选择旋律")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.creamDim)
            Picker("旋律", selection: $selectedMelodyId) {
                ForEach(store.melodies) { m in
                    Text(m.name).tag(Optional(m.id))
                }
            }
            .pickerStyle(.menu)
            .tint(Theme.brassBright)

            Text("礼物标题")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.creamDim)
            TextField("例如：给你的睡前小夜曲", text: $title)
                .textFieldStyle(.plain)
                .foregroundStyle(Theme.cream)
                .padding(9)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.3)))

            Text("祝福语")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.creamDim)
            TextEditor(text: $message)
                .scrollContentBackground(.hidden)
                .foregroundStyle(Theme.cream)
                .frame(height: 74)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.3)))

            MechanicalButton(systemImage: "gift.fill",
                             title: justSaved ? "已保存到草稿" : "保存礼物草稿",
                             isActive: justSaved) {
                guard let melody = selectedMelody else { return }
                let gift = GiftPackage(
                    melody: melody,
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "一份音乐礼物" : title,
                    message: message)
                giftStore.add(gift)
                justSaved = true
                Haptics.medium()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { justSaved = false }
            }

            HStack(spacing: 10) {
                if let gift = draftGift {
                    ShareLink(item: gift,
                              preview: SharePreview(gift.title, image: Image(systemName: "gift.fill"))) {
                        shareLabel(systemImage: "square.and.arrow.up", title: "分享这份礼物")
                    }
                }
                Button {
                    showingImporter = true
                } label: {
                    shareLabel(systemImage: "square.and.arrow.down", title: "导入礼物")
                }
                .buttonStyle(.plain)
            }

            // 网页礼物：单个 HTML 文件，对方免 App 在浏览器/微信里打开就能听。
            if let gift = draftGift {
                ShareLink(item: WebGiftFile(package: gift),
                          preview: SharePreview(gift.title, image: Image(systemName: "globe"))) {
                    shareLabel(systemImage: "globe", title: "分享网页礼物（免 App 打开就能听）")
                }
            }

            if let note = importNote {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.brassBright)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 与 MechanicalButton 同外观的标签（ShareLink 需要自定义标签视图）。
    private func shareLabel(systemImage: String, title: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
            Text(title)
                .font(.system(size: 10))
        }
        .foregroundStyle(Theme.cream)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.walnutInnerGradient)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.brass.opacity(0.45), lineWidth: 1)
        )
    }

    /// 导入对方分享来的礼物文件：礼物存入草稿，旋律快照存入旋律库。
    private func handleImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            let gift = try GiftPackage.decode(data: data)
            importNote = gift.importInto(giftStore: giftStore, melodyStore: store)
            Haptics.medium()
        } catch {
            importNote = "导入失败：所选文件不是有效的礼物文件。"
        }
    }

    private var savedDrafts: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("已保存的礼物草稿（\(giftStore.gifts.count)）")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.creamDim)
            if giftStore.gifts.isEmpty {
                Text("还没有草稿。选一首旋律、写一句祝福，保存第一份吧。")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.creamDim)
            } else {
                ForEach(giftStore.gifts) { gift in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "gift")
                            .foregroundStyle(Theme.brassBright)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(gift.title)
                                .font(Theme.bodyFont(size: 14))
                                .foregroundStyle(Theme.cream)
                            Text("旋律：《\(gift.melodyName)》 · \(gift.melodySnapshot.events.count) 颗音钉")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.creamDim)
                            if !gift.message.isEmpty {
                                Text(gift.message)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.creamDim)
                                    .lineLimit(2)
                            }
                        }
                        Spacer()
                        ShareLink(item: gift,
                                  preview: SharePreview(gift.title, image: Image(systemName: "gift.fill"))) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.brassBright)
                        }
                        ShareLink(item: WebGiftFile(package: gift),
                                  preview: SharePreview(gift.title, image: Image(systemName: "globe"))) {
                            Image(systemName: "globe")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.brassBright)
                        }
                        Button {
                            giftStore.delete(id: gift.id)
                            Haptics.tick()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.creamDim)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.22)))
                }
            }
        }
    }
}
