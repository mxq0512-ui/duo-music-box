import SwiftUI

/// 编曲模式（交接书模式 B：Free Compose 为 Phase 1 落地范围；
/// 模式 A 教程的乐谱指引区在此预留为同一块音高网格，教程步进逻辑在 Phase 3 扩展）。
///
/// 布局与全 App 统一：上半区 = 指引（音高网格 + 当前节拍 + 选中格信息），
/// 下半区 = 可编辑滚筒（Phase 2 起为 MechanismSceneView 3D 场景，编辑语义不变）。装钉/拆钉即时发声验证，
/// 编辑结果实时 sync 回 PlaybackEngine，试听与创作共用同一份草稿数据。
public struct ComposeView: View {
    @ObservedObject public var playback: PlaybackEngine
    @ObservedObject public var store: MelodyStore
    @Binding public var draft: Melody

    @State private var selectedPitch: Int?
    @State private var selectedStep: Int?
    @State private var showSaveAlert = false
    @State private var saveName = ""

    public init(playback: PlaybackEngine, store: MelodyStore, draft: Binding<Melody>) {
        self.playback = playback
        self.store = store
        self._draft = draft
    }

    private var triggered: Set<Int> {
        guard playback.isPlaying, playback.melody.id == draft.id else { return [] }
        return Set(playback.melody.events(atStep: playback.currentStep).map(\.pitchIndex))
    }

    public var body: some View {
        VStack(spacing: 10) {
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
            .frame(height: 218)
            controls
        }
    }

    // MARK: - 上半区指引

    private var guidancePanel: some View {
        ZStack {
            WoodPanel(cornerRadius: 12, inner: true)
            HStack(spacing: 8) {
                // 左列音高名（自上而下 C6 → C5，与网格行对应）
                VStack(spacing: 0) {
                    ForEach((0..<Melody.pitchCount).reversed(), id: \.self) { i in
                        Text(Pitch.at(index: i)?.noteName ?? "")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(selectedPitch == i ? Theme.brassBright : Theme.creamDim)
                            .frame(height: 13)
                    }
                }
                pitchGrid
            }
            .padding(8)
        }
        .frame(height: 122)
    }

    /// 简化音符指引网格：行 = 音高（上高下低），列 = 时间步；亮点 = 音钉；
    /// 播放时当前列高亮；点选格在网格上以黄铜圈标出。
    private var pitchGrid: some View {
        Canvas { ctx, size in
            let rows = Melody.pitchCount
            let cols = draft.stepCount
            let cellW = size.width / CGFloat(cols)
            let cellH = size.height / CGFloat(rows)
            // 五线谱式横线（每行一条）
            var lines = Path()
            for r in 0...rows {
                let y = cellH * CGFloat(r)
                lines.move(to: CGPoint(x: 0, y: y))
                lines.addLine(to: CGPoint(x: size.width, y: y))
            }
            ctx.stroke(lines, with: .color(Theme.cream.opacity(0.16)), lineWidth: 0.6)
            // 当前播放列
            if playback.isPlaying, playback.melody.id == draft.id {
                let x = cellW * CGFloat(playback.currentStep)
                ctx.fill(Path(CGRect(x: x, y: 0, width: cellW, height: size.height)),
                         with: .color(Theme.brass.opacity(0.18)))
            }
            // 音钉点
            for event in draft.events {
                let rowFromTop = CGFloat(Melody.pitchCount - 1 - event.pitchIndex)
                let cx = cellW * (CGFloat(event.step) + 0.5)
                let cy = cellH * (rowFromTop + 0.5)
                let r = min(cellW, cellH) * 0.30
                ctx.fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)),
                         with: .color(Theme.brassBright))
            }
            // 选中格
            if let sp = selectedPitch, let ss = selectedStep {
                let rowFromTop = CGFloat(Melody.pitchCount - 1 - sp)
                let rect = CGRect(x: cellW * CGFloat(ss), y: cellH * rowFromTop,
                                  width: cellW, height: cellH)
                ctx.stroke(Path(rect), with: .color(Theme.brassBright), lineWidth: 1.4)
            }
        }
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
        if let p = selectedPitch, let s = selectedStep, let pitch = Pitch.at(index: p) {
            let has = draft.hasNote(pitchIndex: p, step: s)
            return "已选 \(pitch.noteName)（\(pitch.solfege)）· 第 \(s + 1) 步 · \(has ? "有音钉，再点一次拆除" : "空，点滚筒装上音钉")"
        }
        return "点按滚筒装上或拆除音钉 · 共 \(draft.events.count) 颗 · \(draft.stepCount) 步"
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
