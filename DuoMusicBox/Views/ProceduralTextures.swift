import UIKit

/// 程序生成的贴图（零外部素材）：胡桃木纹、环境反射图、黄铜拉丝/径向纹、
/// 粗糙度变化图与接触阴影。
/// 全部用 CoreGraphics 现场绘制，算法与 Theme.WoodPanel 的木纹（正弦扰动横纹 +
/// 确定性伪随机）同源，保证 2D 界面与 3D 场景的木质视觉是同一块"木头"。
/// 只生成一次（静态常量），场景内多节点共享同一张图。
public enum ProceduralTextures {
    /// 胡桃木纹（512×512），用作 3D 盒体/背板的漫反射贴图。
    public static let walnut: UIImage = makeWalnutTexture()

    /// 胡桃木粗糙度图（512×512 灰度，SceneKit 采样绿通道）：
    /// 与漫反射同为横纹大结构，让木面高光随纹理起伏，不再是均匀塑料感。
    public static let walnutRoughness: UIImage = makeWalnutRoughnessTexture()

    /// 环境反射图（512×256 等距柱状）：上方一道明亮的暖色"窗光"带，
    /// 下方沉入深棕——赋给 SceneKit 的 lightingEnvironment 后，
    /// 黄铜与钢的金属表面会映出这道光带，金属感主要来自于此。
    public static let environment: UIImage = makeEnvironmentImage()

    /// 拉丝黄铜（512×512，底色已烤入）：逐行亮度微扰的横向拉丝，
    /// 行方向与圆柱 UV 的 v 轴对应——绕鼓一周（u 向）纹理恒定，天然无接缝。
    public static let brushedBrass: UIImage = makeBrushedBrassTexture(base: (0.84, 0.66, 0.31), seed: 11)

    /// 同一套拉丝、深一号烤色：发条筒侧面用。
    public static let brushedBrassDark: UIImage = makeBrushedBrassTexture(base: (0.55, 0.40, 0.16), seed: 47)

    /// 拉丝粗糙度图（512×512 灰度）：数值在 0.25–0.45 间随行变化、
    /// 几条抛光带压到 0.25，与 brushedBrass 叠用在鼓面/筒面材质上。
    public static let brushedRoughness: UIImage = makeBrushedRoughnessTexture()

    /// 端盖径向拉丝（256×256）：同心环微扰 + 中心亮、边缘沉的径向渐变，
    /// 假造车床端面的旋转纹路，用于滚筒端盖与发条筒盖面。
    public static let radialBrass: UIImage = makeRadialBrassTexture()

