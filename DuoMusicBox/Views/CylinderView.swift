import SwiftUI

/// 黄铜滚筒 + 金属音梳，本 App 机械真实感的核心视图，全部 Canvas/代码绘制。
///
/// 坐标约定（与真实八音盒一一对应，全项目统一）：
/// - 滚筒横轴方向（x）= 音高：左 C5 → 右 C6，共 8 列（Melody.pitchCount）。
/// - 滚筒圆周方向（y）= 时间步：音钉自上而下滚动，抵达底部"拨弦线"时触发对应音梳齿。
/// - 音钉的 y 位置只由 PlaybackEngine 发布的 cylinderRotation 推导，与音频调度同源。
///
/// 编曲模式点按：把点按坐标反解为 (pitch, step)，与正向绘制公式严格互逆。
public struct CylinderView: View {
    public let melody: Melody
    public let rotationDegrees: Double
    public let currentStep: Int
    /// 当前步正在发声的音高集合（音梳振动高亮用）。
    public let triggeredPitches: Set<Int>
    public let isEditing: Bool
    public var onToggleNote: ((Int, Int) -> Void)?

    // 音梳区固定高度：基座 8 + 最长齿 30 + 音名标注 11。
    private let combHeight: CGFloat = 49
    /// 音钉在圆柱面上的可视边距（上下各留，避免贴边被裁）。
    private let pinMargin: CGFloat = 7

    public init(melody: Melody,
                rotationDegrees: Double,
                currentStep: Int,
                triggeredPitches: Set<Int>,
                isEditing: Bool,
                onToggleNote: ((Int, Int) -> Void)? = nil) {
        self.melody = melody
        self.rotationDegrees = rotationDegrees
        self.currentStep = currentStep
        self.triggeredPitches = triggeredPitches
        self.isEditing = isEditing
        self.onToggleNote = onToggleNote
    }

    /// 当前连续步进位置（步），由旋转角度反推——与 PlaybackMath.rotationDegrees 互逆。
    private var stepFloat: Double {
        guard melody.stepCount > 0 else { return 0 }
        return rotationDegrees / 360.0 * Double(melody.stepCount)
    }

    public var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let cylHeight = max(60, geo.size.height - combHeight)
            VStack(spacing: 0) {
                Canvas { ctx, size in
                    drawCylinder(ctx, size: size)
                }
                .frame(width: width, height: cylHeight)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { value in
                            handleTap(at: value.location, width: width, height: cylHeight)
                        }
                )

