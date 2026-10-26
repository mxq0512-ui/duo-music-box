import SwiftUI
import SceneKit
import CoreMotion
import UIKit

/// Phase 2 机械主体 3D 视图（SceneKit），替代 Phase 1 的 Canvas 2.5D CylinderView / GearView。
///
/// 不变的约定（与 Phase 1 完全同源，杜绝第二套时间线）：
/// - 滚筒旋转角只来自 PlaybackEngine.cylinderRotation（由 stepFloat 推导），
///   本视图只把它换算成弧度赋给鼓体节点，不持有任何时钟。
/// - 音钉落位与点按反解都走 MechanismMath 的同一组正/逆公式，与声音、编曲器共用同一份 Melody。
/// - 齿轮/调速器角度是滚筒角的纯函数（MechanismMath，公式与 Phase 1 GearView 逐字对应）。
/// - 音梳振动由 PlaybackEngine.lastStepTrigger（只读观察口）驱动，不回探音频调度。
/// - 发条钥匙的转角来自 WindingControl 的手势回调（MusicBoxView 中转），储能读 springCharge，
///   模型仍在 PlaybackEngine，本视图只呈现。
///
/// 布局不变量保持：本视图只占机械主体区（盒盖区仍是 SwiftUI 的木质横幅）；
/// 场景内自上而下依次是音梳、滚筒、齿轮/发条，与 Phase 1 的上下关系一致。
///
/// 画面精修约定：投影来自 key 光（自动投影包围全场，投影开关在建场末尾统一设置）；
/// 材质细节全部程序贴图（ProceduralTextures 的拉丝/径向/粗糙度图）；
/// 相机 (0, 0.35, 5.3) / fov 47 是按面板宽高比（≥1.43）算过的满幅机位——
/// 在 z=0 平面可见高约 4.61、内容（音梳顶 1.43 ~ 齿轮底 −1.84）上下各留约 0.66
/// 余量（含视差最坏偏移）；改机位前先按此口径重算。
public struct MechanismSceneView: View {
    public let melody: Melody
    @ObservedObject public var playback: PlaybackEngine
    public let rotationDegrees: Double
    /// 当前步被触发的音高集合（梳齿高亮用，与 Phase 1 CylinderView 同语义）。
    public let triggeredPitches: Set<Int>
    public let springCharge: Double
    /// 上发条钥匙的累计转角（度，来自 WindingControl 手势）。
    public let windingKeyAngle: Double
    public let isEditing: Bool
    public var onToggleNote: ((Int, Int) -> Void)?

    public init(melody: Melody,
                playback: PlaybackEngine,
                rotationDegrees: Double,
                triggeredPitches: Set<Int>,
                springCharge: Double,
                windingKeyAngle: Double,
                isEditing: Bool,
                onToggleNote: ((Int, Int) -> Void)? = nil) {
        self.melody = melody
        self.playback = playback
        self.rotationDegrees = rotationDegrees
        self.triggeredPitches = triggeredPitches
        self.springCharge = springCharge
        self.windingKeyAngle = windingKeyAngle
        self.isEditing = isEditing
        self.onToggleNote = onToggleNote
    }

    public var body: some View {
        MechanismSceneRepresentable(melody: melody,
                                    playback: playback,
                                    rotationDegrees: rotationDegrees,
                                    triggeredPitches: triggeredPitches,
                                    springCharge: springCharge,
                                    windingKeyAngle: windingKeyAngle,
                                    isEditing: isEditing,
                                    onToggleNote: onToggleNote)
    }
}

// MARK: - UIViewRepresentable 桥

private struct MechanismSceneRepresentable: UIViewRepresentable {
    var melody: Melody
    var playback: PlaybackEngine
    var rotationDegrees: Double
    var triggeredPitches: Set<Int>
    var springCharge: Double
    var windingKeyAngle: Double
    var isEditing: Bool
    var onToggleNote: ((Int, Int) -> Void)?

    func makeCoordinator() -> MechanismSceneCoordinator {
        MechanismSceneCoordinator()
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero, options: nil)
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = .clear
        view.isOpaque = false
        view.allowsCameraControl = false
        context.coordinator.attach(to: view, playback: playback)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.update(melody: melody,
                                   rotationDegrees: rotationDegrees,
                                   triggeredPitches: triggeredPitches,
                                   springCharge: springCharge,
                                   windingKeyAngle: windingKeyAngle,
                                   isEditing: isEditing,
                                   onToggleNote: onToggleNote)
    }

    static func dismantleUIView(_ view: SCNView, coordinator: MechanismSceneCoordinator) {
        coordinator.detach()
    }
}

// MARK: - 场景协调器（建场 + 每帧状态应用）

final class MechanismSceneCoordinator: NSObject, SCNSceneRendererDelegate {
    private let scene = SCNScene()
    private weak var sceneView: SCNView?
    private weak var playback: PlaybackEngine?

    // 动态节点
    private let drumGroup = SCNNode()
    private var drumMesh: SCNNode!
    private let pinGroup = SCNNode()
    private let ringGroup = SCNNode()
    private var bigGearGroup: SCNNode!
    private var smallGearGroup: SCNNode!
    private var governorGroup: SCNNode!
    private var keyGroup: SCNNode!
    private var springHand: SCNNode!
    private var teeth: [SCNNode] = []
    private var toothBaseAngles: [Float] = []
    private var toothMaterials: [SCNMaterial] = []

    // 共享几何/材质（全场景各一份，节点只引用不复制）
    // 音钉（珍藏级一轮）：半径 0.048 → 0.05、段数提到 28（球面更圆、镜面高光更整），
    // 材质改用专用抛光黄铜（见 buildScene 的 pinMaterial），不再与钥匙共用。
    private let pinGeometry: SCNSphere = {
        let sphere = SCNSphere(radius: 0.05)
        sphere.segmentCount = 28
        return sphere
    }()
    private let stepRingGeometry = SCNBox(width: CGFloat(MechanismMath.drumLength),
                                          height: 0.02, length: 0.008, chamferRadius: 0)
    private let columnRingGeometry = SCNTorus(ringRadius: CGFloat(MechanismMath.drumRadius) + 0.002,
                                              pipeRadius: 0.005)
    /// 编辑网格环（步环 + 列界环）共用的深色恒定光照材质：看起来像鼓面刻线，不随光照变化。
    private let ringMaterial: SCNMaterial = {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = UIColor(red: 0.16, green: 0.11, blue: 0.05, alpha: 1)
        return m
    }()