    /// 接触阴影（256×256，带 alpha）：中心深、边缘透明的径向渐变黑，
    /// 贴在底座顶面给机芯压出"落地"的暗斑，与方向光投影叠加使用。
    public static let contactShadow: UIImage = makeContactShadowTexture()

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
            // 精修后线数 110 → 150、深线 alpha 上限 0.11 → 0.14：对比更读得出。
            let lines = 150
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
                let alpha = isLight ? 0.07 : 0.05 + 0.09 * abs(sin(Double(i) * 2.3))
                cg.setStrokeColor(isLight
                    ? UIColor(red: 1, green: 0.92, blue: 0.75, alpha: CGFloat(alpha)).cgColor
                    : UIColor.black.withAlphaComponent(CGFloat(alpha)).cgColor)
                cg.setLineWidth(isLight ? 1.4 : 1.0)
                cg.strokePath()
            }

            // 强年轮线：5 条更深更粗的线（同一扰动公式），
            // 给大面积木面一个远看也可读的纹理骨架。
            for i in [13, 41, 77, 108, 136] {
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
                cg.setStrokeColor(UIColor.black.withAlphaComponent(0.16).cgColor)
                cg.setLineWidth(2.2)
                cg.strokePath()
            }

            // 木孔微斑：两千个极小短点（深色为主、少量亮点），近看才有颗粒感。
            for i in 0..<2000 {
                let x = hash(i &* 37 &+ 11) * 512
                let y = hash(i &* 53 &+ 7) * 512
                let light = hash(i &* 71 &+ 3) > 0.82
                cg.setFillColor(light
                    ? UIColor(red: 1, green: 0.9, blue: 0.72, alpha: 0.06).cgColor
                    : UIColor.black.withAlphaComponent(CGFloat(0.04 + 0.05 * hash(i &* 97 &+ 1))).cgColor)
                cg.fill(CGRect(x: CGFloat(x), y: CGFloat(y),
                               width: CGFloat(1 + hash(i &* 113 &+ 5) * 2), height: 0.9))
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

    private static func makeWalnutRoughnessTexture() -> UIImage {
        let size = CGSize(width: 512, height: 512)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            // 基底 0.84（与原先的均匀粗糙度同量级），其上叠横向起伏。
            cg.setFillColor(UIColor(white: 0.84, alpha: 1).cgColor)
            cg.fill(CGRect(origin: .zero, size: size))
            // 宽带起伏：0.78–0.91
            for i in 0..<64 {
                let y = size.height * Double(i) / 64.0
                let v = 0.78 + 0.13 * hash(i &* 19 &+ 29)
                cg.setFillColor(UIColor(white: CGFloat(v), alpha: 0.55).cgColor)
                cg.fill(CGRect(x: 0, y: CGFloat(y), width: size.width, height: size.height / 64 + 1))
            }
            // 细行起伏：0.80–0.92，与漫反射的横纹同为大尺度横结构即可，
            // 不追求逐行对齐——粗糙度变化本身是低频观感。
            for y in stride(from: 0, to: 512, by: 3) {
                let v = 0.80 + 0.12 * hash(y &* 7 &+ 3)
                cg.setFillColor(UIColor(white: CGFloat(v), alpha: 0.35).cgColor)
                cg.fill(CGRect(x: 0, y: CGFloat(y), width: size.width, height: 1))
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
            // 精修：窗光带提亮到近纯暖白、顶部压得更深，带与底的对比更强，
            // 圆柱面上的高光带因此更成形、更有方向。
            let colors = [
                UIColor(red: 0.10, green: 0.06, blue: 0.03, alpha: 1).cgColor,
                UIColor(red: 1.00, green: 0.93, blue: 0.70, alpha: 1).cgColor,
                UIColor(red: 0.58, green: 0.40, blue: 0.19, alpha: 1).cgColor,
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
                UIColor.white.withAlphaComponent(0.95).cgColor,
                UIColor.white.withAlphaComponent(0).cgColor,
            ] as CFArray
            if let spot = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: spotColors, locations: [0, 1]) {
                cg.drawRadialGradient(spot,
                                      startCenter: CGPoint(x: size.width * 0.62, y: size.height * 0.30),
                                      startRadius: 0,
                                      endCenter: CGPoint(x: size.width * 0.62, y: size.height * 0.30),
                                      endRadius: size.width * 0.34,
                                      options: [.drawsAfterEndLocation])
            }
            // 左下弱冷光团：钢件（音梳/转轴/齿轮螺丝）下缘映出一点冷色，
            // 与暖窗光成对照，也呼应场景里的冷色轮廓光。
            let coolColors = [
                UIColor(red: 0.72, green: 0.82, blue: 1.0, alpha: 0.35).cgColor,
                UIColor(red: 0.72, green: 0.82, blue: 1.0, alpha: 0).cgColor,
            ] as CFArray
            if let cool = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: coolColors, locations: [0, 1]) {
                cg.drawRadialGradient(cool,
                                      startCenter: CGPoint(x: size.width * 0.16, y: size.height * 0.74),
                                      startRadius: 0,
                                      endCenter: CGPoint(x: size.width * 0.16, y: size.height * 0.74),
                                      endRadius: size.width * 0.24,
                                      options: [.drawsAfterEndLocation])
            }
        }
    }

    // MARK: - 黄铜拉丝（鼓面/筒面）

    /// 拉丝底色烤入 diffuse：SceneKit 的 PBR 漫反射槽位只能放一个 contents，
    /// 贴图即颜色本身，故底色作为参数传入（鼓面亮版 / 发条筒深版共用一套算法）。
    private static func makeBrushedBrassTexture(base: (Double, Double, Double), seed: Int) -> UIImage {
        let size = CGSize(width: 512, height: 512)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            cg.setFillColor(UIColor(red: CGFloat(base.0), green: CGFloat(base.1),
                                    blue: CGFloat(base.2), alpha: 1).cgColor)
            cg.fill(CGRect(origin: .zero, size: size))

            // 逐行拉丝：每行（= 圆柱 v 向一圈）亮度做 ±5% 确定性微扰；
            // 同一行内沿 u 恒定，绕鼓一周无接缝。
            for y in 0..<512 {
                let delta = (hash(seed &* 1000 &+ y) - 0.5) * 0.10
                cg.setFillColor(delta >= 0
                    ? UIColor.white.withAlphaComponent(CGFloat(delta)).cgColor
                    : UIColor.black.withAlphaComponent(CGFloat(-delta)).cgColor)
                cg.fill(CGRect(x: 0, y: CGFloat(y), width: size.width, height: 1))
            }

            // 抛光带：几段较宽的行带微微提亮（车削/擦拭留下的亮痕）。
            for b in 0..<9 {
                let y0 = hash(seed &* 31 &+ b) * 512
                let height = 5 + hash(seed &* 57 &+ b) * 16
                cg.setFillColor(UIColor.white.withAlphaComponent(
                    CGFloat(0.03 + 0.04 * hash(seed &* 91 &+ b))).cgColor)
                cg.fill(CGRect(x: 0, y: CGFloat(y0), width: size.width, height: CGFloat(height)))
            }

            // 短划痕：细小水平短线，明暗各半，只在近看时出现。
            for i in 0..<700 {
                let x = hash(seed &* 131 &+ i) * 512
                let y = hash(seed &* 197 &+ i) * 512
                let len = 6 + hash(seed &* 233 &+ i) * 42
                let light = hash(seed &* 271 &+ i) > 0.5
                cg.setFillColor(light
                    ? UIColor.white.withAlphaComponent(0.05).cgColor
                    : UIColor.black.withAlphaComponent(0.05).cgColor)
                cg.fill(CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(len), height: 1))
            }
        }
    }

    private static func makeBrushedRoughnessTexture() -> UIImage {
        let size = CGSize(width: 512, height: 512)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            // 基底 0.35；逐行在 0.25–0.45 间变化（与拉丝漫反射同为横行结构）。
            cg.setFillColor(UIColor(white: 0.35, alpha: 1).cgColor)
            cg.fill(CGRect(origin: .zero, size: size))
            for y in 0..<512 {
                let v = 0.25 + 0.20 * hash(y &* 3 &+ 7)
                cg.setFillColor(UIColor(white: CGFloat(v), alpha: 1).cgColor)
                cg.fill(CGRect(x: 0, y: CGFloat(y), width: size.width, height: 1))
            }
            // 几条抛光带压回 0.25：与漫反射的亮带大尺度对应（不要求逐行对齐）。
            for b in 0..<7 {
                let y0 = hash(b &* 41 &+ 3) * 512
                cg.setFillColor(UIColor(white: 0.25, alpha: 1).cgColor)
                cg.fill(CGRect(x: 0, y: CGFloat(y0), width: size.width,
                               height: CGFloat(6 + hash(b &* 67 &+ 5) * 14)))
            }
        }
    }

    // MARK: - 端盖径向拉丝

    private static func makeRadialBrassTexture() -> UIImage {
        let size = CGSize(width: 256, height: 256)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            cg.setFillColor(UIColor(red: 0.86, green: 0.68, blue: 0.33, alpha: 1).cgColor)
            cg.fill(CGRect(origin: .zero, size: size))
            let center = CGPoint(x: 128, y: 128)
            // 同心拉丝环：半径逐圈做亮度微扰，假造车床端面的旋转纹。
            var r = 128.0
            var ring = 0
            while r > 2 {
                let delta = (hash(ring &* 17 &+ 23) - 0.5) * 0.14
                cg.setStrokeColor(delta >= 0
                    ? UIColor.white.withAlphaComponent(CGFloat(delta)).cgColor
                    : UIColor.black.withAlphaComponent(CGFloat(-delta)).cgColor)
                cg.setLineWidth(1.6)
                cg.strokeEllipse(in: CGRect(x: center.x - CGFloat(r), y: center.y - CGFloat(r),
                                            width: CGFloat(r) * 2, height: CGFloat(r) * 2))
                r -= 2.2
                ring += 1
            }
            // 径向明暗：中心微亮、边缘压沉，端盖看起来微微隆起。
            let shadeColors = [
                UIColor.white.withAlphaComponent(0.16).cgColor,
                UIColor.black.withAlphaComponent(0.20).cgColor,
            ] as CFArray
            if let shade = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: shadeColors, locations: [0, 1]) {
                cg.drawRadialGradient(shade,
                                      startCenter: center, startRadius: 6,
                                      endCenter: center, endRadius: 128,
                                      options: [.drawsAfterEndLocation])
            }
        }
    }

    // MARK: - 接触阴影

    private static func makeContactShadowTexture() -> UIImage {
        let size = CGSize(width: 256, height: 256)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false // 必须保留 alpha：贴图靠透明度混合压暗底座
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            let colors = [
                UIColor.black.withAlphaComponent(0.52).cgColor,
                UIColor.black.withAlphaComponent(0.30).cgColor,
                UIColor.black.withAlphaComponent(0).cgColor,
            ] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: colors, locations: [0, 0.62, 1]) {
                cg.drawRadialGradient(gradient,
                                      startCenter: CGPoint(x: 128, y: 128), startRadius: 0,
                                      endCenter: CGPoint(x: 128, y: 128), endRadius: 126,
                                      options: [])
            }
        }
    }

    /// 确定性伪随机（0..<1），与音频引擎的合成噪声同思路：同样输入永远同样输出。
    private static func hash(_ i: Int) -> Double {
        let x = sin(Double(i) * 12.9898) * 43758.5453
        return x - floor(x)
    }
}
