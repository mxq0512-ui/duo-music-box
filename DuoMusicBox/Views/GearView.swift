import SwiftUI

/// 黄铜齿轮：以"根圆/齿顶圆交替折线"近似渐开线齿形，代码绘制，无素材。
public struct GearShape: Shape {
    public var teeth: Int
    /// 齿高占半径的比例。
    public var toothHeight: CGFloat = 0.15

    public init(teeth: Int, toothHeight: CGFloat = 0.15) {
        self.teeth = max(5, teeth)
        self.toothHeight = toothHeight
    }

    public func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let root = outer * (1 - toothHeight)
        let stepsPerTooth = 4 // 根-升-顶-降，梯形齿
        let total = teeth * stepsPerTooth
        var path = Path()
        for i in 0...total {
            let idx = i % total
            let phase = idx % stepsPerTooth
            let r = (phase == 1 || phase == 2) ? outer : root
            let a = Double(idx) / Double(total) * 2 * Double.pi - Double.pi / 2
            let p = CGPoint(x: center.x + r * CGFloat(cos(a)),
                            y: center.y + r * CGFloat(sin(a)))
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }
}

/// 一对啮合齿轮 + 可选的调速飞轮（右侧小风扇状调速器，八音盒标志性部件）。
/// rotationDegrees 直接取自 PlaybackEngine.cylinderRotation，齿轮转速与滚筒严格成比例：
/// 大齿轮与滚筒同轴同速；小齿轮按齿数比反向加速；调速器再放大。
public struct GearView: View {
    public var rotationDegrees: Double
    /// 大齿轮齿数（与小齿轮之比决定相对转速）。
    public var bigTeeth: Int = 12
    public var smallTeeth: Int = 8

    public init(rotationDegrees: Double) {
        self.rotationDegrees = rotationDegrees
    }

    public var body: some View {
        HStack(alignment: .center, spacing: -6) {
            gear(teeth: bigTeeth, size: 62, angle: rotationDegrees)
            gear(teeth: smallTeeth, size: 44,
                 angle: -rotationDegrees * Double(bigTeeth) / Double(smallTeeth) + 12)
            governor(angle: rotationDegrees * 6)
        }
    }

    private func gear(teeth: Int, size: CGFloat, angle: Double) -> some View {
        ZStack {
            GearShape(teeth: teeth)
                .fill(Theme.brassGradient)
                .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
            Circle()
                .fill(Theme.walnutDark)
                .frame(width: size * 0.30, height: size * 0.30)
            Circle()
                .fill(Theme.brassBright)
                .frame(width: size * 0.11, height: size * 0.11)
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(angle))
    }

    /// 调速器（governor）：两片小翼片绕轴高速旋转，速度被滚筒带动时转得飞快——
    /// 真实八音盒靠它利用空气阻力稳定转速。
    private func governor(angle: Double) -> some View {
        ZStack {
            ForEach(0..<2, id: \.self) { i in
                Capsule()
                    .fill(Theme.steelGradient)
                    .frame(width: 7, height: 30)
                    .offset(y: -11)
                    .rotationEffect(.degrees(Double(i) * 90))
            }
            Circle()
                .fill(Theme.brassDark)
                .frame(width: 9, height: 9)
        }
        .frame(width: 36, height: 36)
        .rotationEffect(.degrees(angle))
        .opacity(0.95)
    }
}
