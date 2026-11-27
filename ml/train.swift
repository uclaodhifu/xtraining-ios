// 用苹果 Create ML 训练器械识别模型（在苹果自带的看图能力上再学一层，模型很小）
import CreateML
import Foundation
let fm = FileManager.default
let train = URL(fileURLWithPath: "ml/split/train"), test = URL(fileURLWithPath: "ml/split/test")
let params = MLImageClassifier.ModelParameters(featureExtractor: .scenePrint(revision: 2), validation: .split(strategy: .automatic), maxIterations: 60, augmentation: [.crop, .exposure, .flip, .rotation, .blur])
let model = try MLImageClassifier(trainingData: .labeledDirectories(at: train), parameters: params)
let ev = model.evaluation(on: .labeledDirectories(at: test))
var report = "训练准确率 \(String(format: "%.1f", (1 - model.trainingMetrics.classificationError) * 100))%\n"
report += "验证准确率 \(String(format: "%.1f", (1 - model.validationMetrics.classificationError) * 100))%\n"
report += "测试准确率（没见过的照片） \(String(format: "%.1f", (1 - ev.classificationError) * 100))%\n\n"
report += "每类准确/召回：\n\(ev.precisionRecall)\n\n混淆表：\n\(ev.confusion)\n"
try fm.createDirectory(atPath: "ml/out", withIntermediateDirectories: true)
try report.write(toFile: "ml/out/report.txt", atomically: true, encoding: .utf8)
try model.write(to: URL(fileURLWithPath: "ml/out/MachineClassifier.mlmodel"), metadata: MLModelMetadata(author: "X Training", shortDescription: "健身器械类型识别", version: "1"))
print(report)
