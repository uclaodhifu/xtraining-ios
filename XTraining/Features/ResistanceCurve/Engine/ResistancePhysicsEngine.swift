import Foundation
import CoreGraphics

/// 确定性物理引擎：把追踪到的点变成 21 点阻力曲线，再分类、和肌群发力曲线对比。
/// 纯 Swift，不依赖界面和 Vision，方便单元测试。
enum ResistancePhysicsEngine {
    static let nodeCount = 21
    static let romNodes: [Double] = (0..<21).map { Double($0) * 5 }
    static let smoothingWindow = 5

    // MARK: - 四种模式的力学公式（返回 0...1 的力臂系数）

    /// 挂片杠杆：R = |Wx − Px| / ‖W − P‖（杠杆和水平线夹角的余弦）
    static func leverFactor(pivot p: CGPoint, weight w: CGPoint) -> Double? {
        let d = distance(p, w)
        guard d > 1e-6 else { return nil }
        return abs(Double(w.x - p.x)) / d
    }

    /// 多挂片杠杆：总力矩 = |Σ mᵢ · rᵢ · (Wᵢx − Px) / ‖Wᵢ − P‖|
    /// 同一根杠杆上的挂片可能在支点两侧，力矩有正负，所以先带符号相加再取绝对值。
    static func leverTorque(pivot p: CGPoint, weights: [CGPoint?], loads: [Double], radii: [Double]) -> Double? {
        var sum = 0.0
        var used = 0
        for (i, w) in weights.enumerated() {
            guard let w else { continue }
            let d = distance(p, w)
            guard d > 1e-6 else { continue }
            let m = i < loads.count ? loads[i] : 1
            let r = i < radii.count ? radii[i] : d
            sum += m * r * Double(w.x - p.x) / d
            used += 1
        }
        return used == 0 ? nil : abs(sum)
    }

    /// 绳索滑轮：R = |JH × HC| / (‖JH‖ · ‖HC‖)（肢体和绳子夹角的正弦）
    static func cableFactor(joint j: CGPoint, hand h: CGPoint, pulley c: CGPoint) -> Double? {
        let jh = CGVector(dx: h.x - j.x, dy: h.y - j.y)
        let hc = CGVector(dx: c.x - h.x, dy: c.y - h.y)
        let a = hypot(Double(jh.dx), Double(jh.dy)), b = hypot(Double(hc.dx), Double(hc.dy))
        guard a > 1e-6, b > 1e-6 else { return nil }
        return abs(Double(jh.dx * hc.dy - jh.dy * hc.dx)) / (a * b)
    }

    /// 自由重量：R = |Wx − Jx| / ‖W − J‖（重力方向竖直向下，力臂 = 水平距离）
    static func freeWeightFactor(joint j: CGPoint, weight w: CGPoint) -> Double? {
        leverFactor(pivot: j, weight: w)
    }

    // MARK: - 主流程

    /// 视频追踪结果 → 分析结果（挂片杠杆 / 绳索 / 自由重量）
    static func analyze(_ input: PhysicsInput) throws -> ResistanceAnalysisResult {
        let series = try signals(for: input)
        guard series.resistance.count >= 8 else { throw ResistanceAnalysisError.notEnoughFrames }

        let r = movingAverage(series.resistance, window: smoothingWindow)
        let s = movingAverage(series.progress, window: smoothingWindow)
        guard let lo = s.min(), let hi = s.max(), hi - lo > 0.02 else { throw ResistanceAnalysisError.tooLittleMotion }

        // ROM：进度信号最小 = 0%（拉长位），最大 = 100%（缩短位）
        let rom = s.map { ($0 - lo) / (hi - lo) * 100 }
        let nodes = normalize(resample(rom: rom, values: r))
        let reps = countStrokes(rom)
        return buildResult(modality: input.modality, nodes: nodes, muscle: input.muscleProfile,
                           matchedMachineId: nil, camWarning: nil,
                           stability: input.trackingStability, reps: reps)
    }

    /// 插片凸轮：直接用本地曲线库里这台器械的曲线
    static func analyze(profile: MachineProfile, confidence: Double? = nil) -> ResistanceAnalysisResult {
        var warning = "插片器械按型号的典型曲线给，不同品牌凸轮形状会有差别"
        if let c = confidence, c < EquipmentRecognition.confidenceThreshold {
            warning = "认得不太准（\(Int(c * 100))%），请确认器械型号。" + warning
        }
        var result = buildResult(modality: .selectorizedCam, nodes: normalize(fit21(profile.defaultCurve)),
                                 muscle: nil, muscleCurveOverride: fit21(profile.muscleCurve),
                                 matchedMachineId: profile.id, camWarning: warning, stability: nil, reps: nil)
        result.coachingSummary += " " + profile.advice
        return result
    }

