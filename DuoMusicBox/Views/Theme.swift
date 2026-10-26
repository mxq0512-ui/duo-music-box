import SwiftUI
import UIKit

/// 全 App 唯一的视觉语言：深胡桃木 + 抛光黄铜 + 钢制音梳 + 米白文字。
/// 所有颜色与渐变只在此定义，各视图禁止散落硬编码色值，保证机械视觉一致性。
public enum Theme {
    // 胡桃木
    public static let walnutDark = Color(red: 0.145, green: 0.082, blue: 0.045)
    public static let walnut = Color(red: 0.29, green: 0.18, blue: 0.10)
    public static let walnutLight = Color(red: 0.46, green: 0.31, blue: 0.18)
    public static let walnutInner = Color(red: 0.36, green: 0.23, blue: 0.13)
    // 黄铜
    public static let brass = Color(red: 0.83, green: 0.65, blue: 0.30)
    public static let brassBright = Color(red: 0.99, green: 0.87, blue: 0.56)
    public static let brassDark = Color(red: 0.52, green: 0.38, blue: 0.15)
    // 金属音梳
    public static let steel = Color(red: 0.78, green: 0.80, blue: 0.84)
    public static let steelDark = Color(red: 0.45, green: 0.47, blue: 0.52)
    // 文字与背景
    public static let cream = Color(red: 0.96, green: 0.91, blue: 0.80)
    public static let creamDim = Color(red: 0.80, green: 0.73, blue: 0.60)
    public static let ink = Color(red: 0.10, green: 0.06, blue: 0.03)
    public static let tableTop = Color(red: 0.07, green: 0.045, blue: 0.03)
    public static let tableBottom = Color(red: 0.16, green: 0.10, blue: 0.06)

    public static var walnutGradient: LinearGradient {
        LinearGradient(colors: [walnutLight, walnut, walnutDark],
                       startPoint: .top, endPoint: .bottom)
    }

    public static var walnutInnerGradient: LinearGradient {
        LinearGradient(colors: [walnutInner, walnutDark],
                       startPoint: .top, endPoint: .bottom)
    }

    public static var brassGradient: LinearGradient {
        LinearGradient(colors: [brassBright, brass, brassDark, brass],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// 滚筒的圆柱明暗：上暗 → 中亮（高光带）→ 下暗，模拟圆柱曲面反光。
    public static var cylinderGradient: LinearGradient {
        LinearGradient(
            colors: [brassDark,
                     Color(red: 0.72, green: 0.55, blue: 0.25),
                     brassBright,
                     brass,
                     brassDark],
            startPoint: .top, endPoint: .bottom)
    }

    public static var steelGradient: LinearGradient {
        LinearGradient(colors: [steel, steelDark, steel],
                       startPoint: .leading, endPoint: .trailing)
    }

    public static var tableGradient: LinearGradient {
        LinearGradient(colors: [tableBottom, tableTop],
                       startPoint: .top, endPoint: .bottom)
    }

    /// 铭牌与标题字体：衬线、古典。
    public static func plaqueFont(size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    public static func bodyFont(size: CGFloat) -> Font {
        .system(size: size, design: .serif)
    }
}

/// 程序绘制的木纹面板（Canvas 直线 + 正弦扰动），不使用任何图片素材。
public struct WoodPanel: View {
    public var cornerRadius: CGFloat = 14
    public var inner: Bool = false

    public init(cornerRadius: CGFloat = 14, inner: Bool = false) {
        self.cornerRadius = cornerRadius
        self.inner = inner
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(inner ? Theme.walnutInnerGradient : Theme.walnutGradient)
            Canvas { ctx, size in
                // 横向木纹：多条带正弦弯曲的细线，透明度随行变化，确定性伪随机保证每帧一致。
                let lines = 14
                for i in 0..<lines {
                    let yBase = size.height * (Double(i) + 0.5) / Double(lines)
                    var path = Path()
                    let segments = 24
                    for s in 0...segments {
                        let x = size.width * Double(s) / Double(segments)
                        let wobble = sin(Double(s) * 0.7 + Double(i) * 1.7) * 1.6
                            + sin(Double(s) * 0.23 + Double(i) * 4.1) * 2.6
                        let p = CGPoint(x: x, y: yBase + wobble)
                        if s == 0 { path.move(to: p) } else { path.addLine(to: p) }
                    }
                    let alpha = 0.05 + 0.05 * abs(sin(Double(i) * 2.3))
                    ctx.stroke(path, with: .color(.black.opacity(alpha)), lineWidth: 1.1)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Theme.brassDark.opacity(0.55), lineWidth: 1)
        }
    }
}

/// 黄铜铭牌：中央刻字 + 两侧螺丝点，古典雕刻感。
public struct BrassPlaque: View {
    public var title: String
    public var subtitle: String?

    public init(title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.brassGradient)
                .shadow(color: .black.opacity(0.45), radius: 3, y: 2)
            VStack(spacing: 1) {
                // 标题两侧月桂枝角花（SF Symbols laurel），学参考图铭牌的雕刻纹饰。
                HStack(spacing: 5) {
                    Image(systemName: "laurel.leading")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.ink.opacity(0.55))
                    Text(title)
                        .font(Theme.plaqueFont(size: 17))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Image(systemName: "laurel.trailing")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.ink.opacity(0.55))
                }
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.bodyFont(size: 11))
                        .foregroundStyle(Theme.ink.opacity(0.75))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 6)
            HStack {
                screw
                Spacer()
                screw
            }
            .padding(.horizontal, 7)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var screw: some View {
        Circle()
            .fill(Theme.brassDark)
            .frame(width: 7, height: 7)
            .overlay(Circle().stroke(Theme.ink.opacity(0.35), lineWidth: 0.6))
    }
}

/// 统一的机械风按钮（黄铜描边、木底）。
public struct MechanicalButton: View {
    public var systemImage: String
    public var title: String
    public var isActive: Bool = false
    public var action: () -> Void

    public init(systemImage: String, title: String, isActive: Bool = false, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.title = title
        self.isActive = isActive
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                Text(title)
                    .font(.system(size: 10))
            }
            .foregroundStyle(isActive ? Theme.ink : Theme.cream)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isActive ? Theme.brassGradient : Theme.walnutInnerGradient)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Theme.brass.opacity(isActive ? 0.9 : 0.45), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

/// 触觉反馈集中出口，便于全局调整强度。
public enum Haptics {
    public static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    public static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    public static func rigid() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    /// 棘轮逐齿、音钉落位这类细小"咔哒"。
    public static func tick() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
