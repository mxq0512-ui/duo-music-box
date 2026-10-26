import SwiftUI

/// 编曲模式（交接书模式 B：Free Compose）。
///
/// 布局与全 App 统一：上半区 = 可编辑音高表格（Phase 3 起为主要编曲面：
/// 点格装/拆音钉，64 步横向滚动，试听时播放列自动跟随），
/// 下半区 = 3D 滚筒镜像（同一份草稿数据的实时呈现，可拖动滚动、可点按，
/// 与表格互为镜像）。装钉/拆钉即时发声验证，编辑结果实时 sync 回
/// PlaybackEngine，试听与创作共用同一份草稿数据。
public struct ComposeView: View {
    @ObservedObject public var playback: PlaybackEngine
    @ObservedObject public var store: MelodyStore
    @Binding public var draft: Melody
    /// 参考谱例（欣赏页谱例条设定，或在本页谱例行点选）：其音钉在表格中以
    /// 虚线圈呈现，照着装钉即可复刻整首——"照着钉"的教学闭环。
    @Binding public var reference: Melody?

    @State private var selectedPitch: Int?
    @State private var selectedStep: Int?
    @State private var showSaveAlert = false
    @State private var saveName = ""

    public init(playback: PlaybackEngine, store: MelodyStore, draft: Binding<Melody>,
                reference: Binding<Melody?>) {
        self.playback = playback
        self.store = store
        self._draft = draft
        self._reference = reference
    }

    private var triggered: Set<Int> {
        guard playback.isPlaying, playback.melody.id == draft.id else { return [] }
        return Set(playback.melody.events(atStep: playback.currentStep).map(\.pitchIndex))
    }

    public var body: some View {
        VStack(spacing: 10) {
            referenceChips
            guidancePanel
            // 可编辑滚筒：Phase 2 起与欣赏模式共用同一块 3D 场景，
            // 点按增删的回调、草稿数据与发声反馈与 Phase 1 完全一致（仍走 toggle）。
            MechanismSceneView(melody: draft,
                               playback: playback,
                               rotationDegrees: playback.melody.id == draft.id ? playback.cylinderRotation : 0,
                               triggeredPitches: triggered,
                               springCharge: playback.springCharge,
                               windingKeyAngle: 0,
                               isEditing: true) { pitch, step in
                toggle(pitch: pitch, step: step)
            }
            .frame(height: 184)
            controls
        }
    }

    // MARK: - 上半区：可编辑音高表格（Phase 3 主要编曲面）

    private static let cellW: CGFloat = 30
    private static let cellH: CGFloat = 17

    /// 已装钉格子的键集合（pitch × 10000 + step），供单元格 O(1) 查询。
    private var noteKeySet: Set<Int> {
        Set(draft.events.map { $0.pitchIndex * 10000 + $0.step })
    }

    /// 参考谱例的钉位键集合（虚线圈渲染用）。
    private var referenceKeySet: Set<Int> {
        guard let reference else { return [] }
        return Set(reference.events.map { $0.pitchIndex * 10000 + $0.step })
    }

    /// 参考谱例中尚未照着装上的音钉数。
    private var referenceRemaining: Int {
        guard let reference else { return 0 }
        return reference.events.filter { !draft.hasNote(pitchIndex: $0.pitchIndex, step: $0.step) }.count
    }