    // MARK: - 每帧原始信号

    struct Signals {
        var resistance: [Double]
        var progress: [Double]
    }

    static func signals(for input: PhysicsInput) throws -> Signals {
        var res: [Double] = [], prog: [Double] = []
        switch input.modality {
        case .plateLoadedLever:
            guard let p = input.pivot else { throw ResistanceAnalysisError.missingAnchor(.pivot) }
            let count = input.frames.map(\.weights.count).max() ?? 0
            guard count > 0 else { throw ResistanceAnalysisError.missingAnchor(.weight) }
            let loads = (0..<count).map { i in i < input.weightLoads.count && input.weightLoads[i] > 0 ? input.weightLoads[i] : 1 }
            // 每个挂片到支点的半径取中位数，压掉追踪抖动
            let radii = (0..<count).map { i -> Double in
                median(input.frames.compactMap { f in i < f.weights.count ? f.weights[i].map { distance(p, $0) } : nil }) ?? 0
            }
            for f in input.frames {
                let present = f.weights.enumerated().compactMap { i, w in w.map { (i, $0) } }
                guard !present.isEmpty else { continue }
                let value: Double?
                if count == 1, let w = present.first?.1 {
                    value = leverFactor(pivot: p, weight: w)
                } else {
                    value = leverTorque(pivot: p, weights: f.weights, loads: loads, radii: radii)
                }
                guard let v = value else { continue }
                // 进度 = 挂片的加权平均高度（片子越高越接近缩短位）
                let m = present.reduce(0.0) { $0 + loads[$1.0] }
                let h = present.reduce(0.0) { $0 + loads[$1.0] * Double($1.1.y) } / m
                res.append(v); prog.append(h)
            }
        case .cablePulley:
            guard let c = input.pulley else { throw ResistanceAnalysisError.missingAnchor(.pulley) }
            for f in input.frames {
                guard let j = f.joint, let h = f.hand, let v = cableFactor(joint: j, hand: h, pulley: c) else { continue }
                // 进度 = 手腕到滑轮的距离（越远越接近缩短位）
                res.append(v); prog.append(distance(h, c))
            }
        case .freeWeight:
            for f in input.frames {
                guard let j = f.joint, let w = f.hand ?? f.weights.compactMap({ $0 }).first,
                      let v = freeWeightFactor(joint: j, weight: w) else { continue }
                res.append(v); prog.append(Double(w.y))
            }
        case .selectorizedCam:
            throw ResistanceAnalysisError.notEnoughFrames
        }
        return Signals(resistance: res, progress: prog)
    }

    // MARK: - 信号处理

    /// 居中移动平均，两端窗口自动缩小
    static func movingAverage(_ v: [Double], window: Int) -> [Double] {
        guard window > 1, v.count > 2 else { return v }
        let half = window / 2
        return v.indices.map { i in
            let a = max(0, i - half), b = min(v.count - 1, i + half)
            return v[a...b].reduce(0, +) / Double(b - a + 1)
        }
    }

    /// 按 ROM 把所有帧分到 21 个节点（每个节点 ±2.5%），取中位数；空节点线性插值
    static func resample(rom: [Double], values: [Double]) -> [Double] {
        var buckets = Array(repeating: [Double](), count: nodeCount)
        for (x, v) in zip(rom, values) {
            let k = min(nodeCount - 1, max(0, Int((x / 5).rounded())))
            buckets[k].append(v)
        }
        let raw: [Double?] = buckets.map { median($0) }
        return fillGaps(raw)
    }

    static func fillGaps(_ raw: [Double?]) -> [Double] {
        let known = raw.enumerated().compactMap { i, v in v.map { (i, $0) } }
        guard let first = known.first, let last = known.last else { return Array(repeating: 0, count: raw.count) }
        return raw.indices.map { i in
            if let v = raw[i] { return v }
            if i < first.0 { return first.1 }
            if i > last.0 { return last.1 }
            let l = known.last { $0.0 < i }!, r = known.first { $0.0 > i }!
            let t = Double(i - l.0) / Double(r.0 - l.0)
            return l.1 + (r.1 - l.1) * t
        }
    }