    // 状态缓存（避免每帧重复建节点/改材质）
    private var lastMelody: Melody?
    private var lastStepCount = -1
    private var lastTriggeredPitches: Set<Int> = []
    private var lastTriggerTime: CFTimeInterval = -1
    private var lastWindingAngle: Double = .nan
    private var lastWindingChange: CFTimeInterval = 0

    // 编曲模式手动滚筒（Phase 3）：纵向拖动把滚筒转到想放钉的位置。
    // manualDrumOffsetDegrees 与播放旋转叠加在鼓体上；播放一起步即逐帧衰减归零，
    // 由播放时钟平滑接管。dragStartOffset/dragMoved 供手势消歧：拖动结束 0.3 秒内的
    // 点按视为拖动的收尾，不触发装/拆钉。
    private var manualDrumOffsetDegrees: Double = 0
    private var lastPlaybackRotation: Double = 0
    private var dragStartOffset: Double = 0
    private var dragMoved = false
    private var lastDragEndTime: CFTimeInterval = 0
    private var strikeTimes: [Int: TimeInterval] = [:]
    private let strikeLock = NSLock()
    private var editing = false
    private var toggleHandler: ((Int, Int) -> Void)?

    // 裸眼 3D 视差：相机挂在 rig 上（只动机位不动相机本地变换），注视目标需逐帧改位故留引用。
    private let cameraRig = SCNNode()
    private var lookTargetNode: SCNNode!
    // CoreMotion 姿态：回调跑在 motionQueue 上只存增量，渲染帧加锁读取。
    private let motionManager = CMMotionManager()
    private let motionQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.jacky.duomusicbox.parallax-motion"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private var motionRunning = false
    private let attitudeLock = NSLock()
    private var referencePitch: Double?
    private var referenceRoll: Double?
    private var targetPitchDelta: Double = 0
    private var targetRollDelta: Double = 0
    // 平滑后的机位偏移（只在渲染帧内读写）；lastRenderTime 用于帧率无关的阻尼系数。
    private var smoothedParallaxX: Double = 0
    private var smoothedParallaxY: Double = 0
    private var lastRenderTime: TimeInterval?

    override init() {
        super.init()
        buildScene()
    }

    // MARK: 附着/分离

    func attach(to view: SCNView, playback: PlaybackEngine) {
        sceneView = view
        self.playback = playback
        view.scene = scene
        view.delegate = self
        // 持续渲染：早期版本用「按需补一帧」省电，但在模拟器/截图与冷启动下
        // 补帧可能赶在呈现前被关掉而整屏空白。八音盒是展示型单屏 App，
        // 优先保证画面永远在屏，常开销可接受（见 Phase 2 交付报告修订）。
        view.isPlaying = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        view.addGestureRecognizer(tap)
        // 编曲模式拖动滚筒：与点按并存，靠位移阈值与收尾时间窗消歧（见 handlePan）。
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        view.addGestureRecognizer(pan)
        startParallaxMotion()
    }

    func detach() {
        stopParallaxMotion()
        sceneView?.delegate = nil
        sceneView = nil
        smoothedParallaxX = 0
        smoothedParallaxY = 0
        lastRenderTime = nil
    }

    // MARK: 建场（一次性，几何与材质全部共享）

