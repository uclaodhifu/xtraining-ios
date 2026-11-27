import Foundation
import CoreGraphics

// 阻力曲线分析引擎的数据模型（纯 Swift，不依赖界面）。
// 坐标约定：引擎里的点都是“重力校准后的归一化坐标”，x、y 都在 0...1，y 轴朝上（和 Vision 一致），
// 所以 y 越大 = 位置越高。

/// 器械的四种力学模式
enum EquipmentModality: String, Codable, CaseIterable, Identifiable, Hashable {
    case plateLoadedLever   // 挂片杠杆：点支点 P + 配重点 W
    case cablePulley        // 绳索滑轮：姿态认关节 J、手腕 H，点滑轮 C
    case freeWeight         // 自由重量：不用点，按动作选关节 J 和手腕 W
    case selectorizedCam    // 插片凸轮：识别器械型号，查本地曲线库

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plateLoadedLever: return "挂片杠杆"
        case .cablePulley: return "绳索滑轮"
        case .freeWeight: return "自由重量"
        case .selectorizedCam: return "插片凸轮"
        }
    }

    var subtitle: String {
        switch self {
        case .plateLoadedLever: return "点一下转轴和挂片，按力臂算"
        case .cablePulley: return "点一下滑轮，按绳子和手臂的夹角算"
        case .freeWeight: return "哑铃、杠铃，不用点，认关节自动算"
        case .selectorizedCam: return "插销配重片，认出器械查曲线"
        }
    }

    /// 第一帧上需要用户点的锚点（按顺序）
    var requiredAnchors: [AnchorRole] {
        switch self {
        case .plateLoadedLever: return [.pivot, .weight]
        case .cablePulley: return [.pulley]
        case .freeWeight, .selectorizedCam: return []
        }
    }
}

/// 第一帧上用户点的锚点
enum AnchorRole: String, Codable, CaseIterable, Identifiable, Hashable {
    case pivot      // 支点（转轴）
    case weight     // 配重点（挂片）
    case pulley     // 滑轮

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pivot: return "支点"
        case .weight: return "配重点"
        case .pulley: return "滑轮"
        }
    }

    var hint: String {
        switch self {
        case .pivot: return "点一下器械转动的轴"
        case .weight: return "点一下挂杠铃片的位置"
        case .pulley: return "点一下绳子出来的滑轮"
        }
    }

    /// 支点、滑轮是固定的，不用逐帧追踪
    var isFixed: Bool { self != .weight }
}

/// 人体关节（姿态识别取左右两侧里置信度高的一侧）
enum BodyJoint: String, Codable, CaseIterable, Identifiable, Hashable {
    case shoulder, elbow, wrist, hip, knee, ankle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shoulder: return "肩"
        case .elbow: return "肘"
        case .wrist: return "手腕"
        case .hip: return "髋"
        case .knee: return "膝"
        case .ankle: return "脚踝"
        }
    }
}

/// 自由重量动作类型：决定用哪个关节当转动中心、哪个点当重物
enum FreeWeightExercise: String, Codable, CaseIterable, Identifiable, Hashable {
    case bicepsCurl         // 弯举：肘 + 手腕
    case tricepsExtension   // 颈后臂屈伸：肘 + 手腕
    case lateralRaise       // 侧平举：肩 + 手腕
    case frontRaise         // 前平举：肩 + 手腕
    case dumbbellFly        // 哑铃飞鸟：肩 + 手腕
    case pullover           // 仰卧上拉：肩 + 手腕

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bicepsCurl: return "弯举"
        case .tricepsExtension: return "颈后臂屈伸"
        case .lateralRaise: return "侧平举"
        case .frontRaise: return "前平举"
        case .dumbbellFly: return "哑铃飞鸟"
        case .pullover: return "仰卧上拉"
        }
    }

    var pivotJoint: BodyJoint {
        switch self {
        case .bicepsCurl, .tricepsExtension: return .elbow
        case .lateralRaise, .frontRaise, .dumbbellFly, .pullover: return .shoulder
        }
    }

    var weightJoint: BodyJoint { .wrist }

    var muscleProfile: MuscleProfileKind {
        switch self {
        case .bicepsCurl: return .bicepsCurl
        case .tricepsExtension: return .tricepsExtension
        case .lateralRaise, .frontRaise: return .shoulderRaise
        case .dumbbellFly, .pullover: return .chestFly
        }
    }
}

/// 阻力曲线形态
enum CurvePattern: String, Codable, CaseIterable, Identifiable, Hashable {
    case descending     // 递减：拉长位最重
    case ascending      // 递增：缩短位最重
    case bellShaped     // 钟形：中段最重
    case flat           // 恒定
    case complex        // 不规则

    var id: String { rawValue }

    var title: String {
        switch self {
        case .descending: return "下降阻力"
        case .ascending: return "上升阻力"
        case .bellShaped: return "钟形阻力"
        case .flat: return "平稳阻力"
        case .complex: return "不规则阻力"
        }
    }

    var shortText: String {
        switch self {
        case .descending: return "越往后越轻 · 拉长位最吃力"
        case .ascending: return "越往后越重 · 缩短位最吃力"
        case .bellShaped: return "中间最重 · 两头轻"
        case .flat: return "从头到尾差不多重"
        case .complex: return "忽轻忽重，没有固定规律"
        }
    }
}

