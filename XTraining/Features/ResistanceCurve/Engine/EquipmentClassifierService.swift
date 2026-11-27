import Foundation
import CoreGraphics
import CoreML
import ImageIO
import Vision

/// 识别出的一个候选
struct EquipmentPrediction: Equatable, Identifiable {
    var label: String           // 模型的类别名（machine_id 或中文器械名）
    var confidence: Double      // 0...1
    var profile: MachineProfile?

    var id: String { label }
}

/// 识别结论：把握够就直接用，不够就让用户选，没有模型就走手动模式
enum EquipmentRecognitionOutcome: Equatable {
    case confident(MachineProfile, confidence: Double)
    case needsManualPick(candidates: [EquipmentPrediction])
    case unavailable            // App 里没带模型：让用户手动选器械，或改用挂片杠杆 / 绳索模式
}

protocol EquipmentClassifying {
    var isAvailable: Bool { get }
    func classify(_ image: CGImage, orientation: CGImagePropertyOrientation) async -> [EquipmentPrediction]
}

extension EquipmentClassifying {
    /// 识别 + 按 0.75 的把握线给出结论
    func recognize(_ image: CGImage, orientation: CGImagePropertyOrientation = .up) async -> EquipmentRecognitionOutcome {
        guard isAvailable else { return .unavailable }
        let preds = await classify(image, orientation: orientation)
        guard let top = preds.first else { return .needsManualPick(candidates: []) }
        if let p = top.profile, top.confidence >= EquipmentRecognition.confidenceThreshold {
            return .confident(p, confidence: top.confidence)
        }
        return .needsManualPick(candidates: Array(preds.prefix(3)))
    }
}

/// Core ML 器械识别。模型放进 App 包里（EquipmentClassifier 或 MachineClassifier，.mlmodel 会被编译成 .mlmodelc）。
/// 没有模型也能编译、能运行：isAvailable = false，界面退回手动选择。
final class EquipmentClassifierService: EquipmentClassifying {
    static let modelNames = ["EquipmentClassifier", "MachineClassifier"]

    private let library: MachineProfileLibrary
    private let vnModel: VNCoreMLModel?

    init(library: MachineProfileLibrary = .load(), bundle: Bundle = .main) {
        self.library = library
        self.vnModel = Self.loadModel(bundle: bundle)
    }

    var isAvailable: Bool { vnModel != nil }

    private static func loadModel(bundle: Bundle) -> VNCoreMLModel? {
        for name in modelNames {
            guard let url = bundle.url(forResource: name, withExtension: "mlmodelc") else { continue }
            let config = MLModelConfiguration()
            config.computeUnits = .all
            if let ml = try? MLModel(contentsOf: url, configuration: config), let vn = try? VNCoreMLModel(for: ml) {
                return vn
            }
        }
        return nil
    }

    func classify(_ image: CGImage, orientation: CGImagePropertyOrientation) async -> [EquipmentPrediction] {
        guard let model = vnModel else { return [] }
        let library = self.library
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let req = VNCoreMLRequest(model: model)
                req.imageCropAndScaleOption = .centerCrop
                do {
                    try VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:]).perform([req])
                } catch {
                    cont.resume(returning: [])
                    return
                }
                let obs = (req.results as? [VNClassificationObservation]) ?? []
                let preds = obs.prefix(5).map {
                    EquipmentPrediction(label: $0.identifier, confidence: Double($0.confidence), profile: library.match($0.identifier))
                }
                cont.resume(returning: Array(preds))
            }
        }
    }
}

/// 没有模型时用的占位识别器（也方便测试）
struct UnavailableEquipmentClassifier: EquipmentClassifying {
    var isAvailable: Bool { false }
    func classify(_ image: CGImage, orientation: CGImagePropertyOrientation) async -> [EquipmentPrediction] { [] }
}