    private func buildScene() {
        let root = scene.rootNode
        scene.lightingEnvironment.contents = ProceduralTextures.environment
        // 珍藏级一轮：环境图升级为双柔光箱（1024×512），强度 1.05 → 1.15，
        // 让鼓面高光流得动、音钉与抛光件的镜面反射更挺。
        scene.lightingEnvironment.intensity = 1.15

        // —— 材质（色值与 Theme 一一对应，保证 2D/3D 同一视觉语言）——
        let brass = pbrMaterial(color: (0.83, 0.65, 0.30), metalness: 1.0, roughness: 0.30)
        let brassBright = pbrMaterial(color: (0.99, 0.87, 0.56), metalness: 1.0, roughness: 0.22)
        let brassDark = pbrMaterial(color: (0.52, 0.38, 0.15), metalness: 0.9, roughness: 0.45)
        // 齿轮专用黄铜：比鼓面更暗更粗，与抛光鼓面拉开层次。微调轮把反照率从
        // (0.60, 0.44, 0.19) 提到 (0.74, 0.57, 0.27)、粗糙度 0.44 → 0.34：齿轮坐在
        // 鼓影里，原值读作闷剪影；新值仍明确暗于鼓面拉丝底色 (0.84, 0.66, 0.31)，
        // 层次顺序不变（鼓最亮、齿轮居中、背板最暗）。
        // 曾评估给齿轮加拉丝粗糙度图：SCNShape 端面 UV 是路径坐标（非 0–1 归一化）、
        // 挤出壁面又是另一套 UV，拉丝的走向与频率不可控，故不加，齿轮走纯色 +
        // 倒角高光的路线。
        let gearBrass = pbrMaterial(color: (0.74, 0.57, 0.27), metalness: 1.0, roughness: 0.34)
        let grooveBrass = pbrMaterial(color: (0.38, 0.27, 0.10), metalness: 0.9, roughness: 0.50)
        // 钢件（音梳/转轴/螺丝）：冷色调抛光钢，与暖黄铜形成材质对照。
        // 珍藏级一轮：粗糙度 0.18 → 0.13，梳齿与转轴近镜面，冷光刃口更利。
        let steel = pbrMaterial(color: (0.70, 0.75, 0.85), metalness: 1.0, roughness: 0.13)
        let steelDark = pbrMaterial(color: (0.40, 0.44, 0.53), metalness: 0.95, roughness: 0.38)
        // 滚筒：侧面用拉丝黄铜贴图（底色烤入 diffuse）+ 拉丝粗糙度图（0.25–0.45），
        // 端盖用径向拉丝贴图。SCNCylinder 材质槽位顺序为 [侧面, 顶盖, 底盖]，
        // 两端盖同用径向纹，左右对称无方向问题。
        let drumSide = SCNMaterial()
        drumSide.lightingModel = .physicallyBased
        // 珍藏级一轮：鼓面改用滚筒专用拉丝（两端渐暗 + 细划痕 + 氧化斑）
        // 并叠加拉丝法线图，掠射光下出现环向沟纹光泽。
        drumSide.diffuse.contents = ProceduralTextures.brushedBrassDrum
        drumSide.roughness.contents = ProceduralTextures.brushedRoughness
        drumSide.normal.contents = ProceduralTextures.brushedNormal
        drumSide.metalness.contents = NSNumber(value: 1.0)
        let drumCap = SCNMaterial()
        drumCap.lightingModel = .physicallyBased
        drumCap.diffuse.contents = ProceduralTextures.radialBrass
        drumCap.roughness.contents = NSNumber(value: 0.19) // 端盖更抛光，与鼓面拉丝拉开层次
        drumCap.metalness.contents = NSNumber(value: 1.0)
        // 发条筒侧面：同一套拉丝，深一号烤色。
        let barrelSide = SCNMaterial()
        barrelSide.lightingModel = .physicallyBased
        barrelSide.diffuse.contents = ProceduralTextures.brushedBrassDark
        barrelSide.roughness.contents = ProceduralTextures.brushedRoughness
        barrelSide.metalness.contents = NSNumber(value: 1.0)
        let wood = SCNMaterial()
        wood.lightingModel = .physicallyBased
        wood.diffuse.contents = ProceduralTextures.walnut
        wood.roughness.contents = ProceduralTextures.walnutRoughness
        wood.metalness.contents = NSNumber(value: 0.0)
        // 音钉专用抛光黄铜：比 brassBright 更亮、粗糙度 0.22 → 0.11 近镜面——
        // 每颗钉在鼓面上是一个独立的小亮点，滚动时逐颗闪烁，是滚筒活过来的关键。
        let pinMaterial = pbrMaterial(color: (1.0, 0.90, 0.58), metalness: 1.0, roughness: 0.11)
        pinGeometry.firstMaterial = pinMaterial

        let drumY: Float = 0.25
        let radius = Float(MechanismMath.drumRadius)
        let length = Float(MechanismMath.drumLength)

        // —— 灯光：环境光（压低，让明暗有方向）+ 主方向光（暖，投影）
        // + 补光（冷，弱）+ 轮廓光（左后冷光勾边），金属反射主要来自环境图 ——
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = UIColor(red: 0.38, green: 0.31, blue: 0.23, alpha: 1)
        ambient.light?.intensity = 0.35
        root.addChildNode(ambient)

        let lookTarget = SCNNode()
        lookTarget.position = SCNVector3(0, -0.2, 0)
        root.addChildNode(lookTarget)
        lookTargetNode = lookTarget

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.color = UIColor(red: 1.0, green: 0.93, blue: 0.80, alpha: 1)
        key.light?.intensity = 2.0
        // 投影：方向光的影相机用自动投影（automaticallyAdjustsShadowProjection
        // 显式打开）——场景包围盒只有约 5.0×4.6×2.6，自动拟合已足够紧、分辨率够用；
        // 手设 orthographicScale/zNear/zFar 反而容易裁掉影子，故不手设。
        key.light?.castsShadow = true
        key.light?.automaticallyAdjustsShadowProjection = true
        key.light?.shadowMapSize = CGSize(width: 1024, height: 1024)
        key.light?.shadowRadius = 4
        key.light?.shadowColor = UIColor(white: 0, alpha: 0.45)
        key.light?.shadowBias = 0.008
        key.position = SCNVector3(4, 6, 5)
        key.constraints = [SCNLookAtConstraint(target: lookTarget)]
        root.addChildNode(key)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .directional
        fill.light?.color = UIColor(red: 0.72, green: 0.78, blue: 0.90, alpha: 1)
        fill.light?.intensity = 0.45 // 微调轮 0.35 → 0.45：只轻抬下排齿轮/发条/调速器一带
        fill.position = SCNVector3(-5, 2, 4)
        fill.constraints = [SCNLookAtConstraint(target: lookTarget)]
        root.addChildNode(fill)

        // 轮廓光：左后方冷色方向光（不投影），给滚筒左缘、端板与齿尖勾一条冷边，
        // 把暖色机芯从同为暖色的背板上分离出来。
        let rim = SCNNode()
        rim.light = SCNLight()
        rim.light?.type = .directional
        rim.light?.color = UIColor(red: 0.62, green: 0.72, blue: 1.0, alpha: 1)
        rim.light?.intensity = 0.9
        rim.position = SCNVector3(-4.5, 3.0, -3.5)
        rim.constraints = [SCNLookAtConstraint(target: lookTarget)]
        root.addChildNode(rim)

        // —— 相机：挂在 rig 上，视差只移动 rig（见 applyParallax），相机本地
        // 位置与 lookAt 约束保持不变，静止时与固定机位画面逐像素一致。
        // 精修机位：z 6.6 → 5.3、fov 40 → 47、y 0.55 → 0.35——取景范围（z=0 处
        // 可见高 4.80 → 4.61）几乎不变，但相机更近、透视梯度更陡
        // （鼓面近/远端距离比 5.6/7.6 → 4.3/6.3），圆柱的"圆"与前后层次随之增强，
        // 且同样的 rig 偏移在更近的机位上张角更大，视差也更读得出。
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 47
        cameraNode.position = SCNVector3(0, 0.35, 5.3)
        cameraNode.constraints = [SCNLookAtConstraint(target: lookTarget)]
        cameraRig.addChildNode(cameraNode)
        root.addChildNode(cameraRig)

        // —— 盒体：胡桃木背板 + 底座 ——
        let backPanel = SCNNode(geometry: SCNBox(width: 5.0, height: 4.4, length: 0.22, chamferRadius: 0.03))
        backPanel.geometry?.firstMaterial = wood
        backPanel.position = SCNVector3(0, -0.05, -1.1)
        root.addChildNode(backPanel)

        let plinth = SCNNode(geometry: SCNBox(width: 5.0, height: 0.28, length: 2.4, chamferRadius: 0.03))
        plinth.geometry?.firstMaterial = wood
        plinth.position = SCNVector3(0, -2.3, -0.15)
        root.addChildNode(plinth)

        // 接触阴影：底座顶面（y = −2.16）上方 0.005 处一张径向渐变暗斑，
        // 与 key 光投影叠加，让机芯"坐"在底座上而非浮空。
        // 不写深度、靠贴图 alpha 混合压暗；自身不参与投影（建场末尾统一排除）。
        let contactShadow = SCNNode(geometry: SCNPlane(width: 4.6, height: 1.9))
        let contactMaterial = SCNMaterial()
        contactMaterial.lightingModel = .constant
        contactMaterial.diffuse.contents = ProceduralTextures.contactShadow
        contactMaterial.writesToDepthBuffer = false
        contactShadow.geometry?.firstMaterial = contactMaterial
        contactShadow.eulerAngles.x = -Float.pi / 2
        contactShadow.position = SCNVector3(0, -2.155, 0.15)
        root.addChildNode(contactShadow)

        // —— 机芯框架：左右黄铜端板 + 转轴 ——
        // 珍藏级一轮：端板不再是一块闷暗平板——朝内/外的大面用径向拉丝（与端盖同
        // 纹理语言），朝观者的前缘用抛光黄铜条抓光；转轴穿板处加抛光轴套（轴承盖），
        // 前缘上下各一颗带槽螺丝，与齿轮/音梳的零件语言统一。
        // SCNBox 材质槽位顺序：[+x, -x, +y, -y, +z, -z]。
        let plateFace = SCNMaterial()
        plateFace.lightingModel = .physicallyBased
        plateFace.diffuse.contents = ProceduralTextures.radialBrass
        plateFace.roughness.contents = NSNumber(value: 0.30)
        plateFace.metalness.contents = NSNumber(value: 1.0)
        let plateEdge = pbrMaterial(color: (0.83, 0.65, 0.30), metalness: 1.0, roughness: 0.26)
        for side in [-1, 1] {
            let plate = SCNNode(geometry: SCNBox(width: 0.09, height: 1.7, length: 1.7, chamferRadius: 0.02))
            plate.geometry?.materials = [plateFace, plateFace, brassDark, brassDark, plateEdge, brassDark]
            plate.position = SCNVector3(Float(side) * 1.86, 0.1, 0)
            root.addChildNode(plate)

            // 轴套：转轴穿出端板处的抛光圆盖（鼓轴在 y = drumY）。
            let collar = SCNNode(geometry: SCNCylinder(radius: 0.13, height: 0.07))
            collar.geometry?.firstMaterial = brassBright
            collar.eulerAngles.z = Float.pi / 2
            collar.position = SCNVector3(Float(side) * 1.83, drumY, 0)
            root.addChildNode(collar)

            // 前缘螺丝：圆头（深钢）+ 一字槽（恒定深色小盒假造），与齿轮螺丝同规格。
            for dy in [-0.62, 0.62] {
                let screw = SCNNode(geometry: SCNCylinder(radius: 0.032, height: 0.026))
                screw.geometry?.firstMaterial = steelDark
                screw.eulerAngles.x = Float.pi / 2
                screw.position = SCNVector3(Float(side) * 1.86, Float(0.1 + dy), 0.855)
                root.addChildNode(screw)
                let slot = SCNNode(geometry: SCNBox(width: 0.052, height: 0.011, length: 0.012, chamferRadius: 0))
                slot.geometry?.firstMaterial = ringMaterial
                slot.position = SCNVector3(Float(side) * 1.86, Float(0.1 + dy), 0.87)
                root.addChildNode(slot)
            }
        }

        // —— 滚筒组（整体绕 X 轴旋转，是唯一的"转子"）——
        drumGroup.position = SCNVector3(0, drumY, 0)
        root.addChildNode(drumGroup)

        let drum = SCNNode(geometry: SCNCylinder(radius: CGFloat(radius), height: CGFloat(length)))
        drum.geometry?.materials = [drumSide, drumCap, drumCap] // [侧面, 端盖, 端盖]
        drum.eulerAngles.z = Float.pi / 2 // 圆柱默认轴向 Y，转到 X（横轴 = 音高）
        drum.name = "drum"
        drumGroup.addChildNode(drum)
        drumMesh = drum

        // 鼓身刻线环：每端两道贴面的深色细带，半径只比鼓面高 0.002，
        // 读作刻进表面的线而非凸起的箍；与下方端沿压边环一起构成端部细节。
        let grooveBand = SCNCylinder(radius: CGFloat(radius) + 0.002, height: 0.028)
        grooveBand.firstMaterial = grooveBrass
        for side in [-1, 1] {
            for inset in [0.12, 0.24] {
                let band = SCNNode(geometry: grooveBand)
                band.eulerAngles.z = Float.pi / 2
                band.position = SCNVector3(Float(side) * (length / 2 - Float(inset)), 0, 0)
                drumGroup.addChildNode(band)
            }
        }

        // 转轴：微调轮半径 0.055 → 0.077（+40%），读作实心轴杆而非铁丝；
        // 全长 3.9 → 3.87：端板外表面在 ±1.905，轴端外伸由 0.045 收至约 0.03
        //（−30%），仍完整贯穿端板。
        let axle = SCNNode(geometry: SCNCylinder(radius: 0.077, height: 3.87))
        axle.geometry?.firstMaterial = steel
        axle.eulerAngles.z = Float.pi / 2
        drumGroup.addChildNode(axle)

        // 鼓身两端压边带：略凸出鼓面的短圆柱带（与上方刻线带同类几何）。
        // 原实现用 SCNTorus 圆环面，但在云端截图中渲染成横贯画面的椭圆伪影
        // （2026-10-26 诊断：隐藏该组节点后伪影消失），故改用绕鼓轴旋转对称的
        // 圆柱带——不受鼓组旋转姿态影响，视觉意图（端部压边）不变。
        let rimBand = SCNCylinder(radius: CGFloat(radius) + 0.006, height: 0.055)
        rimBand.firstMaterial = brassDark
        for side in [-1, 1] {
            let band = SCNNode(geometry: rimBand)
            band.eulerAngles.z = Float.pi / 2
            band.position = SCNVector3(Float(side) * (length / 2 - 0.05), 0, 0)
            drumGroup.addChildNode(band)
        }

        drumGroup.addChildNode(pinGroup)
        drumGroup.addChildNode(ringGroup)
        buildColumnRings()

        // —— 音梳：基座横梁在滚筒前上方，8 齿与音高列严格对齐 ——
        let combBase = SCNNode(geometry: SCNBox(width: 3.6, height: 0.17, length: 0.34, chamferRadius: 0.02))
        combBase.geometry?.firstMaterial = steel
        combBase.position = SCNVector3(0, 1.34, 0.86)
        root.addChildNode(combBase)
        for side in [-1, 1] {
            let screw = SCNNode(geometry: SCNCylinder(radius: 0.035, height: 0.03))
            screw.geometry?.firstMaterial = steelDark
            screw.eulerAngles.x = Float.pi / 2
            screw.position = SCNVector3(Float(side) * 1.55, 1.34, 1.045)
            root.addChildNode(screw)
        }

        // 梳齿指向：齿根（1.27, 0.98）→ 齿尖目标为鼓面 38° 处，二者之差决定齿的俯角。
        let tipY = Double(drumY) + 1.03 * sin(38.0 * Double.pi / 180)
        let tipZ = 1.03 * cos(38.0 * Double.pi / 180)
        let gamma = atan2(tipY - 1.27, -(tipZ - 0.98)) // 绕 X 的俯角，推导见 MechanismMath 注释
        let colW = MechanismMath.drumLength / Double(Melody.pitchCount)
        for p in 0..<Melody.pitchCount {
            let toothLength = 0.47 - Double(p) * 0.017 // 低音齿长、高音齿短（真实音梳规律）
            let toothMaterial = (steel.copy() as? SCNMaterial) ?? steel
            let mesh = SCNNode(geometry: SCNBox(width: 0.17, height: 0.024,
                                                length: CGFloat(toothLength), chamferRadius: 0.004))
            mesh.geometry?.firstMaterial = toothMaterial
            mesh.position = SCNVector3(0, 0, Float(-toothLength / 2)) // 几何挂在齿根之后，枢轴在齿根
            let tooth = SCNNode()
            tooth.position = SCNVector3(Float(-MechanismMath.drumLength / 2 + colW * (Double(p) + 0.5)),
                                        1.27, 0.98)
            tooth.eulerAngles.x = Float(gamma)
            tooth.addChildNode(mesh)
            root.addChildNode(tooth)
            teeth.append(tooth)
            toothBaseAngles.append(Float(gamma))
            toothMaterials.append(toothMaterial)
        }

        // —— 齿轮组（滚筒下方，面向观者）——
        bigGearGroup = makeGear(teeth: 12, outerRadius: 0.52, material: gearBrass,
                                hubMaterial: steel, darkMaterial: steelDark)
        bigGearGroup.position = SCNVector3(-1.18, -1.32, 0.32)
        root.addChildNode(bigGearGroup)

        smallGearGroup = makeGear(teeth: 8, outerRadius: 0.37, material: gearBrass,
                                  hubMaterial: steel, darkMaterial: steelDark)
        smallGearGroup.position = SCNVector3(-0.469, -1.579, 0.32)
        root.addChildNode(smallGearGroup)

        // 调速器：两片交叉翼片（Phase 1 governor 的 3D 对应物）
        let governor = SCNNode()
        for i in 0..<2 {
            let vane = SCNNode(geometry: SCNBox(width: 0.09, height: 0.4, length: 0.02, chamferRadius: 0.008))
            vane.geometry?.firstMaterial = steel
            vane.eulerAngles.z = Float(i) * Float.pi / 2
            governor.addChildNode(vane)
        }
        let govHub = SCNNode(geometry: SCNCylinder(radius: 0.05, height: 0.16))
        govHub.geometry?.firstMaterial = brassDark
        govHub.eulerAngles.x = Float.pi / 2
        governor.addChildNode(govHub)
        // 与齿轮同规格的零件语言：向后伸的短轴 + 正面轴端盖。
        let govAxle = SCNNode(geometry: SCNCylinder(radius: 0.028, height: 0.5))
        govAxle.geometry?.firstMaterial = steelDark
        govAxle.eulerAngles.x = Float.pi / 2
        govAxle.position = SCNVector3(0, 0, -0.14)
        governor.addChildNode(govAxle)
        let govCap = SCNNode(geometry: SCNCylinder(radius: 0.034, height: 0.05))
        govCap.geometry?.firstMaterial = brassBright
        govCap.eulerAngles.x = Float.pi / 2
        govCap.position = SCNVector3(0, 0, 0.10)
        governor.addChildNode(govCap)
        governor.position = SCNVector3(1.45, -1.42, 0.32)
        root.addChildNode(governor)
        governorGroup = governor

        // —— 发条：鼓身 + 量表指针 + 上链钥匙 ——
        // 筒身侧面走拉丝、正/背面盖走径向纹（材质槽位同滚筒 [侧面, 盖, 盖]）；
        // 正面再压一块略凸出的径向纹圆盘作筒盖、配收细的外圈，轮廓读作
        // "带盖的筒"而非敞口的碗；筒身后缘一道深色凹槽环强调筒深。
        let barrel = SCNNode(geometry: SCNCylinder(radius: 0.44, height: 0.30))
        barrel.geometry?.materials = [barrelSide, drumCap, drumCap]
        barrel.eulerAngles.x = Float.pi / 2
        barrel.position = SCNVector3(0.72, -1.58, 0.32)
        root.addChildNode(barrel)
        let barrelLid = SCNNode(geometry: SCNCylinder(radius: 0.40, height: 0.025))
        barrelLid.geometry?.firstMaterial = drumCap
        barrelLid.eulerAngles.x = Float.pi / 2
        barrelLid.position = SCNVector3(0.72, -1.58, 0.485)
        root.addChildNode(barrelLid)
        let barrelRing = SCNNode(geometry: SCNTorus(ringRadius: 0.44, pipeRadius: 0.022))
        barrelRing.geometry?.firstMaterial = brass
        barrelRing.position = SCNVector3(0.72, -1.58, 0.48)
        root.addChildNode(barrelRing)
        let barrelGroove = SCNNode(geometry: SCNTorus(ringRadius: 0.44, pipeRadius: 0.012))
        barrelGroove.geometry?.firstMaterial = grooveBrass
        barrelGroove.position = SCNVector3(0.72, -1.58, 0.20)
        root.addChildNode(barrelGroove)

        let handMesh = SCNNode(geometry: SCNBox(width: 0.05, height: 0.34, length: 0.03, chamferRadius: 0.01))
        handMesh.geometry?.firstMaterial = brassBright
        handMesh.position = SCNVector3(0, 0.13, 0)
        let hand = SCNNode()
        hand.position = SCNVector3(0.72, -1.58, 0.50)
        hand.addChildNode(handMesh)
        root.addChildNode(hand)
        springHand = hand

        // 蝶形钥匙：中轴 + 立柱 + 双环握柄（与 WindingControl 的 2D 钥匙同造型）。
        // 微调轮：全组改用与量表指针同款的抛光亮黄铜 brassBright 抓光，并整体
        // 放大 ×1.25；放大绕自身原点，中轴后端会向筒内多伸 0.15 × 0.25 = 0.0375，
        // 故位置 z 由 0.62 补到 0.6575，轴底仍落在发条筒正面（z = 0.47），不悬不陷。
        // 转动行为不变：update() 只写 keyGroup.eulerAngles.z，与 scale 正交。
        let windKey = SCNNode()
        let shaft = SCNNode(geometry: SCNCylinder(radius: 0.045, height: 0.30))
        shaft.geometry?.firstMaterial = brassBright
        shaft.eulerAngles.x = Float.pi / 2
        windKey.addChildNode(shaft)
        let stem = SCNNode(geometry: SCNBox(width: 0.06, height: 0.30, length: 0.05, chamferRadius: 0.01))
        stem.geometry?.firstMaterial = brassBright
        stem.position = SCNVector3(0, 0.10, 0.14)
        windKey.addChildNode(stem)
        for side in [-1, 1] {
            let loop = SCNNode(geometry: SCNTorus(ringRadius: 0.115, pipeRadius: 0.028))
            loop.geometry?.firstMaterial = brassBright
            loop.position = SCNVector3(Float(side) * 0.115, 0.30, 0.14)
            windKey.addChildNode(loop)
        }
        windKey.scale = SCNVector3(1.25, 1.25, 1.25)
        windKey.position = SCNVector3(0.72, -1.58, 0.6575)
        root.addChildNode(windKey)
        keyGroup = windKey

        // 投影开关（建场最后一步统一设置）：所有带几何体的零件既投射也承接——
        // 音梳的影子落到鼓面、齿轮的影子落到背板与底座，是这一轮深度感的关键。
        // 唯独排除编辑参考环（贴在鼓面的引导线，投影会留下假刻线）与接触阴影面本身；
        // 相机/灯光/注视目标无几何体，天然跳过。
        applyShadowFlags(node: root, excluded: [ringGroup, contactShadow])
    }

