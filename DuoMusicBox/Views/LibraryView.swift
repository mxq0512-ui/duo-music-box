import SwiftUI

/// 旋律库（界面五 My Melodies）：预置 + 用户旋律统一列表。
/// 点按装载到八音盒并切去欣赏；左滑可重命名/删除（预置亦可，删后不自动恢复）。
public struct LibraryView: View {
    @ObservedObject public var store: MelodyStore
    @Binding public var currentMelody: Melody
    public var onLoad: (Melody) -> Void

    @State private var renameID: UUID?
    @State private var renameText = ""
    @State private var deleteID: UUID?
    /// 单一 alert 出口：同一视图挂两个 .alert 在部分 iOS 版本上只会呈现一个，故合并。
    @State private var activeAlert: LibraryAlert?

    private enum LibraryAlert { case rename, delete }

    public init(store: MelodyStore, currentMelody: Binding<Melody>, onLoad: @escaping (Melody) -> Void) {
        self.store = store
        self._currentMelody = currentMelody
        self.onLoad = onLoad
    }

    public var body: some View {
        ZStack {
            WoodPanel(cornerRadius: 14, inner: true)
            if store.melodies.isEmpty {
                Text("旋律库是空的，去「编曲」装上第一颗音钉再保存吧。")
                    .font(Theme.bodyFont(size: 13))
                    .foregroundStyle(Theme.creamDim)
                    .multilineTextAlignment(.center)
                    .padding(24)
            } else {
                List {
                    ForEach(store.melodies) { melody in
                        Button {
                            onLoad(melody)
                            Haptics.light()
                        } label: {
                            row(for: melody)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(Theme.brass.opacity(0.25))
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                deleteID = melody.id
                                activeAlert = .delete
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            Button {
                                renameID = melody.id
                                renameText = melody.name
                                activeAlert = .rename
                            } label: {
                                Label("重命名", systemImage: "pencil")
                            }
                            .tint(Theme.brassDark)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .padding(.vertical, 6)
            }
        }
        .alert(alertTitle, isPresented: Binding(
            get: { activeAlert != nil },
            set: { if !$0 { activeAlert = nil } }
        )) {
            if activeAlert == .rename {
                TextField("名称", text: $renameText)
                Button("确定") {
                    if let id = renameID { store.rename(id: id, to: renameText) }
                    // 若改的正是当前装载的旋律，界面上的名字同步刷新。
                    if let id = renameID, id == currentMelody.id,
                       let updated = store.melody(id: id) {
                        currentMelody = updated
                    }
                }
                Button("取消", role: .cancel) {}
            } else {
                Button("删除", role: .destructive) {
                    if let id = deleteID { store.delete(id: id) }
                }
                Button("取消", role: .cancel) {}
            }
        } message: {
            if activeAlert == .delete {
                Text("删除后无法恢复。")
            }
        }
    }

    private var alertTitle: String {
        activeAlert == .rename ? "重命名旋律" : "删除这首旋律？"
    }

    private func row(for melody: Melody) -> some View {
        HStack(spacing: 10) {
            Image(systemName: melody.id == currentMelody.id ? "speaker.wave.2.fill" : "music.note")
                .foregroundStyle(melody.id == currentMelody.id ? Theme.brassBright : Theme.creamDim)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(melody.name)
                    .font(Theme.bodyFont(size: 15))
                    .foregroundStyle(Theme.cream)
                Text("\(melody.events.count) 颗音钉 · \(melody.stepCount) 步 · \(Int(melody.tempoBPM)) BPM")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.creamDim)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.creamDim)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