    /// 谱例选择行：无 / 七首谱例（与欣赏页同一份名单）。选中后表格出现虚线圈钉位。
    private var referenceChips: some View {
        HStack(spacing: 6) {
            Text("参考谱例")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.creamDim)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip(title: "无", isActive: reference == nil) { reference = nil }
                    ForEach(Melody.scoreExamples) { example in
                        chip(title: example.name, isActive: reference?.id == example.id) {
                            reference = example
                        }
                    }
                }
            }
        }
    }

    private func chip(title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: isActive ? .bold : .regular))
                .foregroundStyle(isActive ? Theme.ink : Theme.cream)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(isActive ? Theme.brass : Color.black.opacity(0.3)))
                .overlay(Capsule().stroke(Theme.brass.opacity(isActive ? 0.9 : 0.4), lineWidth: 0.7))
        }
        .buttonStyle(.plain)
    }

    private var guidancePanel: some View {
        ZStack {
            WoodPanel(cornerRadius: 12, inner: true)
            HStack(spacing: 8) {
                // 左列音高名（自上而下 C6 → C5，与网格行对应；首行为表头占位）
                VStack(spacing: 0) {
                    Text("步")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Theme.creamDim)
                        .frame(height: 14)
                    ForEach((0..<Melody.pitchCount).reversed(), id: \.self) { i in
                        Text(Pitch.at(index: i)?.noteName ?? "")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(selectedPitch == i ? Theme.brassBright : Theme.creamDim)
                            .frame(height: Self.cellH)
                    }
                }
                .frame(width: 22)
                editorGrid
            }
            .padding(8)
        }
        .frame(height: 170)
    }

    /// 横向滚动的步进表格：列 = 时间步（64 步全长），行 = 音高；
    /// 点格即装/拆音钉（与滚筒点按共用同一个 toggle）；试听时当前列高亮并自动滚入视野。
    private var editorGrid: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(0..<draft.stepCount, id: \.self) { step in
                        gridColumn(step: step)
                            .id(step)
                    }
                }
            }
            .onChange(of: playback.currentStep) { _, newStep in
                if playback.isPlaying, playback.melody.id == draft.id {
                    withAnimation(.linear(duration: 0.12)) {
                        proxy.scrollTo(newStep, anchor: .center)
                    }
                }
            }
        }
    }

    private func gridColumn(step: Int) -> some View {
        let isCurrent = playback.isPlaying && playback.melody.id == draft.id
            && playback.currentStep == step
        return VStack(spacing: 0) {
            // 表头：每小节（8 步 = 4/4 一小节）标出起始步号
            Text(step % 8 == 0 ? "\(step + 1)" : "")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(isCurrent ? Theme.brassBright : Theme.creamDim)
                .frame(width: Self.cellW, height: 14)
            ForEach((0..<Melody.pitchCount).reversed(), id: \.self) { pitch in
                gridCell(pitch: pitch, step: step)
            }
        }
        .background(isCurrent ? Theme.brass.opacity(0.13) : Color.clear)
        .overlay(alignment: .leading) {
            if step % 8 == 0, step > 0 {
                Rectangle()
                    .fill(Theme.cream.opacity(0.22))
                    .frame(width: 1)
            }
        }
    }

    private func gridCell(pitch: Int, step: Int) -> some View {
        let key = pitch * 10000 + step
        let has = noteKeySet.contains(key)
        let isGhost = !has && referenceKeySet.contains(key)
        let isSelected = selectedPitch == pitch && selectedStep == step
        return ZStack {
            Rectangle()
                .fill(has ? Theme.brass : Theme.cream.opacity(0.05))
            if has {
                Circle()
                    .fill(Theme.brassBright)
                    .frame(width: 7, height: 7)
            }
            if isGhost {
                // 参考谱例钉位：空心圈，照着把钉装进圈里即对位。
                Circle()
                    .strokeBorder(Theme.brassBright.opacity(0.8), lineWidth: 1.1)
                    .frame(width: 9, height: 9)
            }
            Rectangle()
                .strokeBorder(isSelected ? Theme.brassBright : Theme.cream.opacity(0.10),
                              lineWidth: isSelected ? 1.4 : 0.5)
        }
        .frame(width: Self.cellW, height: Self.cellH)
        .contentShape(Rectangle())
        .onTapGesture { toggle(pitch: pitch, step: step) }
    }

    // MARK: - 控制区

    private var controls: some View {
        VStack(spacing: 8) {
            // 选中格信息 / 操作提示
            Text(selectionText)
                .font(Theme.bodyFont(size: 12))
                .foregroundStyle(Theme.cream)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 14) {
                Text("速度")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.creamDim)
                Slider(value: Binding(
                    get: { draft.tempoBPM },
                    set: { newValue in
                        draft = draft.withTempo(newValue)
                        syncDraftToPlayer()
                        if playback.melody.id == draft.id { playback.tempoBPM = newValue }
                    }), in: 60...160, step: 1)
                .tint(Theme.brass)
                Text("\(Int(draft.tempoBPM)) BPM")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.cream)
                    .frame(width: 56, alignment: .trailing)
            }

            HStack(spacing: 8) {
                MechanicalButton(systemImage: playback.isPlaying ? "pause.fill" : "play.fill",
                                 title: "试听", isActive: playback.isPlaying) {
                    if playback.isPlaying {
                        playback.pause()
                    } else {
                        playback.setMelody(draft)
                        playback.play()
                    }
                    Haptics.light()
                }
                MechanicalButton(systemImage: "trash", title: "清空") {
                    draft = Melody(id: draft.id, name: draft.name,
                                   tempoBPM: draft.tempoBPM,
                                   stepCount: draft.stepCount, events: [])
                    syncDraftToPlayer()
                    selectedPitch = nil
                    selectedStep = nil
                    Haptics.medium()
                }
                MechanicalButton(systemImage: "square.and.arrow.down", title: "保存") {
                    saveName = draft.name
                    showSaveAlert = true
                }
            }
        }
        .alert("保存旋律", isPresented: $showSaveAlert) {
            TextField("旋律名称", text: $saveName)
            Button("保存") {
                let saved = store.save(draft.renamed(saveName))
                draft = saved
                syncDraftToPlayer()
                Haptics.medium()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("保存到「我的旋律」，下次打开还在。")
        }
    }

    private var selectionText: String {
        var parts: [String] = []
        if let reference {
            parts.append(referenceRemaining == 0
                ? "参考《\(reference.name)》：全部钉对了 ✓"
                : "参考《\(reference.name)》：照着空心圈装钉，还差 \(referenceRemaining) 颗")
        }
        if let p = selectedPitch, let s = selectedStep, let pitch = Pitch.at(index: p) {
            let has = draft.hasNote(pitchIndex: p, step: s)
            parts.append("已选 \(pitch.noteName)（\(pitch.solfege)）· 第 \(s + 1) 步 · \(has ? "有音钉，再点一次拆除" : "空，再点一次装上")")
        } else if reference == nil {
            parts.append("点上方表格装上或拆除音钉（滚筒可拖动滚动，也可点按）· 共 \(draft.events.count) 颗 · \(draft.stepCount) 步")
        }
        return parts.joined(separator: " · ")
    }

    /// 只有播放器当前装载的正是这份草稿时，才把编辑实时同步过去；
    /// 正在欣赏别的旋律时不打扰，等用户按「试听」再切换。
    private func syncDraftToPlayer() {
        if playback.melody.id == draft.id { playback.syncMelody(draft) }
    }

    // MARK: - 编辑动作

    private func toggle(pitch: Int, step: Int) {
        let existed = draft.hasNote(pitchIndex: pitch, step: step)
        draft = draft.togglingNote(pitchIndex: pitch, step: step)
        selectedPitch = pitch
        selectedStep = step
        syncDraftToPlayer()
        if existed {
            playback.audio.playClick()
            Haptics.tick()
        } else {
            // 装钉后立刻发该音高一声，让用户当场确认音高对不对。
            playback.audio.play(pitchIndex: pitch, velocity: 0.85)
            Haptics.light()
        }
    }
}