    /// 递归设置 castsShadow；excluded 中的子树整体跳过（身份比对）。承接阴影由材质自动完成。
    private func applyShadowFlags(node: SCNNode, excluded: [SCNNode]) {
        if excluded.contains(where: { $0 === node }) { return }
        if node.geometry != nil {
            node.castsShadow = true
            // 注：SceneKit 没有节点级 receivesShadow —— 被投影光照亮的材质自动承接阴影。
        }
        for child in node.childNodes {
            applyShadowFlags(node: child, excluded: excluded)
        }
    }

    /// 齿轮：梯形齿廓（与 GearView.GearShape 同一公式）拉伸成型 + 轴毂。
    private func makeGear(teeth: Int, outerRadius: Double, material: SCNMaterial,
                          hubMaterial: SCNMaterial, darkMaterial: SCNMaterial) -> SCNNode {
        let path = UIBezierPath()
        let root = outerRadius * (1 - 0.15)
        let stepsPerTooth = 4
        let total = teeth * stepsPerTooth
        for i in 0...total {
            let idx = i % total
            let phase = idx % stepsPerTooth
            let r = (phase == 1 || phase == 2) ? outerRadius : root
            let a = Double(idx) / Double(total) * 2 * Double.pi - Double.pi / 2
            let p = CGPoint(x: r * cos(a), y: r * sin(a))
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.close()
        let shape = SCNShape(path: path, extrusionDepth: 0.12)
        // 倒角即挤出形状的 bevel 表达：SCNShape 并无 bevelEnabled/bevelAmount 属性
        // （已核对 API），斜边由 chamferRadius + chamferMode(.both) 在前后两端生成，
        // 默认倒角轮廓为直线斜面。0.018 远小于挤出深度 0.12 的一半，不会自交。
        shape.chamferRadius = 0.018
        shape.chamferMode = .both
        shape.firstMaterial = material
        let mesh = SCNNode(geometry: shape)
        mesh.position = SCNVector3(0, 0, -0.06)
        let hub = SCNNode(geometry: SCNCylinder(radius: CGFloat(outerRadius * 0.18), height: 0.2))
        hub.geometry?.firstMaterial = hubMaterial
        hub.eulerAngles.x = Float.pi / 2
        // 转轴：向后伸出的短轴（深钢色）；轴毂正面中心螺丝：圆头 + 一字槽
        // （槽用恒定光照的深色小盒贴在螺丝头表面假造，不开真槽）。
        // 齿轮从"平面剪影"变成装配好的零件，靠的就是这三件。
        let axle = SCNNode(geometry: SCNCylinder(radius: CGFloat(outerRadius * 0.075), height: 0.55))
        axle.geometry?.firstMaterial = darkMaterial
        axle.eulerAngles.x = Float.pi / 2
        axle.position = SCNVector3(0, 0, -0.16)
        let screw = SCNNode(geometry: SCNCylinder(radius: CGFloat(outerRadius * 0.085), height: 0.05))
        screw.geometry?.firstMaterial = darkMaterial
        screw.eulerAngles.x = Float.pi / 2
        screw.position = SCNVector3(0, 0, 0.115)
        let slot = SCNNode(geometry: SCNBox(width: CGFloat(outerRadius * 0.15), height: 0.022,
                                            length: 0.014, chamferRadius: 0))
        slot.geometry?.firstMaterial = ringMaterial
        slot.position = SCNVector3(0, 0, 0.142)
        let group = SCNNode()
        group.addChildNode(mesh)
        group.addChildNode(hub)
        group.addChildNode(axle)
        group.addChildNode(screw)
        group.addChildNode(slot)
        return group
    }

    /// 编曲模式的列界环（常驻 ringGroup，仅编辑时可见）。
    private func buildColumnRings() {
        columnRingGeometry.firstMaterial = ringMaterial
        let colW = MechanismMath.drumLength / Double(Melody.pitchCount)
        for c in 0...Melody.pitchCount {
            let ring = SCNNode(geometry: columnRingGeometry)
            ring.eulerAngles.y = Float.pi / 2
            ring.position = SCNVector3(Float(-MechanismMath.drumLength / 2 + colW * Double(c)), 0, 0)
            ringGroup.addChildNode(ring)
        }
    }

    private func pbrMaterial(color: (Double, Double, Double), metalness: Double, roughness: Double) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = UIColor(red: CGFloat(color.0), green: CGFloat(color.1),
                                     blue: CGFloat(color.2), alpha: 1)
        m.metalness.contents = NSNumber(value: metalness)
        m.roughness.contents = NSNumber(value: roughness)
        return m
    }

