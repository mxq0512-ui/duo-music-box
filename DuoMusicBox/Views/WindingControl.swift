import SwiftUI

/// 发条钥匙：用户绕中心拖动旋转上链。
/// 顺时针转动给 PlaybackEngine.springCharge 补充储能；每转过约 15° 触发一次
/// 单齿 ratchet 声 + 轻触觉——真实八音盒上链的"咔哒咔哒"逐齿感，声响密度
/// 跟随手的转速（声音与动作同步）。
/// 逆时针只转钥匙不储能（棘轮打滑），与真实机构一致。
public struct WindingControl: View {
    @ObservedObject public var playback: PlaybackEngine
    public let audio: MusicBoxAudioEngine
    /// 钥匙累计转角回调（度）：Phase 2 的 3D 场景用它同步呈现钥匙转动，本控件仍是唯一手势入口。
    public var onKeyAngleChange: ((Double) -> Void)?

    @State private var keyAngle: Double = 0
    @State private var lastDragAngle: Double?
    @State private var ratchetAccumulator: Double = 0

    /// 转满一圈补充的储能（约 3.3 圈上满，接近真实八音盒的手感）。
    private static let chargePerRevolution = 0.30
    /// 每积累多少度触发一次棘轮声（一齿一响；真实棘轮约 24 齿/圈）。
    private static let ratchetStepDegrees = 15.0

    public init(playback: PlaybackEngine, audio: MusicBoxAudioEngine,
                onKeyAngleChange: ((Double) -> Void)? = nil) {
        self.playback = playback
        self.audio = audio
        self.onKeyAngleChange = onKeyAngleChange
    }