    /// 最大值归一到 100
    static func normalize(_ v: [Double]) -> [Double] {
        guard let m = v.max(), m > 1e-9 else { return v.map { _ in 0 } }
        return v.map { max(0, $0 / m * 100) }
    }

    /// 任意长度曲线线性插值成 21 点
    static func fit21(_ v: [Double]) -> [Double] {
        guard v.count != nodeCount else { return v }
        guard v.count > 1 else { return Array(repeating: v.first ?? 0, count: nodeCount) }
        return (0..<nodeCount).map { k in
            let x = Double(k) / Double(nodeCount - 1) * Double(v.count - 1)
            let i = min(v.count - 2, Int(x))
            return v[i] + (v[i + 1] - v[i]) * (x - Double(i))
        }
    }

    /// 数完整行程：ROM 在 25% 以下和 75% 以上之间来回一次算一次
    static func countStrokes(_ rom: [Double]) -> Int {
        var state = 0, ups = 0
        for x in rom {
            if x <= 25 {
                state = -1
            } else if x >= 75 {
                if state == -1 { ups += 1 }
                state = 1
            }
        }
        return max(ups, rom.isEmpty ? 0 : 1)
    }

    // MARK: - 形态分类

    struct Classification: Equatable {
        var pattern: CurvePattern
        var peakRomPercent: Int
        var dropoffPercent: Double
    }

    static func classify(_ input: [Double]) -> Classification {
        let n = normalize(fit21(input))
        let peakIdx = n.indices.max { n[$0] < n[$1] } ?? 0
        let peakRom = peakIdx * 5
        let dropoff = 100 - (n.min() ?? 100)
        if dropoff < 8 { return Classification(pattern: .flat, peakRomPercent: peakRom, dropoffPercent: dropoff) }

        let start = mean(n[0...4]), end = mean(n[16...20]), mid = mean(n[7...13])
        let pattern: CurvePattern
        if peakRom <= 25 && start > end + 6 {
            pattern = .descending
        } else if peakRom >= 75 && end > start + 6 {
            pattern = .ascending
        } else if peakRom >= 25 && peakRom <= 75 && mid > max(start, end) + 4 {
            pattern = .bellShaped
        } else {
            pattern = .complex
        }
        return Classification(pattern: pattern, peakRomPercent: peakRom, dropoffPercent: dropoff)
    }

    // MARK: - 肌群发力曲线（长度-张力关系，0% = 拉长位）

    static func muscleCurve(_ kind: MuscleProfileKind) -> [Double] {
        func gauss(_ base: Double, _ center: Double, _ width: Double) -> (Double) -> Double {
            { x in base + (100 - base) * exp(-pow((x - center) / width, 2)) }
        }
        let f: (Double) -> Double
        switch kind {
        case .backRow: f = { 100 - 45 * $0 }
        case .chestPress: f = gauss(60, 0.35, 0.35)
        case .chestFly: f = { 100 - 50 * $0 }
        case .bicepsCurl: f = gauss(55, 0.5, 0.3)
        case .tricepsExtension: f = gauss(60, 0.3, 0.35)
        case .shoulderRaise: f = gauss(50, 0.35, 0.35)
        case .quadExtension: f = gauss(55, 0.4, 0.35)
        case .hamstringCurl: f = { 100 - 50 * $0 }
        case .squatPress: f = { 55 + 45 * $0 }
        }
        return normalize((0..<nodeCount).map { f(Double($0) / Double(nodeCount - 1)) })
    }

    struct MuscleComparison: Equatable {
        var lengthenedMatch: Double     // 0...100
        var peakWarning: String?
    }

    /// 拉长位（0~30%）匹配度 + 顶峰位（75~100%）发虚 / 过载
    static func compare(resistance r: [Double], muscle m: [Double]) -> MuscleComparison {
        let gap = (0...6).map { abs(r[$0] - m[$0]) }
        let match = min(100, max(0, 100 - mean(gap[...])))
        let peakDiff = mean(r[15...20]) - mean(m[15...20])
        var warning: String?
        if peakDiff > 15 {
            warning = "顶峰位过载：动作快做完时阻力比肌肉能出的力大，容易做不完整或借力"
        } else if peakDiff < -20 {
            warning = "顶峰位发虚：动作快做完时几乎没阻力，顶峰收缩练不到"
        }
        return MuscleComparison(lengthenedMatch: match, peakWarning: warning)
    }

    // MARK: - 组装结果