    // MARK: 状态应用（updateUIView 每次调用；全部是赋值，无每帧分配）

    func update(melody: Melody, rotationDegrees: Double, triggeredPitches: Set<Int>,
                springCharge: Double, windingKeyAngle: Double,
                isEditing: Bool, onToggleNote: ((Int, Int) -> Void)?) {
        editing = isEditing
        toggleHandler = onToggleNote
        lastPlaybackRotation = rotationDegrees

        // 手动滚筒偏移：仅叠加于鼓体（齿轮/调速器仍由播放时钟驱动）；
        // 播放中逐帧衰减归零，让播放位置平滑接管，避免画面跳变。
        if playback?.isPlaying == true, manualDrumOffsetDegrees != 0 {
            manualDrumOffsetDegrees *= 0.75
            if abs(manualDrumOffsetDegrees) < 0.05 { manualDrumOffsetDegrees = 0 }
        }
        let effectiveRotation = rotationDegrees + manualDrumOffsetDegrees
        drumGroup.eulerAngles.x = Float(MechanismMath.drumRotationRadians(rotationDegrees: effectiveRotation))
        bigGearGroup.eulerAngles.z = Float(MechanismMath.sceneRotationZ(
            clockwiseDegrees: MechanismMath.bigGearDegrees(cylinderRotation: rotationDegrees)))
        smallGearGroup.eulerAngles.z = Float(MechanismMath.sceneRotationZ(
            clockwiseDegrees: MechanismMath.smallGearDegrees(cylinderRotation: rotationDegrees)))
        governorGroup.eulerAngles.z = Float(MechanismMath.sceneRotationZ(
            clockwiseDegrees: MechanismMath.governorDegrees(cylinderRotation: rotationDegrees)))
        keyGroup.eulerAngles.z = Float(MechanismMath.sceneRotationZ(clockwiseDegrees: windingKeyAngle))
        springHand.eulerAngles.z = Float(MechanismMath.sceneRotationZ(
            clockwiseDegrees: MechanismMath.springIndicatorDegrees(charge: springCharge)))

        if melody != lastMelody {
            rebuildPins(for: melody)
            if melody.stepCount != lastStepCount {
                rebuildStepRings(stepCount: melody.stepCount)
                lastStepCount = melody.stepCount
            }
            lastMelody = melody
        }
        ringGroup.isHidden = !isEditing

        if triggeredPitches != lastTriggeredPitches {
            for (i, material) in toothMaterials.enumerated() {
                material.emission.contents = triggeredPitches.contains(i)
                    ? UIColor(red: 0.45, green: 0.32, blue: 0.08, alpha: 1)
                    : UIColor.black
            }
            lastTriggeredPitches = triggeredPitches
        }

        // 音梳振动触发：只读消费 PlaybackEngine 的触发快照；旋律对不上（编曲预览别的草稿）时忽略。
        if let trigger = playback?.lastStepTrigger, trigger.time != lastTriggerTime {
            lastTriggerTime = trigger.time
            if playback?.melody.id == melody.id {
                strikeLock.lock()
                for pitch in trigger.pitchIndices { strikeTimes[pitch] = trigger.time }
                strikeLock.unlock()
            }
        }

        if windingKeyAngle != lastWindingAngle {
            lastWindingAngle = windingKeyAngle
            lastWindingChange = CACurrentMediaTime()
        }
        refreshPlayingState()
    }

