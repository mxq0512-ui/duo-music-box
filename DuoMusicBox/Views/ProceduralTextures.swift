import UIKit

/// 程序生成的贴图（零外部素材）：胡桃木纹与环境反射图。
/// 全部用 CoreGraphics 现场绘制，算法与 Theme.WoodPanel 的木纹（正弦扰动横纹 +
/// 确定性伪随机）同源，保证 2D 界面与 3D 场景的木质视觉是同一块"木头"。
/// 只生成一次（静态常量），场景内多节点共享同一张图。
public enum ProceduralTextures {
    /// 胡桃木纹（512×512），用作 3D 盒体/背板的漫反射贴图。
    public static let walnut: UIImage = makeWalnutTexture()

    /// 环境反射图（512×256 等距柱状）：上方一道明亮的暖色"窗光"带，
    /// 下方沉入深棕——赋给 SceneKit 的 lightingEnvironment 后，
    /// 黄铜与钢的金属表面会映出这道光带，金属感主要来自于此。
    public static let environment: UIImage = makeEnvironmentImage()

    // MARK: - 胡桃木纹

    private static func makeWalnutTexture() -> UIImage {
        let size = CGSize(width: 512, height: 512)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            // 基底：Theme.walnut 一带的中深胡桃色
            cg.setFillColor(UIColor(red: 0.30, green: 0.185, blue: 0.105, alpha: 1).cgColor)
            cg.fill(CGRect(origin: .zero, size: size))

            // 宽色带：木材年轮造成的整体明暗起伏
            for i in 0..<26 {
                let t = Double(i) / 26.0
                let y = size.height * CGFloat(t)
                let dark = hash(i &* 7 &+ 3) > 0.45
                let alpha = 0.03 + 0.05 * hash(i &* 13 &+ 5)
                cg.setFillColor(dark
                    ? UIColor.black.withAlphaComponent(CGFloat(alpha)).cgColor
                    : UIColor(red: 1, green: 0.9, blue: 0.7, alpha: CGFloat(alpha)).cgColor)
                cg.fill(CGRect(x: 0, y: y, width: size.width, height: size.height / 26 + 2))
            }

            // 横向木纹细线：与 WoodPanel 同一公式（双正弦扰动），确定性保证稳定。
            let lines = 110
            for i in 0..<lines {
                let yBase = size.height * (Double(i) + 0.5) / Double(lines)
                cg.beginPath()
                let segments = 32
                for s in 0...segments {
                    let x = size.width * Double(s) / Double(segments)
                    let wobble = sin(Double(s) * 0.55 + Double(i) * 1.7) * 1.8
                        + sin(Double(s) * 0.19 + Double(i) * 4.1) * 3.0
                    let p = CGPoint(x: x, y: yBase + wobble)
                    if s == 0 { cg.move(to: p) } else { cg.addLine(to: p) }
                }
                let isLight = i % 7 == 3
                let alpha = isLight ? 0.05 : 0.05 + 0.06 * abs(sin(Double(i) * 2.3))
                cg.setStrokeColor(isLight
                    ? UIColor(red: 1, green: 0.92, blue: 0.75, alpha: CGFloat(alpha)).cgColor
                    : UIColor.black.withAlphaComponent(CGFloat(alpha)).cgColor)
                cg.setLineWidth(isLight ? 1.4 : 1.0)
                cg.strokePath()
            }

            // 两处木节：同心椭圆环，深褐。
            for (cx, cy, r) in [(118.0, 150.0, 15.0), (398.0, 372.0, 11.0)] {
                for ring in 0..<4 {
                    let rr = r * (1 - Double(ring) * 0.22)
                    cg.setStrokeColor(UIColor.black.withAlphaComponent(0.10 + 0.03 * Double(ring)).cgColor)
                    cg.setLineWidth(1.6)
                    cg.strokeEllipse(in: CGRect(x: cx - rr, y: cy - rr * 0.62,
                                                width: rr * 2, height: rr * 1.24))
                }
            }
        }
    }

    // MARK: - 环境反射图

    private static func makeEnvironmentImage() -> UIImage {
        let size = CGSize(width: 512, height: 256)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            // 纵向渐变：深棕（顶）→ 明亮暖带（窗光）→ 黄铜色中段 → 近黑（底）
            let colors = [
                UIColor(red: 0.13, green: 0.08, blue: 0.04, alpha: 1).cgColor,
                UIColor(red: 0.98, green: 0.88, blue: 0.62, alpha: 1).cgColor,
                UIColor(red: 0.55, green: 0.38, blue: 0.18, alpha: 1).cgColor,
                UIColor(red: 0.07, green: 0.045, blue: 0.03, alpha: 1).cgColor,
            ] as CFArray
            let locations: [CGFloat] = [0, 0.36, 0.58, 1]
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: colors, locations: locations) {
                cg.drawLinearGradient(gradient,
                                      start: CGPoint(x: 0, y: 0),
                                      end: CGPoint(x: 0, y: size.height),
                                      options: [])
            }
            // 窗光高光团：径向渐变，让金属表面出现一块集中的亮斑而非均匀亮带。
            let spotColors = [
                UIColor.white.withAlphaComponent(0.85).cgColor,
                UIColor.white.withAlphaComponent(0).cgColor,
            ] as CFArray
            if let spot = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: spotColors, locations: [0, 1]) {
                cg.drawRadialGradient(spot,
                                      startCenter: CGPoint(x: size.width * 0.62, y: size.height * 0.30),
                                      startRadius: 0,
                                      endCenter: CGPoint(x: size.width * 0.62, y: size.height * 0.30),
                                      endRadius: size.width * 0.30,
                                      options: [.drawsAfterEndLocation])
            }
        }
    }

    /// 确定性伪随机（0..<1），与音频引擎的合成噪声同思路：同样输入永远同样输出。
    private static func hash(_ i: Int) -> Double {
        let x = sin(Double(i) * 12.9898) * 43758.5453
        return x - floor(x)
    }
}