/// 曲线上的一个点（ROM 0% = 拉长位起点，100% = 缩短位终点）
struct ResistancePoint: Codable, Identifiable, Hashable {
    var romPercent: Double          // 0...100
    var resistancePct: Double       // 0...100，最大值 = 100
    var muscleForcePct: Double?     // 目标肌群在这个位置的发力能力，0...100

    var id: Double { romPercent }
}

/// 一次分析的结果
struct ResistanceAnalysisResult: Codable, Identifiable, Hashable {
    var id = UUID()
    var modality: EquipmentModality
    var curvePattern: CurvePattern
    var peakRomPercent: Int
    var dropoffPercent: Double          // 最重到最轻掉了多少（%）
    var points: [ResistancePoint]       // 21 个点：0, 5, ..., 100
    var matchedMachineId: String?
    var camWarning: String?
    var coachingSummary: String

    // 附加信息（可选，不影响上面的核心字段）
    var lengthenedMatch: Double?        // 拉长位匹配度 0...100
    var peakWarning: String?            // 顶峰位发虚 / 过载提示
    var trackingStability: Double?      // 追踪稳定率 0...1
    var reps: Int?
    var createdAt = Date()
}

/// 目标肌群的发力曲线类型（长度-张力关系，0% = 拉长位）
enum MuscleProfileKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case backRow            // 背部划船/下拉：拉长位强，越往后越弱
    case chestPress         // 推胸/推肩：中段偏前最强
    case chestFly           // 夹胸/飞鸟：拉长位强
    case bicepsCurl         // 弯举：中段最强（钟形）
    case tricepsExtension   // 臂屈伸：拉长位到中段强
    case shoulderRaise      // 侧平举：中段偏前强，顶端弱
    case quadExtension      // 腿屈伸：中段偏前最强
    case hamstringCurl      // 腿弯举：拉长位强
    case squatPress         // 深蹲/腿举：拉长位弱、越伸直越强

    var id: String { rawValue }

    var title: String {
        switch self {
        case .backRow: return "背阔肌 / 中背"
        case .chestPress: return "胸大肌（推）"
        case .chestFly: return "胸大肌（夹）"
        case .bicepsCurl: return "肱二头肌"
        case .tricepsExtension: return "肱三头肌"
        case .shoulderRaise: return "三角肌中束"
        case .quadExtension: return "股四头肌"
        case .hamstringCurl: return "腘绳肌"
        case .squatPress: return "股四头肌 / 臀"
        }
    }
}

/// 本地器械曲线库里的一台器械（MachinePhysicsProfiles.json）
struct MachineProfile: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var aliases: [String]               // 识别模型的类别名、常见叫法
    var modality: EquipmentModality
    var muscleProfile: MuscleProfileKind
    var defaultCurve: [Double]          // 21 点，器械阻力
    var muscleCurve: [Double]           // 21 点，目标肌群发力
    var advice: String
}

/// 视频追踪后的一帧（重力校准后的归一化坐标，y 朝上）
struct TrackedFrame: Equatable {
    var time: Double
    var weights: [CGPoint?]  // 每个挂片位置（多挂片器械可以有 1~3 个），追丢的帧为 nil
    var hand: CGPoint?       // 手腕（自由重量时也当重物）
    var joint: CGPoint?      // 转动中心关节（绳索、自由重量）

    init(time: Double, weights: [CGPoint?] = [], hand: CGPoint? = nil, joint: CGPoint? = nil) {
        self.time = time
        self.weights = weights
        self.hand = hand
        self.joint = joint
    }

    /// 单挂片的便捷写法
    init(time: Double, weight: CGPoint?, hand: CGPoint? = nil, joint: CGPoint? = nil) {
        self.init(time: time, weights: [weight], hand: hand, joint: joint)
    }
}

/// 交给物理引擎的一次分析输入
struct PhysicsInput {
    var modality: EquipmentModality
    var frames: [TrackedFrame]
    var pivot: CGPoint?             // 挂片杠杆：支点（固定）
    var weightLoads: [Double]       // 每个挂片挂的重量（kg），空 = 都一样重
    var pulley: CGPoint?            // 绳索：滑轮（固定）
    var muscleProfile: MuscleProfileKind?
    var trackingStability: Double?

    init(modality: EquipmentModality, frames: [TrackedFrame], pivot: CGPoint? = nil, weightLoads: [Double] = [],
         pulley: CGPoint? = nil, muscleProfile: MuscleProfileKind? = nil, trackingStability: Double? = nil) {
        self.modality = modality
        self.frames = frames
        self.pivot = pivot
        self.weightLoads = weightLoads
        self.pulley = pulley
        self.muscleProfile = muscleProfile
        self.trackingStability = trackingStability
    }
}

enum ResistanceAnalysisError: Error, Equatable, LocalizedError {
    case notEnoughFrames
    case tooLittleMotion
    case missingAnchor(AnchorRole)

    var errorDescription: String? {
        switch self {
        case .notEnoughFrames: return "能用的画面太少，换个角度再录一次，让人和器械都在画面里"
        case .tooLittleMotion: return "几乎没看到动作，至少录完整的一次"
        case .missingAnchor(let r): return "还没点\(r.title)"
        }
    }
}
