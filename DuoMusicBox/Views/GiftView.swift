import SwiftUI

/// 数字礼物（界面六 Gift）——Phase 1 范围：真实数据模型 + 本地草稿。
///
/// 诚实边界：交接书 Phase 4 才交付"生成链接 → 浏览器免安装打开播放"的线上服务
/// （涉及链接存储、隐私、失效与滥用防护，需单独设计）。Phase 1 只把礼物包
/// （旋律快照 + 标题 + 祝福）完整建模并存到本地，界面不生成任何假链接、
/// 不假装已发送。数据结构已自包含，Phase 4 可直接在其上加编码与分享。
public struct GiftView: View {
    @ObservedObject public var store: MelodyStore
    @StateObject private var giftStore = GiftStore()

    @State private var selectedMelodyId: UUID?
    @State private var title = ""
    @State private var message = ""
    @State private var justSaved = false

    public init(store: MelodyStore) {
        self.store = store
    }

    private var selectedMelody: Melody? {
        if let id = selectedMelodyId, let m = store.melody(id: id) { return m }
        return store.melodies.first
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
        }
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("把旋律装进八音盒，送给一个人")
                .font(Theme.plaqueFont(size: 15))
                .foregroundStyle(Theme.cream)
            Text("当前为本地礼物草稿：旋律与祝福会完整保存。生成分享链接、对方免安装在浏览器开盒播放，是后续阶段（Phase 4）的线上功能，尚未开通——这里不会生成假链接。")
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