                comb(width: width)
                    .frame(width: width, height: combHeight)
            }
        }
    }

    // MARK: - 位置换算（正/逆共用同一组公式）

    /// 第 step 步音钉的 y：距触发还有 d 步时，y = 底边 - d 步的弧长。
    private func pinY(step: Int, height: CGFloat) -> CGFloat {
        let n = Double(melody.stepCount)
        guard n > 0 else { return height / 2 }
        let d = Self.mod(Double(step) - stepFloat, n) // 距下一次触发的步数，0 = 正在拨弦线
        let usable = height - pinMargin * 2
        return pinMargin + usable * CGFloat(1 - d / n)
    }

    private func stepAt(y: CGFloat, height: CGFloat) -> Int {
        let n = Double(melody.stepCount)
        guard n > 0 else { return 0 }
        let usable = max(1, height - pinMargin * 2)
        let frac = min(1, max(0, (Double(y) - Double(pinMargin)) / Double(usable)))
        let d = n * (1 - frac)
        var s = Int((stepFloat + d).rounded()) % melody.stepCount
        if s < 0 { s += melody.stepCount }
        return s
    }

    private func pitchAt(x: CGFloat, width: CGFloat) -> Int {
        let col = width / CGFloat(Melody.pitchCount)
        return min(Melody.pitchCount - 1, max(0, Int(Double(x / col))))
    }

    private func columnCenterX(pitch: Int, width: CGFloat) -> CGFloat {
        width / CGFloat(Melody.pitchCount) * (CGFloat(pitch) + 0.5)
    }

    private static func mod(_ a: Double, _ n: Double) -> Double {
        let r = a.truncatingRemainder(dividingBy: n)
        return r >= 0 ? r : r + n
    }

    // MARK: - 滚筒绘制

    private func drawCylinder(_ ctx: GraphicsContext, size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        // 圆柱面
        ctx.fill(Path(rect), with: .linearGradient(
            Gradient(colors: [Theme.brassDark,
                              Color(red: 0.72, green: 0.55, blue: 0.25),
                              Theme.brassBright,
                              Theme.brass,
                              Theme.brassDark]),
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: 0, y: size.height)))

        // 编曲模式网格：竖线 = 音高列界，横线 = 每步位置
        if isEditing {
            var grid = Path()
            let cols = Melody.pitchCount
            for c in 0...cols {
                let x = size.width / CGFloat(cols) * CGFloat(c)
                grid.move(to: CGPoint(x: x, y: 0))
                grid.addLine(to: CGPoint(x: x, y: size.height))
            }
            for s in 0..<melody.stepCount {
                let y = pinY(step: s, height: size.height)
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: size.width, y: y))
            }
            ctx.stroke(grid, with: .color(.black.opacity(0.14)), lineWidth: 0.6)
        }

        // 长音拖尾：真实音梳被拨后持续共鸣，用钉后（上方）一条渐淡轨迹表示 duration。
        let stepPixels = (size.height - pinMargin * 2) / CGFloat(max(1, melody.stepCount))
        for event in melody.events where event.durationSteps > 1 {
            let x = columnCenterX(pitch: event.pitchIndex, width: size.width)
            let y = pinY(step: event.step, height: size.height)
            var trail = Path()
            trail.move(to: CGPoint(x: x, y: y - 3))
            trail.addLine(to: CGPoint(x: x, y: y - 3 - stepPixels * CGFloat(event.durationSteps - 1)))
            ctx.stroke(trail, with: .color(Theme.cream.opacity(0.35)),
                       style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }

        // 音钉：黄铜小凸点（深色底 + 左上高光），越接近拨弦线越亮。
        for event in melody.events {
            let x = columnCenterX(pitch: event.pitchIndex, width: size.width)
            let y = pinY(step: event.step, height: size.height)
            let proximity = 1 - abs(y - (size.height - pinMargin)) / max(1, size.height)
            let r: CGFloat = 4.6
            let base = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
            ctx.fill(Path(ellipseIn: base), with: .color(
                Theme.brassDark.opacity(0.55 + 0.45 * proximity)))
            let hl = CGRect(x: x - r * 0.55, y: y - r * 0.62, width: r * 0.85, height: r * 0.85)
            ctx.fill(Path(ellipseIn: hl), with: .color(
                Color.white.opacity(0.35 + 0.45 * proximity)))
        }

        // 拨弦线：底部一条亮线，音钉抵达此处即发声
        var strike = Path()
        strike.move(to: CGPoint(x: 0, y: size.height - 3))
        strike.addLine(to: CGPoint(x: size.width, y: size.height - 3))
        ctx.stroke(strike, with: .color(Theme.brassBright.opacity(0.8)), lineWidth: 1.4)

        // 左右端面与转轴
        for sideX in [CGFloat(0), size.width] {
            let capRect = CGRect(x: sideX - 7, y: 2, width: 14, height: size.height - 4)
            ctx.fill(Path(ellipseIn: capRect), with: .color(Theme.brassDark.opacity(0.85)))
            let hub = CGRect(x: sideX - 3.5, y: size.height / 2 - 3.5, width: 7, height: 7)
            ctx.fill(Path(ellipseIn: hub), with: .color(Theme.ink.opacity(0.6)))
        }

        // 曲面收边阴影（上下各一道），强化圆柱体积感
        ctx.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: 10)),
                 with: .linearGradient(Gradient(colors: [.black.opacity(0.28), .clear]),
                                       startPoint: CGPoint(x: 0, y: 0),
                                       endPoint: CGPoint(x: 0, y: 10)))
        ctx.fill(Path(CGRect(x: 0, y: size.height - 10, width: size.width, height: 10)),
                 with: .linearGradient(Gradient(colors: [.clear, .black.opacity(0.30)]),
                                       startPoint: CGPoint(x: 0, y: size.height - 10),
                                       endPoint: CGPoint(x: 0, y: size.height)))
    }

    // MARK: - 音梳

    private func comb(width: CGFloat) -> some View {
        let colW = width / CGFloat(Melody.pitchCount)
        return VStack(spacing: 0) {
            // 音梳基座（梳背）
            RoundedRectangle(cornerRadius: 2)
                .fill(Theme.steelGradient)
                .frame(height: 8)
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(.black.opacity(0.3), lineWidth: 0.6))
            // 梳齿：与滚筒列严格对齐；低音齿长、高音齿短（真实音梳规律）；
            // 当前步被触发的齿下沉 1.5pt 并提亮，模拟被音钉拨动的瞬间。
            HStack(spacing: 0) {
                ForEach(0..<Melody.pitchCount, id: \.self) { i in
                    let active = triggeredPitches.contains(i)
                    let toothLen = 30 - CGFloat(i) * 1.6
                    VStack(spacing: 1) {
                        RoundedRectangle(cornerRadius: 1.6)
                            .fill(active
                                  ? AnyShapeStyle(Theme.brassGradient)
                                  : AnyShapeStyle(Theme.steelGradient))
                            .frame(width: min(16, colW * 0.42), height: toothLen)
                            .offset(y: active ? 1.5 : 0)
                            .shadow(color: active ? Theme.brass.opacity(0.7) : .clear, radius: 3)
                        Text(Pitch.at(index: i)?.noteName ?? "")
                            .font(.system(size: 8))
                            .foregroundStyle(Theme.creamDim)
                    }
                    .frame(width: colW)
                }
            }
            .animation(.easeOut(duration: 0.09), value: triggeredPitches)
        }
    }

    // MARK: - 点按编辑

    private func handleTap(at point: CGPoint, width: CGFloat, height: CGFloat) {
        guard isEditing, let onToggleNote else { return }
        let pitch = pitchAt(x: point.x, width: width)
        let step = stepAt(y: point.y, height: height)
        onToggleNote(pitch, step)
    }
}
