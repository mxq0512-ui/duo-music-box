import SwiftUI

/// 主界面（交接书的机械结构宪法在此落地）：
/// 屏幕上半区永远是木质盒盖区，下半区永远是机械主体区（滚筒/音梳在上、齿轮与发条在下），
/// 四种模式只替换下半区的内容构成，滚筒与音梳的位置在任何模式下都不互换、不消失于欣赏/编曲之外。
///
/// 状态流：
/// - 关闭态：整屏是一台合上的古董八音盒，点盖开盒（弹簧阻尼动画 + 开盒声）。
/// - 打开态：盒盖收为顶部横幅（内侧铭牌显示当前旋律），下方依次是滚筒音梳、齿轮/发条、走带控制。
public struct MusicBoxView: View {
    @StateObject private var playback = PlaybackEngine()
    @StateObject private var store = MelodyStore()

    @State private var isOpen = false
    @State private var mode: Mode = .listen
    @State private var currentMelody: Melody = Melody.twinkleTwinkle
    @State private var draft: Melody = Melody.makeBlank(name: "我的旋律")

    public init() {}

    public enum Mode: String, CaseIterable {
        case listen, compose, library, gift

        public var title: String {
            switch self {
            case .listen: return "欣赏"
            case .compose: return "编曲"
            case .library: return "旋律"
            case .gift: return "礼物"
            }
        }

        public var icon: String {
            switch self {
            case .listen: return "music.note"
            case .compose: return "pencil"
            case .library: return "music.note.list"
            case .gift: return "gift"
            }
        }
    }

    private var triggeredPitches: Set<Int> {
        guard playback.isPlaying else { return [] }
        return Set(playback.melody.events(atStep: playback.currentStep).map(\.pitchIndex))
    }

    public var body: some View {
        ZStack {
            Theme.tableGradient.ignoresSafeArea()
            VStack(spacing: 10) {
                lidHeader
                if isOpen {
                    content
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    modeBar
                } else {
                    closedFront
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .onAppear {
            playback.setMelody(currentMelody)
            playback.audio.startIfNeeded()
        }
    }

    // MARK: - 盒盖区（上半区，永不移位）

    private var lidHeader: some View {
        ZStack {
            WoodPanel(cornerRadius: 14)
            VStack(spacing: 6) {
                BrassPlaque(title: isOpen ? currentMelody.name : "DUO MUSIC BOX",
                            subtitle: isOpen ? "♪ \(Int(playback.tempoBPM)) BPM · 第 \(playback.currentStep + 1) / \(playback.melody.stepCount) 步" : "复古机械八音盒")
                if isOpen {
                    Button {
                        closeBox()
                    } label: {
                        Label("合上盒盖", systemImage: "chevron.up")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.creamDim)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        }
        .frame(height: isOpen ? 96 : 150)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isOpen { openBox() }
        }
        .animation(.spring(response: 0.85, dampingFraction: 0.82), value: isOpen)
    }

    /// 关闭态的盒身正面：大铭牌 + 开启提示，占据下半区（盒盖合上时机械不可见，符合实物）。
    private var closedFront: some View {
        ZStack {
            WoodPanel(cornerRadius: 16)
            VStack(spacing: 14) {
                Image(systemName: "music.note")
                    .font(.system(size: 30))
                    .foregroundStyle(Theme.brass)
                Text("一台可以亲手上发条、装音钉的八音盒")
                    .font(Theme.bodyFont(size: 14))
                    .foregroundStyle(Theme.cream)
                Text("轻点上方盒盖开盒")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.creamDim)
                GearView(rotationDegrees: 18)
                    .opacity(0.85)
            }
            .padding(24)
        }
    }

    // MARK: - 机械主体区（下半区）

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .listen:
            listenContent
        case .compose:
            ComposeView(playback: playback, store: store, draft: $draft)
        case .library:
            LibraryView(store: store, currentMelody: $currentMelody) { loaded in
                currentMelody = loaded
                playback.setMelody(loaded)
                mode = .listen
            }
        case .gift:
            GiftView(store: store)
        }
    }

    private var listenContent: some View {
        VStack(spacing: 10) {
            // 滚筒 + 音梳：位置固定，永不与下方的齿轮/发条互换。
            ZStack {
                WoodPanel(cornerRadius: 14, inner: true)
                CylinderView(melody: currentMelody,
                             rotationDegrees: playback.cylinderRotation,
                             currentStep: playback.currentStep,
                             triggeredPitches: triggeredPitches,
                             isEditing: false)
                    .padding(10)
            }
            .frame(height: 236)

            // 齿轮组（左）与发条钥匙（右）
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 2) {
                    GearView(rotationDegrees: playback.cylinderRotation)
                    Text("传动齿轮 · 调速器")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.creamDim)
                }
                .frame(maxWidth: .infinity)
                WindingControl(playback: playback, audio: playback.audio)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 4)

            transportControls
        }
    }

    private var transportControls: some View {
        HStack(spacing: 8) {
            MechanicalButton(systemImage: playback.isPlaying ? "pause.fill" : "play.fill",
                             title: playback.isPlaying ? "暂停" : "播放",
                             isActive: playback.isPlaying) {
                if playback.isPlaying {
                    playback.pause()
                } else {
                    if playback.melody.id != currentMelody.id { playback.setMelody(currentMelody) }
                    playback.play()
                }
                Haptics.light()
            }
            MechanicalButton(systemImage: "arrow.counterclockwise", title: "重播") {
                if playback.melody.id != currentMelody.id { playback.setMelody(currentMelody) }
                playback.replay()
                Haptics.light()
            }
            MechanicalButton(systemImage: "stop.fill", title: "停止") {
                playback.stop()
                Haptics.tick()
            }
            VStack(spacing: 2) {
                Text("速度 \(Int(playback.tempoBPM))")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.cream)
                Slider(value: $playback.tempoBPM, in: 60...160, step: 1)
                    .tint(Theme.brass)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.walnutInner.opacity(0.6)))
        }
    }

    private var modeBar: some View {
        HStack(spacing: 8) {
            ForEach(Mode.allCases, id: \.self) { m in
                MechanicalButton(systemImage: m.icon, title: m.title, isActive: mode == m) {
                    mode = m
                    Haptics.tick()
                }
            }
        }
    }

    // MARK: - 开合盒

    private func openBox() {
        withAnimation(.spring(response: 0.9, dampingFraction: 0.80)) { isOpen = true }
        playback.audio.playLidSound()
        Haptics.medium()
    }

    private func closeBox() {
        playback.pause()
        withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) { isOpen = false }
        playback.audio.playLidSound()
        Haptics.medium()
    }
}