    private func rebuildPins(for melody: Melody) {
        for child in pinGroup.childNodes { child.removeFromParentNode() }
        for event in melody.events {
            let node = SCNNode(geometry: pinGeometry)
            // 建场末尾的统一投影遍历跑不到运行时重建的音钉，这里单独打开投射
            // （钉影落在背板上是播放时的小小动态细节）；钉身太小，不必承接投影。
            node.castsShadow = true
            let pos = MechanismMath.pinLocalPosition(pitchIndex: event.pitchIndex,
                                                     step: event.step,
                                                     stepCount: melody.stepCount)
            node.position = SCNVector3(Float(pos.x), Float(pos.y), Float(pos.z))
            node.name = "pin:\(event.pitchIndex):\(event.step)"
            pinGroup.addChildNode(node)
        }
    }

    private func rebuildStepRings(stepCount: Int) {
        for child in ringGroup.childNodes { child.removeFromParentNode() }
        buildColumnRings()
        stepRingGeometry.firstMaterial = ringMaterial
        let radius = MechanismMath.drumRadius + 0.004
        // 刻度环密度恒定策略：64 步时每 4 步一环，避免鼓面被细环糊满（见 MechanismMath.stepRingStride）。
        let stride = MechanismMath.stepRingStride(stepCount: stepCount)
        for s in Swift.stride(from: 0, to: stepCount, by: stride) {
            let a = MechanismMath.pinAngleRadians(step: s, stepCount: stepCount)
            let ring = SCNNode(geometry: stepRingGeometry)
            ring.position = SCNVector3(0, Float(radius * sin(a)), Float(radius * cos(a)))
            ring.eulerAngles.x = Float(-a)
            ringGroup.addChildNode(ring)
        }
    }