    public var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                ZStack {
                    barrelArt
                    keyBow
                        .rotationEffect(.degrees(keyAngle))
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in rotate(to: value.location, center: center) }
                        .onEnded { _ in lastDragAngle = nil }
                )
            }
            .frame(width: 104, height: 104)

            // 储能表：加长黄铜填充条（96 → 216）+ 百分比，读数一眼到位。
            VStack(spacing: 3) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3.5)
                            .fill(Color.black.opacity(0.45))
                        RoundedRectangle(cornerRadius: 3.5)
                            .fill(Theme.brassGradient)
                            .frame(width: geo.size.width * CGFloat(playback.springCharge))
                        RoundedRectangle(cornerRadius: 3.5)
                            .fill(Color.white.opacity(0.22))
                            .frame(height: 2)
                            .padding(.horizontal, 2)
                            .frame(maxHeight: .infinity, alignment: .top)
                            .padding(.top, 1)
                    }
                }
                .frame(height: 7)
                Text("发条 \(Int((playback.springCharge * 100).rounded()))% · 拖动钥匙上链")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.creamDim)
            }
            .frame(width: 216)
        }
    }

    /// 发条筒（静态底座）：外圈棘轮齿 + 拉丝筒面 + 螺旋发条纹 + 中心轴座。
    /// 旧版只是一块平面渐变圆，被用户评为"不够逼真"；这一版按真实发条盒的
    /// 俯视结构逐层画：齿（上链棘爪滑过的那圈）、面（径向高光）、卷（螺旋槽
    /// 双描成浮雕）、轴（中心方孔座）。
    private var barrelArt: some View {
        ZStack {
            // 棘轮齿环：28 颗齿从筒缘探出。
            ForEach(0..<28, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Theme.brassDark)
                    .frame(width: 5, height: 11)
                    .offset(y: -45)
                    .rotationEffect(.degrees(Double(i) * 360 / 28))
            }
            // 筒面：径向渐变（左上亮、右下沉）模拟棚光下的金属圆面。
            Circle()
                .fill(RadialGradient(
                    colors: [Theme.brassBright, Theme.brass, Theme.brassDark],
                    center: UnitPoint(x: 0.35, y: 0.3),
                    startRadius: 4, endRadius: 62))
                .frame(width: 88, height: 88)
                .shadow(color: .black.opacity(0.5), radius: 4, y: 3)
            Circle()
                .stroke(Theme.brassDark.opacity(0.8), lineWidth: 1.5)
                .frame(width: 88, height: 88)
            // 筒盖内圈凹线。
            Circle()
                .stroke(Color.black.opacity(0.25), lineWidth: 5)
                .frame(width: 72, height: 72)
            // 螺旋发条：暗槽 + 错位亮边 = 刻进金属的浮雕感。
            ZStack {
                SpiralShape(turns: 4.5)
                    .stroke(Color.white.opacity(0.30), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                    .offset(x: 0.8, y: 0.8)
                SpiralShape(turns: 4.5)
                    .stroke(Theme.brassDark, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
            .frame(width: 66, height: 66)
            // 中心轴座（钥匙hub 压在其上）。
            Circle()
                .fill(RadialGradient(
                    colors: [Theme.brassBright, Theme.brassDark],
                    center: UnitPoint(x: 0.4, y: 0.35),
                    startRadius: 1, endRadius: 10))
                .frame(width: 17, height: 17)
        }
    }

    /// 蝶形钥匙：中轴 + 双环握柄（八音盒的标志造型），金属渐变 + 落影，
    /// 不再是旧版的平面深色剪影。
    private var keyBow: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(LinearGradient(colors: [Theme.brassBright, Theme.brass, Theme.brassDark],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: 8, height: 36)
                .offset(y: -13)
            HStack(spacing: -5) {
                keyRing
                keyRing
            }
            .offset(y: -36)
            Circle()
                .fill(RadialGradient(
                    colors: [Theme.brassBright, Theme.brass, Theme.brassDark],
                    center: UnitPoint(x: 0.38, y: 0.32),
                    startRadius: 1, endRadius: 9))
                .frame(width: 15, height: 15)
            // 轴心方孔（上链钥匙的身份标记）。
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.black.opacity(0.55))
                .frame(width: 6, height: 6)
        }
        .shadow(color: .black.opacity(0.35), radius: 2, y: 2)
    }

    private var keyRing: some View {
        Circle()
            .stroke(LinearGradient(colors: [Theme.brassBright, Theme.brassDark],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 6)
            .frame(width: 22, height: 22)
    }

    private func rotate(to point: CGPoint, center: CGPoint) {
        let ang = atan2(point.y - center.y, point.x - center.x) * 180 / .pi
        defer { lastDragAngle = ang }
        guard let last = lastDragAngle else { return }
        var delta = ang - last
        while delta > 180 { delta -= 360 }
        while delta < -180 { delta += 360 }
        keyAngle += delta
        onKeyAngleChange?(keyAngle)
        if delta > 0 {
            playback.addCharge(delta / 360.0 * Self.chargePerRevolution)
            ratchetAccumulator += delta
            // 快速甩动时一次手势事件可能跨过多个齿：逐齿补发（每事件上限 6 响，
            // 避免声音堆叠成噪声），保证听到的齿数与转过的角度一致。
            var clicks = 0
            while ratchetAccumulator >= Self.ratchetStepDegrees && clicks < 6 {
                ratchetAccumulator -= Self.ratchetStepDegrees
                audio.playRatchet()
                clicks += 1
            }
            if clicks > 0 { Haptics.tick() }
            if ratchetAccumulator >= Self.ratchetStepDegrees {
                ratchetAccumulator = 0
            }
        }
    }
}

/// 阿基米德螺旋（发条卷的俯视纹）：从内向外等距盘绕 turns 圈。
private struct SpiralShape: Shape {
    var turns: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let maxR = min(rect.width, rect.height) / 2 - 1
        let minR = maxR * 0.14
        let steps = 240
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let angle = t * turns * 2 * Double.pi
            let r = minR + (maxR - minR) * t
            let p = CGPoint(x: center.x + CGFloat(cos(angle) * r),
                            y: center.y + CGFloat(sin(angle) * r))
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        return path
    }
}