    static func buildResult(modality: EquipmentModality, nodes: [Double], muscle: MuscleProfileKind?,
                            muscleCurveOverride: [Double]? = nil, matchedMachineId: String?,
                            camWarning: String?, stability: Double?, reps: Int?) -> ResistanceAnalysisResult {
        let c = classify(nodes)
        let m: [Double]? = muscleCurveOverride.map { normalize($0) } ?? muscle.map(muscleCurve)
        let points = (0..<nodeCount).map { k in
            ResistancePoint(romPercent: romNodes[k], resistancePct: nodes[k], muscleForcePct: m?[k])
        }
        let cmp = m.map { compare(resistance: nodes, muscle: $0) }
        return ResistanceAnalysisResult(
            modality: modality, curvePattern: c.pattern, peakRomPercent: c.peakRomPercent,
            dropoffPercent: c.dropoffPercent, points: points, matchedMachineId: matchedMachineId,
            camWarning: camWarning,
            coachingSummary: summary(c, comparison: cmp, stability: stability),
            lengthenedMatch: cmp?.lengthenedMatch, peakWarning: cmp?.peakWarning,
            trackingStability: stability, reps: reps)
    }

    static func summary(_ c: Classification, comparison: MuscleComparison?, stability: Double?) -> String {
        var parts: [String] = []
        let drop = Int(c.dropoffPercent.rounded())
        switch c.pattern {
        case .descending:
            parts.append("拉长位最重，越往后越轻，最轻的地方比最重时轻了 \(drop)%。拉长位负荷大，对增肌友好。")
        case .ascending:
            parts.append("越往后越重，在 \(c.peakRomPercent)% 的位置最吃力。拉长位偏轻，可以配一个拉长位重的动作。")
        case .bellShaped:
            parts.append("中段（\(c.peakRomPercent)% 左右）最重，两头轻，和大多数肌肉的发力特点接近。")
        case .flat:
            parts.append("从头到尾阻力差不多（起伏不到 8%）。")
        case .complex:
            parts.append("阻力忽轻忽重，在 \(c.peakRomPercent)% 的位置最吃力。可以换个角度再录一次确认。")
        }
        if let cmp = comparison {
            let s = Int(cmp.lengthenedMatch.rounded())
            parts.append(s >= 80 ? "拉长位和肌肉发力很匹配（\(s) 分）。" : s >= 60 ? "拉长位匹配度一般（\(s) 分）。" : "拉长位不太匹配（\(s) 分），肌肉最能出力的地方阻力不够。")
            if let w = cmp.peakWarning { parts.append(w + "。") }
        }
        if let st = stability, st < 0.7 {
            parts.append("这次追踪只有 \(Int(st * 100))% 的画面看得清，结果仅供参考。")
        }
        return parts.joined(separator: " ")
    }

    // MARK: - 小工具

    static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        hypot(Double(a.x - b.x), Double(a.y - b.y))
    }

    static func mean<C: Collection>(_ v: C) -> Double where C.Element == Double {
        v.isEmpty ? 0 : v.reduce(0, +) / Double(v.count)
    }

    static func median(_ v: [Double]) -> Double? {
        guard !v.isEmpty else { return nil }
        let s = v.sorted(), n = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }
}

/// 器械识别的共用常量（识别服务在 Phase 2 实现）
enum EquipmentRecognition {
    /// 低于这个把握就让用户手动选
    static let confidenceThreshold = 0.75
}

/// 本地器械曲线库（MachinePhysicsProfiles.json）
struct MachineProfileLibrary {
    var profiles: [MachineProfile]

    static let fileName = "MachinePhysicsProfiles"

    static func load(bundle: Bundle = .main) -> MachineProfileLibrary {
        guard let url = bundle.url(forResource: fileName, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return MachineProfileLibrary(profiles: []) }
        return (try? decode(data)) ?? MachineProfileLibrary(profiles: [])
    }

    static func decode(_ data: Data) throws -> MachineProfileLibrary {
        MachineProfileLibrary(profiles: try JSONDecoder().decode([MachineProfile].self, from: data))
    }

    func profile(id: String) -> MachineProfile? {
        profiles.first { $0.id == id }
    }

    /// 识别模型的类别名或动作名 → 器械（id、中文名、别名都能对上）
    func match(_ label: String) -> MachineProfile? {
        let l = label.trimmingCharacters(in: .whitespaces)
        guard !l.isEmpty else { return nil }
        return profiles.first { $0.id == l || $0.name == l || $0.aliases.contains(l) }
            ?? profiles.first { p in l.contains(p.name) || p.aliases.contains { !$0.isEmpty && l.contains($0) } }
    }
}