    // MARK: 渲染循环管理（空闲不跑 60fps）

    /// 需要连续渲染的情形：播放中、梳齿还在振动、刚上过发条（0.5 秒内）。
    /// 其余情形只补渲染一帧让最新状态上屏，随即停下——不留常开的渲染循环。
    private func needsContinuousRendering() -> Bool {
        if playback?.isPlaying == true { return true }
        if CACurrentMediaTime() - lastWindingChange < 0.5 { return true }
        strikeLock.lock()
        let hasStrikes = !strikeTimes.isEmpty
        strikeLock.unlock()
        return hasStrikes
    }

    private func refreshPlayingState() {
        // 与 attach 一致：保持常开渲染，不再做空闲关停（原因见 attach 注释）。
        sceneView?.isPlaying = true
    }

    // MARK: 裸眼 3D 视差（陀螺仪倾斜 → 相机机位）

    /// 启动设备姿态采样：以收到的首个样本为中立参考姿态，之后只保存相对增量。
    /// 模拟器等无 deviceMotion 的环境直接跳过——增量恒为 0，机位静止，
    /// CI 截图与旧行为不受影响。无需任何权限（deviceMotion 不读麦克风/相机），
    /// 也不需要 NSMotionUsageDescription（那是健康/活动数据 CMSensorRecorder 的要求）。
    /// 幂等：motionRunning 把关，重复 attach 不会重复启动。
    private func startParallaxMotion() {
        guard !motionRunning, motionManager.isDeviceMotionAvailable else { return }
        motionRunning = true
        attitudeLock.lock()
        referencePitch = nil
        referenceRoll = nil
        targetPitchDelta = 0
        targetRollDelta = 0
        attitudeLock.unlock()
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: motionQueue) { [weak self] motion, _ in
            guard let self, let attitude = motion?.attitude else { return }
            // 回调只做最少的存值：映射与平滑都在渲染帧里算，不占用运动队列。
            self.attitudeLock.lock()
            if let referencePitch = self.referencePitch, let referenceRoll = self.referenceRoll {
                self.targetPitchDelta = Self.normalizedAngleDelta(attitude.pitch - referencePitch)
                self.targetRollDelta = Self.normalizedAngleDelta(attitude.roll - referenceRoll)
            } else {
                self.referencePitch = attitude.pitch
                self.referenceRoll = attitude.roll
            }
            self.attitudeLock.unlock()
        }
    }

    /// 停止采样并清空参考/增量：下次 attach 以当时的握持姿态重新标定中立位。
    private func stopParallaxMotion() {
        guard motionRunning else { return }
        motionRunning = false
        motionManager.stopDeviceMotionUpdates()
        attitudeLock.lock()
        referencePitch = nil
        referenceRoll = nil
        targetPitchDelta = 0
        targetRollDelta = 0
        attitudeLock.unlock()
    }

    /// 角度差归一化到 (−π, π]：姿态角在 ±π 处折返时，避免增量虚报近一整圈。
    private static func normalizedAngleDelta(_ delta: Double) -> Double {
        atan2(sin(delta), cos(delta))
    }

    /// 渲染帧调用：把机位（cameraRig）与注视目标平滑地推向当前视差目标。
    /// 一阶低通 alpha = 1 − exp(−dt/τ)：dt 取相邻渲染时间戳之差并钳制到 0.1s，
    /// 帧率无关，且从后台切回时不会一帧跳到位。目标恒为 0（无姿态数据）时
    /// rig 停在原点、目标停在基准位 (0, −0.2, 0)，与视差功能加入前完全一致。
    private func applyParallax(atTime time: TimeInterval) {
        attitudeLock.lock()
        let pitchDelta = targetPitchDelta
        let rollDelta = targetRollDelta
        attitudeLock.unlock()

        let target = MechanismMath.parallaxOffset(pitchDelta: pitchDelta, rollDelta: rollDelta)
        let dt: Double
        if let lastRenderTime {
            dt = min(max(time - lastRenderTime, 0), 0.1)
        } else {
            dt = 1.0 / 60.0
        }
        lastRenderTime = time
        let alpha = 1 - exp(-dt / MechanismMath.parallaxSmoothingTau)
        smoothedParallaxX += (target.x - smoothedParallaxX) * alpha
        smoothedParallaxY += (target.y - smoothedParallaxY) * alpha

        cameraRig.position = SCNVector3(Float(smoothedParallaxX), Float(smoothedParallaxY), 0)
        let shift = MechanismMath.parallaxTargetShift(offset: (x: smoothedParallaxX, y: smoothedParallaxY))
        lookTargetNode.position = SCNVector3(Float(shift.x), Float(-0.2 + shift.y), 0)
    }

    // MARK: 渲染帧回调（梳齿振动是唯一需要逐帧更新的量）

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        applyParallax(atTime: time)
        strikeLock.lock()
        let strikes = strikeTimes
        strikeLock.unlock()
        for (pitch, start) in strikes {
            guard teeth.indices.contains(pitch) else { continue }
            let elapsed = time - start
            if elapsed > MechanismMath.toothVibrationDuration {
                teeth[pitch].eulerAngles.x = toothBaseAngles[pitch]
                strikeLock.lock()
                strikeTimes[pitch] = nil
                strikeLock.unlock()
            } else {
                teeth[pitch].eulerAngles.x = toothBaseAngles[pitch]
                    + Float(MechanismMath.toothOscillation(elapsed: elapsed))
            }
        }
        // 空闲关停已取消：渲染常开（原因见 attach 注释），此处只更新梳齿振动。
    }

    // MARK: 点按编辑（与 CylinderView 同语义：命中即 toggle）

    /// 命中音钉节点 → 直接用该钉的 (pitch, step)；
    /// 命中鼓身 → 把世界命中点转回滚筒子坐标，用 MechanismMath 反解最近格。
    /// 两条路径同为落位公式的逆运算，与编曲网格、CylinderView 的点按结果一致。
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard editing, let toggleHandler, let view = sceneView, gesture.state == .ended else { return }
        // 拖动收尾的抬指不是点按：0.3 秒时间窗内忽略，避免滚完筒顺手拆掉一颗钉。
        if CACurrentMediaTime() - lastDragEndTime < 0.3 { return }
        let point = gesture.location(in: view)
        let hits = view.hitTest(point, options: nil)
        for hit in hits {
            var node: SCNNode? = hit.node
            while let current = node {
                if let name = current.name, name.hasPrefix("pin:") {
                    let parts = name.split(separator: ":")
                    if parts.count == 3, let pitch = Int(parts[1]), let step = Int(parts[2]) {
                        toggleHandler(pitch, step)
                        return
                    }
                }
                node = current.parent
            }
            if hit.node === drumMesh {
                let local = drumGroup.convertPosition(hit.worldCoordinates, from: view.scene?.rootNode)
                if let cell = MechanismMath.pitchAndStep(localX: Double(local.x),
                                                         localY: Double(local.y),
                                                         localZ: Double(local.z),
                                                         stepCount: lastMelody?.stepCount ?? 16) {
                    toggleHandler(cell.pitch, cell.step)
                    return
                }
            }
        }
    }

    // MARK: 拖动滚筒（编曲模式，Phase 3）

    /// 纵向拖动 = 滚动滚筒：鼓面跟随手指同向滚动（手指下滑，鼓面正前方随之下行，
    /// 与播放时音钉自上而下抵达拨弦线的方向一致，故偏移与播放旋转同号叠加）。
    /// 播放中不接管（播放时钟独占鼓体，偏移由 update 逐帧衰减归零）。
    /// 灵敏度 0.5°/pt：约 180pt 的滑动滚过四分之一圈，定位单步（64 步时 5.6°）足够细。
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard editing, let view = sceneView, playback?.isPlaying != true else { return }
        let translation = gesture.translation(in: view)
        switch gesture.state {
        case .began:
            dragStartOffset = manualDrumOffsetDegrees
            dragMoved = false
        case .changed:
            if abs(translation.y) > 8 { dragMoved = true }
            if dragMoved {
                manualDrumOffsetDegrees = dragStartOffset + Double(translation.y) * 0.5
                // 直接落到鼓体不等下一次 update：拖动跟手优先；下一次 update 会以同值重写。
                drumGroup.eulerAngles.x = Float(MechanismMath.drumRotationRadians(
                    rotationDegrees: lastPlaybackRotation + manualDrumOffsetDegrees))
            }
        case .ended, .cancelled:
            if dragMoved { lastDragEndTime = CACurrentMediaTime() }
            dragMoved = false
        default:
            break
        }
    }
}
