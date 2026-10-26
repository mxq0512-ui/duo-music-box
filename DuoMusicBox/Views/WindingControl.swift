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
        VStack(spacing: 5) {
            GeometryReader { geo in
                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                ZStack {
                    Circle()
                        .fill(Theme.brassGradient)
                        .frame(width: 74, height: 74)
                        .shadow(color: .black.opacity(0.45), radius: 3, y: 2)
                    Circle()
                        .stroke(Theme.brassDark.opacity(0.7), lineWidth: 1.5)
                        .frame(width: 74, height: 74)
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
            .frame(width: 92, height: 92)

            // 储能表：黄铜填充条 + 百分比
            VStack(spacing: 2) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.black.opacity(0.45))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Theme.brassGradient)
                            .frame(width: geo.size.width * CGFloat(playback.springCharge))
                    }
                }
                .frame(height: 6)
                Text("发条 \(Int((playback.springCharge * 100).rounded()))% · 拖动钥匙上链")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.creamDim)
            }
            .frame(width: 96)
        }
    }

    /// 蝶形钥匙：中轴 + 双环握柄（八音盒的标志造型）。
    private var keyBow: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(Theme.brassDark)
                .frame(width: 7, height: 34)
                .offset(y: -14)
            HStack(spacing: -5) {
                Circle().stroke(Theme.brassDark, lineWidth: 5).frame(width: 21, height: 21)
                Circle().stroke(Theme.brassDark, lineWidth: 5).frame(width: 21, height: 21)
            }
            .offset(y: -38)
            Circle()
                .fill(Theme.brassDark)
                .frame(width: 13, height: 13)
        }
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
