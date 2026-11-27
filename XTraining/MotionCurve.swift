import SwiftUI
import AVFoundation
import Vision
import PhotosUI
import UniformTypeIdentifiers

// 录动作算阻力曲线：录 5–8 秒视频，手机本地分析，不联网
// 视频第一帧 = 动作起始位置（开始）。
// 原理：手移动一段距离时，杠铃片（或铁块）被抬高多少。片子升得多 = 手上重；升得少 = 手上轻。
// 哑铃杠铃（重量就在手上）：手往上走的那部分才在对抗重量，所以按手的移动方向算。
// 拍不到片子：看手在哪个位置变慢（最慢的地方最吃力）。

enum CurveKind: String, Codable {
    case ascending, descending, bell, flat
    var title: String {
        switch self {
        case .ascending: return "上升阻力"
        case .descending: return "下降阻力"
        case .bell: return "钟形阻力"
        case .flat: return "平稳阻力"
        }
    }
    var type: String {
        switch self {
        case .ascending: return "越往后越重 · 缩短位最吃力"
        case .descending: return "越往后越轻 · 拉长位最吃力"
        case .bell: return "中间最重 · 中段最吃力"
        case .flat: return "从头到尾差不多"
        }
    }
    var zone: Overload.Zone {
        switch self {
        case .ascending: return .short
        case .descending: return .long
        case .bell, .flat: return .mid
        }
    }
    var tip: String {
        switch self {
        case .descending: return "肌肉拉长的时候最重，到顶反而轻。拉长位已经练到了，可以在顶端多停 1 秒补一补收缩。"
        case .ascending: return "越往后越重，肌肉拉长的时候阻力小。想多练拉长位，可以每组最后加几次只做前半程。"
        case .bell: return "中间最重，两头比较轻。可以再配一个拉长位的动作。"
        case .flat: return "整个动作的阻力比较均匀。"
        }
    }
    static func of(_ v: [Double]) -> CurveKind {
        guard v.count >= 6 else { return .flat }
        let n = v.count, k = max(1, n * 3 / 10)
        func mean(_ s: ArraySlice<Double>) -> Double { s.isEmpty ? 0 : s.reduce(0, +) / Double(s.count) }
        let first = mean(v[0..<k]), last = mean(v[(n - k)..<n]), mid = mean(v[k..<(n - k)])
        if mid > max(first, last) * 1.1 { return .bell }
        if last > first * 1.15 { return .ascending }
        if first > last * 1.15 { return .descending }
        return .flat
    }
}

enum CurveMethod: String, Codable {
    case plate, inHand, speed
    var label: String {
        switch self {
        case .plate: return "按手和杠铃片的移动算"
        case .inHand: return "按手的移动方向算（重量在手上）"
        case .speed: return "按你在哪里变慢估算"
        }
    }
}

struct SavedCurve: Codable, Identifiable, Hashable {
    var id: String { name }
    var name: String
    var values: [Double]          // 从开始（重量最低）到结束，0…1，1 = 最吃力
    var method: CurveMethod
    var peakPct: Int? = nil       // 最吃力时约是重量的百分之几（只有挂片/哑铃时有）
    var lowPct: Int? = nil
    var seat: String? = nil       // 座椅档位
    var date: Double = Date().timeIntervalSince1970
    var kind: CurveKind { CurveKind.of(values) }
}

// 录过的曲线存在本机（xt.curves），以后进步页的阻力曲线按这个算
final class CurveStore: ObservableObject {
    static let shared = CurveStore()
    @Published private(set) var curves: [String: SavedCurve] = [:]
    private let key = "xt.curves"
    init() {
        if let d = UserDefaults.standard.data(forKey: key), let c = try? JSONDecoder().decode([String: SavedCurve].self, from: d) { curves = c }
    }
    func save(_ c: SavedCurve) { curves[c.name] = c; persist() }
    func remove(_ name: String) { curves[name] = nil; persist() }
    private func persist() { if let d = try? JSONEncoder().encode(curves) { UserDefaults.standard.set(d, forKey: key) } }
    func curve(for name: String) -> SavedCurve? {
        let n = name.trimmingCharacters(in: .whitespaces)
        if n.isEmpty { return nil }
        if let c = curves[n] { return c }
        return curves.values.first { $0.name.count >= 2 && (n.contains($0.name) || $0.name.contains(n)) }
    }
    var sorted: [SavedCurve] { curves.values.sorted { $0.date > $1.date } }
}

// MARK: - 分析

struct CurveResult {
    var values: [Double]
    var method: CurveMethod
    var peakPct: Int?
    var lowPct: Int?
    var reps: Int
    var seconds: Double
    var lever: (from: Int, to: Int)? = nil       // 杠杆和水平线的夹角（度），开始 → 结束
    var armDrop: Int? = nil                       // 挂片离转轴横向距离变化（%，正数=变远/变重）
    var joints: [(name: String, from: Int, to: Int)] = []   // 主要关节角度，开始 → 结束
    var usedHand = true                           // false = 手被挡住，只按杠杆角度算
}

enum MotionError: LocalizedError {
    case noVideo, noHand, tooSmall, noPlate
    var errorDescription: String? {
        switch self {
        case .noVideo: return "读不了这段视频，换一段试试"
        case .noHand: return "没认出手。手机放稳，让整个人和手都在画面里再录一次"
        case .tooSmall: return "动作幅度太小，每次做满全程再录一次"
        case .noPlate: return "跟丢了杠铃片。试试从侧面拍、让片子一直在画面里，或者选“看速度”"
        }
    }
}

enum MotionAnalyzer {
    static func generator(_ url: URL) -> AVAssetImageGenerator {
        let g = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        g.appliesPreferredTrackTransform = true
        g.maximumSize = CGSize(width: 720, height: 720)
        let tol = CMTime(value: 1, timescale: 30)
        g.requestedTimeToleranceBefore = tol; g.requestedTimeToleranceAfter = tol
        return g
    }

    static func firstFrame(_ url: URL) async -> UIImage? {
        guard let r = try? await generator(url).image(at: .zero) else { return nil }
        return UIImage(cgImage: r.image)
    }

    // plateBox：Vision 坐标（0…1，左下角为原点）
    // plateBox / pivot：Vision 坐标（0…1，左下角为原点）
    static func analyze(url: URL, method: CurveMethod, plateBox: CGRect?, pivot pivotN: CGPoint? = nil, progress: @escaping (Double) -> Void) async throws -> CurveResult {
        let asset = AVURLAsset(url: url)
        guard let dur = try? await asset.load(.duration), dur.seconds > 0.5 else { throw MotionError.noVideo }
        let secs = min(dur.seconds, 12)
        let fps = 15.0
        let n = Int(secs * fps)
        let gen = generator(url)

        var hands: [CGPoint?] = [], plates: [CGPoint?] = []
        var jointAngles: [String: [Double?]] = ["肘": [], "肩": [], "膝": [], "髋": []]
        var size = CGSize(width: 1, height: 1)
        let seq = VNSequenceRequestHandler()
        var lastObs: VNDetectedObjectObservation? = plateBox.map { VNDetectedObjectObservation(boundingBox: $0) }
        let track: VNTrackObjectRequest? = lastObs.map { VNTrackObjectRequest(detectedObjectObservation: $0) }
        track?.trackingLevel = .accurate

        for i in 0..<n {
            let t = CMTime(seconds: Double(i) / fps, preferredTimescale: 600)
            guard let got = try? await gen.image(at: t) else {
                hands.append(nil); plates.append(nil); for k in jointAngles.keys { jointAngles[k]?.append(nil) }; continue
            }
            let cg = got.image
            size = CGSize(width: cg.width, height: cg.height)
            // 人体：手腕位置 + 肘/肩/膝/髋角度
            let pose = VNDetectHumanBodyPoseRequest()
            try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([pose])
            var hp: CGPoint? = nil
            var ang: [String: Double] = [:]
            if let o = pose.results?.max(by: { area($0) < area($1) }) {
                func pt(_ j: VNHumanBodyPoseObservation.JointName) -> CGPoint? {
                    guard let r = try? o.recognizedPoint(j), r.confidence > 0.3 else { return nil }
                    return CGPoint(x: r.location.x * size.width, y: r.location.y * size.height)
                }
                let ws = [pt(.leftWrist), pt(.rightWrist)].compactMap { $0 }
                if !ws.isEmpty { hp = CGPoint(x: ws.map(\.x).reduce(0, +) / CGFloat(ws.count), y: ws.map(\.y).reduce(0, +) / CGFloat(ws.count)) }
                let sides: [[VNHumanBodyPoseObservation.JointName]] = [
                    [.leftShoulder, .leftElbow, .leftWrist, .leftHip, .leftKnee, .leftAnkle],
                    [.rightShoulder, .rightElbow, .rightWrist, .rightHip, .rightKnee, .rightAnkle]]
                var acc: [String: [Double]] = [:]
                for sd in sides {
                    let sh = pt(sd[0]), el = pt(sd[1]), wr = pt(sd[2]), hip = pt(sd[3]), kn = pt(sd[4]), an = pt(sd[5])
                    if let a = angle(sh, el, wr) { acc["肘", default: []].append(a) }
                    if let a = angle(hip, sh, el) { acc["肩", default: []].append(a) }
                    if let a = angle(hip, kn, an) { acc["膝", default: []].append(a) }
                    if let a = angle(sh, hip, kn) { acc["髋", default: []].append(a) }
                }
                for (k, v) in acc { ang[k] = v.reduce(0, +) / Double(v.count) }
            }
            hands.append(hp)
            for k in jointAngles.keys { jointAngles[k]?.append(ang[k]) }
            // 杠铃片：从第一帧你点的位置开始一路跟
            var pp: CGPoint? = nil
            if let req = track, let obs = lastObs {
                if i == 0 { pp = CGPoint(x: obs.boundingBox.midX * size.width, y: obs.boundingBox.midY * size.height) }
                else {
                    req.inputObservation = obs
                    try? seq.perform([req], on: cg)
                    if let o = req.results?.first as? VNDetectedObjectObservation {
                        lastObs = o
                        if o.confidence > 0.25 { pp = CGPoint(x: o.boundingBox.midX * size.width, y: o.boundingBox.midY * size.height) }
                    }
                }
            }
            plates.append(pp)
            let p = Double(i + 1) / Double(n)
            await MainActor.run { progress(p) }
        }

        let diag = hypot(size.width, size.height)
        let handOK = hands.compactMap({ $0 }).count >= max(10, n / 2)
        let pivot = pivotN.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }

        var plate: [CGPoint] = []
        if method == .plate {
            guard plates.compactMap({ $0 }).count >= max(10, n / 2) else { throw MotionError.noPlate }
            plate = smooth(fill(plates))
        }
        let useLever = method == .plate && pivot != nil
        if !useLever && !handOK { throw MotionError.noHand }
        let hand = handOK ? smooth(fill(hands)) : []

        // 进度（0 = 开始，1 = 动作最远处）。有转轴时按杠杆角度算，否则按手的轨迹
        var prog: [CGFloat]
        var theta: [CGFloat] = []
        var R: CGFloat = 1
        if useLever, let pv = pivot {
            var th = plate.map { atan2($0.y - pv.y, $0.x - pv.x) }
            for i in 1..<th.count {   // 角度展开，避免跨过 ±180° 时跳变
                while th[i] - th[i - 1] > .pi { th[i] -= 2 * .pi }
                while th[i] - th[i - 1] < -.pi { th[i] += 2 * .pi }
            }
            theta = th
            R = plate.map { hypot($0.x - pv.x, $0.y - pv.y) }.sorted()[plate.count / 2]
            plate = th.map { CGPoint(x: pv.x + R * cos($0), y: pv.y + R * sin($0)) }   // 按圆弧去抖
            guard R > diag * 0.03 else { throw MotionError.tooSmall }
            let t0 = th.prefix(3).reduce(0, +) / CGFloat(min(3, th.count))
            let lo = pct(th, 0.05), hi = pct(th, 0.95)
            let far = abs(hi - t0) > abs(lo - t0) ? hi : lo
            guard abs(far - t0) > 0.06 else { throw MotionError.tooSmall }
            prog = th.map { min(1, max(0, ($0 - t0) / (far - t0))) }
        } else {
            let pts = hand
            let mx = pts.map(\.x).reduce(0, +) / CGFloat(pts.count), my = pts.map(\.y).reduce(0, +) / CGFloat(pts.count)
            var a: CGFloat = 0, b: CGFloat = 0, c: CGFloat = 0
            for p in pts { let dx = p.x - mx, dy = p.y - my; a += dx * dx; b += dx * dy; c += dy * dy }
            let th = 0.5 * atan2(2 * b, a - c)
            let v = CGPoint(x: cos(th), y: sin(th))
            var s = pts.map { ($0.x - mx) * v.x + ($0.y - my) * v.y }
            let lo = pct(s, 0.05), hi = pct(s, 0.95)
            guard hi - lo > diag * 0.04 else { throw MotionError.tooSmall }
            // 视频第一帧就是动作的起始位置
            let s0 = s.prefix(3).reduce(0, +) / CGFloat(min(3, s.count))
            if s0 - lo > hi - s0 { s = s.map { -$0 } }
            let lo2 = pct(s, 0.05), hi2 = pct(s, 0.95)
            prog = s.map { min(1, max(0, ($0 - lo2) / max(1, hi2 - lo2))) }
        }

        let bins = 10
        var buckets = Array(repeating: [Double](), count: bins)
        let minMove = diag * 0.004
        for i in 1..<(prog.count - 1) {
            let bi = min(bins - 1, Int(prog[i] * CGFloat(bins)))
            if useLever && !handOK {
                // 手被挡住：只按杠杆，阻力 ∝ 挂片离转轴的横向距离
                buckets[bi].append(Double(abs(cos(theta[i]))))
                continue
            }
            let dh = hypot(hand[i + 1].x - hand[i - 1].x, hand[i + 1].y - hand[i - 1].y)
            guard dh > minMove else { continue }
            switch method {
            case .plate:
                buckets[bi].append(Double(abs(plate[i + 1].y - plate[i - 1].y) / dh))
            case .inHand:
                buckets[bi].append(Double(abs(hand[i + 1].y - hand[i - 1].y) / dh))
            case .speed:
                guard prog[i + 1] > prog[i - 1] else { continue }   // 只看往外做的那一段
                buckets[bi].append(Double(1 / dh))
            }
        }
        var raw = buckets.map { $0.isEmpty ? Double.nan : median($0) }
        raw = interpolateNaN(raw)
        guard !raw.contains(where: \.isNaN) else { throw MotionError.tooSmall }
        raw = smooth3(raw)
        let peak = raw.max() ?? 1
        let values = raw.map { peak > 0 ? $0 / peak : 0 }

        var res = CurveResult(values: values, method: method, peakPct: nil, lowPct: nil, reps: 0, seconds: secs)
        res.usedHand = !(useLever && !handOK)
        if method != .speed && res.usedHand {
            res.peakPct = Int((min(1.2, peak) * 100).rounded())
            res.lowPct = Int((min(1.2, raw.min() ?? 0) * 100).rounded())
        }
        // 开始 / 结束时的样子：开始 = 前 3 帧，结束 = 进度 > 0.9 的帧
        let startIdx = Array(0..<min(3, prog.count))
        let endIdx = prog.indices.filter { prog[$0] > 0.9 }
        func avg(_ a: [CGFloat]) -> CGFloat { a.isEmpty ? 0 : a.reduce(0, +) / CGFloat(a.count) }
        if useLever, !endIdx.isEmpty {
            func deg(_ t: CGFloat) -> Int { Int((abs(Double(atan(tan(t)))) * 180 / .pi).rounded()) }
            let a0 = avg(startIdx.map { theta[$0] }), a1 = avg(endIdx.map { theta[$0] })
            res.lever = (from: deg(a0), to: deg(a1))
            let h0 = abs(cos(a0)), h1 = abs(cos(a1))
            if h0 > 0.01 { res.armDrop = Int(((h1 - h0) / h0 * 100).rounded()) }
        }
        // 关节：取变化最大的两个
        var js: [(String, Int, Int, Double)] = []
        for (k, arr) in jointAngles {
            let vals = arr.compactMap { $0 }
            guard vals.count >= n / 3, !endIdx.isEmpty else { continue }
            let st = startIdx.compactMap { arr[$0] }, en = endIdx.compactMap { $0 < arr.count ? arr[$0] : nil }
            guard !st.isEmpty, !en.isEmpty else { continue }
            let a0 = st.reduce(0, +) / Double(st.count), a1 = en.reduce(0, +) / Double(en.count)
            js.append((k, Int(a0.rounded()), Int(a1.rounded()), abs(a1 - a0)))
        }
        res.joints = js.filter { $0.3 >= 15 }.sorted { $0.3 > $1.3 }.prefix(2).map { (name: $0.0, from: $0.1, to: $0.2) }
        // 数一下做了几次
        var up = false
        for p in prog { if !up && p > 0.7 { up = true; res.reps += 1 } else if up && p < 0.3 { up = false } }
        return res
    }

    // 三点夹角（中间那个点为顶点），度
    private static func angle(_ a: CGPoint?, _ b: CGPoint?, _ c: CGPoint?) -> Double? {
        guard let a, let b, let c else { return nil }
        let v1 = CGVector(dx: a.x - b.x, dy: a.y - b.y), v2 = CGVector(dx: c.x - b.x, dy: c.y - b.y)
        let l1 = hypot(v1.dx, v1.dy), l2 = hypot(v2.dx, v2.dy)
        guard l1 > 1, l2 > 1 else { return nil }
        let cosv = max(-1, min(1, (v1.dx * v2.dx + v1.dy * v2.dy) / (l1 * l2)))
        return Double(acos(cosv)) * 180 / .pi
    }

    private static func area(_ o: VNHumanBodyPoseObservation) -> CGFloat {
        guard let pts = try? o.recognizedPoints(.all).values.filter({ $0.confidence > 0.2 }), !pts.isEmpty else { return 0 }
        let xs = pts.map(\.location.x), ys = pts.map(\.location.y)
        return ((xs.max() ?? 0) - (xs.min() ?? 0)) * ((ys.max() ?? 0) - (ys.min() ?? 0))
    }
    private static func pct(_ a: [CGFloat], _ q: Double) -> CGFloat {
        let s = a.sorted(); return s[min(s.count - 1, max(0, Int(Double(s.count - 1) * q)))]
    }
    private static func median(_ a: [Double]) -> Double { let s = a.sorted(); return s[s.count / 2] }
    // 缺的帧用前后插值补上
    private static func fill(_ a: [CGPoint?]) -> [CGPoint] {
        let idx = a.indices.filter { a[$0] != nil }
        guard let f = idx.first, let l = idx.last else { return [] }
        var out = [CGPoint](repeating: .zero, count: a.count)
        for i in a.indices {
            if let p = a[i] { out[i] = p; continue }
            if i < f { out[i] = a[f]!; continue }
            if i > l { out[i] = a[l]!; continue }
            let p0 = idx.last { $0 < i }!, p1 = idx.first { $0 > i }!
            let t = CGFloat(i - p0) / CGFloat(p1 - p0)
            out[i] = CGPoint(x: a[p0]!.x + (a[p1]!.x - a[p0]!.x) * t, y: a[p0]!.y + (a[p1]!.y - a[p0]!.y) * t)
        }
        return out
    }
    private static func smooth(_ a: [CGPoint], w: Int = 2) -> [CGPoint] {
        a.indices.map { i in
            let r = max(0, i - w)...min(a.count - 1, i + w)
            let k = CGFloat(r.count)
            return CGPoint(x: r.map { a[$0].x }.reduce(0, +) / k, y: r.map { a[$0].y }.reduce(0, +) / k)
        }
    }
    private static func smooth3(_ a: [Double]) -> [Double] {
        a.indices.map { i in
            let l = a[max(0, i - 1)], r = a[min(a.count - 1, i + 1)]
            return 0.25 * l + 0.5 * a[i] + 0.25 * r
        }
    }
    private static func interpolateNaN(_ a: [Double]) -> [Double] {
        let ok = a.indices.filter { !a[$0].isNaN }
        guard let f = ok.first, let l = ok.last, ok.count >= 3 else { return a }
        return a.indices.map { i in
            if !a[i].isNaN { return a[i] }
            if i < f { return a[f] }
            if i > l { return a[l] }
            let p0 = ok.last { $0 < i }!, p1 = ok.first { $0 > i }!
            return a[p0] + (a[p1] - a[p0]) * Double(i - p0) / Double(p1 - p0)
        }
    }
}

// MARK: - 曲线图

struct CurveChart: View {
    let values: [Double]
    var start = "开始（拉长位）"
    var end = "结束（缩短位）"
    var color = Color(hex: 0xe8590c)
    var compact = false
    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { g in
                let w = g.size.width, h = g.size.height
                let pts: [CGPoint] = values.enumerated().map { i, v in
                    CGPoint(x: w * CGFloat(i) / CGFloat(max(1, values.count - 1)), y: h - 6 - (h - 12) * CGFloat(max(0, min(1, v))))
                }
                ZStack {
                    curvePath(pts, close: h).fill(LinearGradient(colors: [color.opacity(0.35), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                    curvePath(pts, close: nil).stroke(color, style: StrokeStyle(lineWidth: compact ? 2.5 : 4, lineCap: .round, lineJoin: .round))
                    if !compact, let i = values.indices.max(by: { values[$0] < values[$1] }) {
                        Circle().fill(color).frame(width: 14, height: 14).overlay(Circle().stroke(.white, lineWidth: 3)).position(pts[i])
                    }
                }
            }
            if !compact {
                HStack { Text(start); Spacer(); Text(end) }.font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func curvePath(_ p: [CGPoint], close h: CGFloat?) -> Path {
        Path { path in
            guard let f = p.first else { return }
            path.move(to: f)
            for i in 1..<p.count {
                let m = CGPoint(x: (p[i - 1].x + p[i].x) / 2, y: (p[i - 1].y + p[i].y) / 2)
                path.addQuadCurve(to: m, control: p[i - 1])
            }
            if let l = p.last { path.addLine(to: l) }
            if let h, let l = p.last { path.addLine(to: CGPoint(x: l.x, y: h)); path.addLine(to: CGPoint(x: f.x, y: h)); path.closeSubpath() }
        }
    }
}

// MARK: - 界面

struct MotionCurveSheet: View {
    let names: [String]              // 最近练过的动作，方便选
    var preset: String = ""
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var cs = CurveStore.shared

    enum Step { case home, mark, analyzing, result }
    @State private var step: Step = .home
    @State private var pick: PhotosPickerItem? = nil
    @State private var camera = false
    @State private var url: URL? = nil
    @State private var frame: UIImage? = nil
    @State private var tap: CGPoint? = nil        // 杠铃片，0…1，左上角为原点
    @State private var pivotTap: CGPoint? = nil   // 转轴
    @State private var noPivot = false
    @State private var seat = ""
    @State private var boxSize: CGFloat = 0.18
    @State private var progress = 0.0
    @State private var result: CurveResult? = nil
    @State private var flipped = false
    @State private var name = ""
    @State private var error: String? = nil
    @State private var saved = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch step {
                    case .home: home
                    case .mark: mark
                    case .analyzing: analyzing
                    case .result: resultView
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(step == .home ? "阻力曲线" : step == .mark ? "点一下杠铃片" : step == .analyzing ? "正在分析" : "分析结果")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(step == .home ? "关闭" : "返回") { if step == .home { dismiss() } else { reset() } } }
            }
        }
        .onAppear { if name.isEmpty { name = preset } }
        .onChange(of: pick) { _, it in
            guard let it else { return }
            Task {
                if let m = try? await it.loadTransferable(type: PickedMovie.self) { await load(m.url) }
                else { error = MotionError.noVideo.errorDescription }
                pick = nil
            }
        }
        .fullScreenCover(isPresented: $camera) {
            VideoCamera { u in camera = false; if let u { Task { await load(u) } } }.ignoresSafeArea()
        }
    }

    // 首页：两个入口 + 录过的动作
    private var home: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("全部在手机上分析，不联网，视频不会上传").font(.footnote).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("录动作").font(.title2.bold())
                        Text("手机放稳，录 5–8 秒（2–3 次完整动作）\n看你在哪个位置最吃力").font(.subheadline).opacity(0.85)
                    }
                    Spacer()
                    Image(systemName: "figure.strengthtraining.traditional").font(.system(size: 40))
                }
                HStack(spacing: 10) {
                    Button { camera = true } label: {
                        Label("现场录", systemImage: "video.fill").font(.subheadline.bold()).frame(maxWidth: .infinity).padding(.vertical, 11)
                            .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                    PhotosPicker(selection: $pick, matching: .videos) {
                        Label("从相册选", systemImage: "photo.on.rectangle").font(.subheadline.bold()).frame(maxWidth: .infinity).padding(.vertical, 11)
                            .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(18)
            .background(LinearGradient(colors: [Color(hex: 0x1c1c1e), Color(hex: 0x3a3a3c)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 22, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("拍器械").font(.title2.bold())
                    Text("即将上线").font(.caption2.bold()).padding(.horizontal, 7).padding(.vertical, 3).background(.white.opacity(0.25), in: Capsule())
                    Spacer()
                    Image(systemName: "camera.fill").font(.system(size: 34))
                }
                Text("拍一张整台器械，认出是什么、给出阻力曲线。识别模型还在训练。").font(.subheadline).opacity(0.9)
            }
            .foregroundStyle(.white)
            .padding(18)
            .background(LinearGradient(colors: [Color(hex: 0xe8590c), Color(hex: 0xf08c00)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .opacity(0.6)

            if let error { Text(error).font(.subheadline).foregroundStyle(Tone.down) }

            VStack(alignment: .leading, spacing: 8) {
                Text("怎么录更准").font(.headline)
                Text("· 从动作的起始位置开始录，第一帧就算动作开始\n· 手机放稳，别手拿着晃\n· 尽量从侧面拍，手和杠铃片（或铁块）都在画面里\n· 每次做满全程，别只做半程").font(.subheadline).foregroundStyle(.secondary)
            }
            .card()

            if !cs.sorted.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("我录过的动作").font(.headline)
                    ForEach(cs.sorted) { c in
                        HStack(spacing: 12) {
                            CurveChart(values: c.values, compact: true).frame(width: 64, height: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.name).font(.subheadline.bold())
                                Text("\(c.kind.title) · \(c.kind.type)" + (c.seat.map { " · 座椅 \($0) 档" } ?? "")).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) { cs.remove(c.name) } label: { Image(systemName: "trash").font(.footnote) }
                                .buttonStyle(.borderless).tint(.secondary)
                        }
                    }
                }
                .card()
            }
        }
    }

    // 第一帧上点杠铃片
    private var mark: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(pivotTap == nil && !noPivot ? "第一帧就是动作开始。先点一下**转轴**（杠杆绕着转的那颗螺栓）" : tap == nil ? "再点一下**杠铃片或铁块**，手机会一路跟着它" : "好了。人体关节手机会自动认，点“开始分析”").font(.subheadline)
            HStack(spacing: 14) {
                if pivotTap == nil && !noPivot {
                    Button("没有转轴（插片、绳索）") { noPivot = true }.font(.footnote)
                }
                if pivotTap != nil || tap != nil || noPivot {
                    Button("重新点") { pivotTap = nil; tap = nil; noPivot = false }.font(.footnote)
                }
            }
            if let img = frame {
                Image(uiImage: img).resizable().scaledToFit()
                    .overlay {
                        GeometryReader { g in
                            ZStack {
                                Color.clear.contentShape(Rectangle())
                                    .onTapGesture { loc in
                                        let q = CGPoint(x: loc.x / g.size.width, y: loc.y / g.size.height)
                                        if pivotTap == nil && !noPivot { pivotTap = q } else { tap = q }
                                    }
                                if let pv = pivotTap {
                                    Circle().fill(Color(hex: 0xe8590c)).frame(width: 18, height: 18).overlay(Circle().stroke(.white, lineWidth: 3))
                                        .overlay(Text("转轴").font(.caption2.bold()).foregroundStyle(.white).padding(3).background(.black.opacity(0.6), in: Capsule()).offset(y: -20))
                                        .position(x: pv.x * g.size.width, y: pv.y * g.size.height)
                                        .allowsHitTesting(false)
                                }
                                if let t = tap {
                                    let side = g.size.width * boxSize
                                    RoundedRectangle(cornerRadius: 8).stroke(Color.yellow, style: StrokeStyle(lineWidth: 3, dash: [7, 5]))
                                        .frame(width: side, height: side)
                                        .position(x: t.x * g.size.width, y: t.y * g.size.height)
                                        .allowsHitTesting(false)
                                }
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                if tap != nil {
                    HStack { Text("框的大小").font(.caption).foregroundStyle(.secondary); Slider(value: $boxSize, in: 0.08...0.45) }
                }
            }
            Button { run(.plate) } label: {
                Text("开始分析").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(tap == nil ? Color.gray.opacity(0.4) : Color.primary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(Color(.systemBackground))
            }
            .disabled(tap == nil)
            Button { run(.inHand) } label: {
                Text("重量就在手上（哑铃、杠铃）").font(.subheadline.bold()).frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            Button { run(.speed) } label: {
                Text("拍不到片子，看我在哪里变慢").font(.subheadline.bold()).frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            if let error { Text(error).font(.subheadline).foregroundStyle(Tone.down) }
        }
    }

    private var analyzing: some View {
        VStack(spacing: 16) {
            ProgressView(value: progress).tint(Color(hex: 0xe8590c))
            Text("正在看转轴、杠铃片和你的关节… \(Int(progress * 100))%").font(.subheadline).foregroundStyle(.secondary)
            Text("全部在手机上算，不联网").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.top, 40)
    }

    private var resultView: some View {
        let r = result!
        let vals = flipped ? Array(r.values.reversed()) : r.values
        let kind = CurveKind.of(vals)
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("录了 \(Int(r.seconds.rounded())) 秒 · \(max(1, r.reps)) 次 · \(r.method.label)").font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("阻力曲线").font(.title3.bold())
                    Text("视频算出").font(.caption2.bold()).padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color(hex: 0xd3f9d8), in: RoundedRectangle(cornerRadius: 7)).foregroundStyle(Color(hex: 0x2b8a3e))
                    Spacer()
                    Text("越往上越吃力").font(.caption).foregroundStyle(.secondary)
                }
                let j0 = r.joints.first
                CurveChart(values: vals,
                           start: j0.map { "开始 · \($0.name) \(flipped ? $0.to : $0.from)°" } ?? "开始（拉长位）",
                           end: j0.map { "结束 · \($0.name) \(flipped ? $0.from : $0.to)°" } ?? "结束（缩短位）")
                    .frame(height: 190)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(kind.title).font(.title2.bold()).foregroundStyle(Color(hex: 0xe8590c))
                    Text(kind.type).font(.footnote).foregroundStyle(.secondary)
                }
                if let p = r.peakPct, let l = r.lowPct, r.method == .plate {
                    Text("最吃力时约是片子重量的 \(p)%，最轻时约 \(l)%（估算，片子离镜头远近会有偏差）").font(.footnote).foregroundStyle(.secondary)
                }
                Text(kind.tip).font(.subheadline)
                Button { withAnimation(.snappy) { flipped.toggle() } } label: {
                    Label("开始和结束弄反了？点这里换过来", systemImage: "arrow.left.arrow.right").font(.footnote)
                }
            }
            .card()

            VerdictCard(kind: kind, name: name)

            if r.lever != nil || !r.joints.isEmpty || !r.usedHand {
                VStack(alignment: .leading, spacing: 8) {
                    Text("转轴、杠铃片、关节一起看出来的").font(.headline)
                    if let lv = r.lever {
                        row("杠杆和水平线的角度", "\(flipped ? lv.to : lv.from)° → \(flipped ? lv.from : lv.to)°")
                    }
                    if let d = r.armDrop {
                        row("挂片离转轴的横向距离", d >= 0 ? "越来越远，多了 \(d)%" : "越来越近，少了 \(-d)%")
                    }
                    if let p = r.peakPct, let l = r.lowPct, r.method == .plate {
                        row("手上的阻力", "最重 \(p)% → 最轻 \(l)%")
                    }
                    if !r.joints.isEmpty {
                        row("主要关节", r.joints.map { "\($0.name) \(flipped ? $0.to : $0.from)° → \(flipped ? $0.from : $0.to)°" }.joined(separator: "，"))
                    }
                    if !r.usedHand {
                        Text("手被挡住了，这次只按杠杆角度算").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .card()
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("存到哪个动作").font(.headline)
                TextField("动作名，比如 T 杠划船", text: $name).textFieldStyle(.roundedBorder)
                if !names.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(names.prefix(12), id: \.self) { n in
                                Button(n) { name = n }.font(.footnote).padding(.horizontal, 11).padding(.vertical, 6)
                                    .background(name == n ? Color.primary : Color(.tertiarySystemFill), in: Capsule())
                                    .foregroundStyle(name == n ? Color(.systemBackground) : Color.primary)
                            }
                        }
                    }
                }
                HStack {
                    Text("座椅档位").font(.subheadline)
                    TextField("选填，比如 4", text: $seat).textFieldStyle(.roundedBorder).frame(maxWidth: 140)
                }
                Text("存好以后，进步页的阻力曲线按这条算；换了器械或座椅档位再录一次就更新").font(.caption).foregroundStyle(.secondary)
            }
            .card()

            Button {
                let n = name.trimmingCharacters(in: .whitespaces)
                guard !n.isEmpty else { return }
                let st = seat.trimmingCharacters(in: .whitespaces)
                cs.save(SavedCurve(name: n, values: vals, method: r.method, peakPct: r.peakPct, lowPct: r.lowPct, seat: st.isEmpty ? nil : st))
                saved = true
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } label: {
                Text(saved ? "已存到「\(name)」" : "存到这个动作").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(saved ? Tone.up : Color.primary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(Color(.systemBackground))
            }
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            if saved { Button("完成") { dismiss() }.frame(maxWidth: .infinity).padding(.top, 4) }
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(k).font(.subheadline)
            Spacer(minLength: 12)
            Text(v).font(.subheadline.bold()).multilineTextAlignment(.trailing)
        }
    }

    private func reset() {
        step = .home; url = nil; frame = nil; tap = nil; pivotTap = nil; noPivot = false; result = nil; flipped = false; error = nil; saved = false; progress = 0
    }

    @MainActor private func load(_ u: URL) async {
        error = nil
        url = u
        guard let f = await MotionAnalyzer.firstFrame(u) else { error = MotionError.noVideo.errorDescription; return }
        frame = f; tap = nil; pivotTap = nil; noPivot = false; step = .mark
    }

    private func run(_ m: CurveMethod) {
        guard let u = url else { return }
        var box: CGRect? = nil
        if m == .plate, let t = tap, let f = frame {
            let bw = boxSize, bh = boxSize * f.size.width / max(1, f.size.height)
            let cx = t.x, cy = 1 - t.y
            box = CGRect(x: max(0, cx - bw / 2), y: max(0, cy - bh / 2), width: min(bw, 1), height: min(bh, 1))
        }
        error = nil; progress = 0; step = .analyzing
        Task {
            do {
                let pv: CGPoint? = (m == .plate) ? pivotTap.map { CGPoint(x: $0.x, y: 1 - $0.y) } : nil
                let r = try await MotionAnalyzer.analyze(url: u, method: m, plateBox: box, pivot: pv) { p in progress = p }
                await MainActor.run { result = r; flipped = false; saved = false; step = .result }
            } catch {
                await MainActor.run { self.error = error.localizedDescription; step = .mark }
            }
        }
    }
}

// 相册选视频
struct PickedMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { m in SentTransferredFile(m.url) } importing: { r in
            let dst = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + (r.file.pathExtension.isEmpty ? "mov" : r.file.pathExtension))
            try? FileManager.default.removeItem(at: dst)
            try FileManager.default.copyItem(at: r.file, to: dst)
            return PickedMovie(url: dst)
        }
    }
}

// 现场录（最长 10 秒）
struct VideoCamera: UIViewControllerRepresentable {
    let done: (URL?) -> Void
    func makeCoordinator() -> Coord { Coord(done: done) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .camera
        p.mediaTypes = ["public.movie"]
        p.cameraCaptureMode = .video
        p.videoMaximumDuration = 10
        p.videoQuality = .typeHigh
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    final class Coord: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let done: (URL?) -> Void
        init(done: @escaping (URL?) -> Void) { self.done = done }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            done(info[.mediaURL] as? URL)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { done(nil) }
    }
}

// MARK: - 按阻力曲线评价动作（增肌为主；依据拉长位训练研究，属于估算）

struct CurveVerdict {
    let muscle: String      // 胸 / 背 / 肩 / 股四 / 腘绳 / 臀 / 二头 / 三头 / 腹肌
    let stars: Int
    let label: String       // 很适合 / 可以 / 建议补一个
    let reason: String
    let tip: String
}

enum CurveAdvice {
    struct Row { let muscle: String; let best: [CurveKind]; let bestText: String; let why: String; let example: String }
    static let table: [Row] = [
        Row(muscle: "胸", best: [.descending], bestText: "下降阻力", why: "手臂打开、胸被拉开时最重", example: "上斜哑铃飞鸟、推胸机起点重的"),
        Row(muscle: "背", best: [.descending], bestText: "下降阻力", why: "手臂伸直、背被拉长时最重", example: "挂片划船、全程引体、直臂下拉"),
        Row(muscle: "肩", best: [.flat, .descending], bestText: "平稳 / 下降", why: "手臂垂下时也要有阻力", example: "哑铃侧平举是上升阻力（下面没劲），换身后绳索侧平举"),
        Row(muscle: "股四", best: [.descending], bestText: "下降阻力", why: "膝盖弯得深时最重", example: "深蹲、哈克深蹲、腿屈伸起点重的"),
        Row(muscle: "腘绳", best: [.descending], bestText: "下降阻力", why: "腿伸直时最重", example: "坐姿腿弯举（比俯卧好）、罗马尼亚硬拉"),
        Row(muscle: "臀", best: [.descending], bestText: "下降为主，上升补充", why: "臀被拉长（蹲深）时最重", example: "深蹲、箭步为主；臀推是上升阻力，用来补顶峰"),
        Row(muscle: "二头", best: [.descending], bestText: "下降阻力", why: "手臂伸直时最重", example: "上斜弯举、牧师凳弯举"),
        Row(muscle: "三头", best: [.descending], bestText: "下降阻力", why: "手肘弯到底时最重", example: "过头臂屈伸"),
        Row(muscle: "腹肌", best: [.descending], bestText: "下降阻力", why: "腹部被拉长（身体后仰）时最重", example: "绳索卷腹、健腹轮"),
    ]

    // 按动作名认是哪块肌肉
    static func muscle(for name: String) -> String? {
        let n = name
        guard let part = Parts.of(n) else { return nil }
        switch part {
        case "腿":
            if ["臀推", "臀桥", "臀"].contains(where: n.contains) { return "臀" }
            if ["腿弯举", "罗马尼亚", "直腿硬拉", "腘绳"].contains(where: n.contains) { return "腘绳" }
            return "股四"
        case "手臂":
            if ["臂屈伸", "下压", "三头", "窄距"].contains(where: n.contains) { return "三头" }
            return "二头"
        case "胸", "背", "肩", "腹肌": return part
        default: return nil
        }
    }

    static func verdict(kind: CurveKind, name: String) -> CurveVerdict? {
        guard let m = muscle(for: name), let row = table.first(where: { $0.muscle == m }) else { return nil }
        let ok = row.best.contains(kind)
        let stars: Int
        let label: String
        if ok { stars = 5; label = "很适合" }
        else if m == "臀" && kind == .ascending { stars = 4; label = "可以" }
        else if kind == .bell || kind == .flat || (kind == .descending) { stars = 4; label = "可以" }
        else { stars = 3; label = "建议补一个" }
        let reason: String
        if ok {
            reason = "\(m)在\(row.why.replacingOccurrences(of: "时最重", with: ""))的时候最该吃力。这个动作是\(kind.title)，正好符合，是练\(m)很理想的阻力。"
        } else if stars == 4 {
            reason = m == "臀" && kind == .ascending
                ? "这是上升阻力，臀在收紧（顶峰）时最重。适合用来补顶峰，主项最好还是蹲、箭步这类拉长位吃力的。"
                : "这是\(kind.title)，能练到\(m)，但\(m)最好在\(row.why.replacingOccurrences(of: "时最重", with: ""))时吃力（\(row.bestText)）。"
        } else {
            reason = "这是\(kind.title)，\(m)被拉长的时候阻力小，跟\(m)最适合的\(row.bestText)正好相反。"
        }
        let tip: String
        switch (ok, kind) {
        case (true, .descending): tip = "顶端偏轻，收缩感会弱一点。可以在顶端停 1 秒。"
        case (true, _): tip = "保持全程，别只做半程。"
        case (false, .ascending): tip = "补一个拉长位的动作，比如：\(row.example)。也可以每组最后加几次只做前半程。"
        default: tip = "配一个拉长位的动作更好，比如：\(row.example)。"
        }
        return CurveVerdict(muscle: m, stars: stars, label: label, reason: reason, tip: tip)
    }
}

struct VerdictCard: View {
    let kind: CurveKind
    let name: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let v = CurveAdvice.verdict(kind: kind, name: name) {
                HStack {
                    Text("这个动作怎么样").font(.headline)
                    Spacer()
                    Text("\(v.muscle) · \(v.label)").font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 4)
                        .background((v.stars >= 5 ? Tone.up : v.stars == 4 ? Tone.gold : Tone.down).opacity(0.15), in: RoundedRectangle(cornerRadius: 7))
                        .foregroundStyle(v.stars >= 5 ? Tone.up : v.stars == 4 ? Color(hex: 0xa35f00) : Tone.down)
                }
                Text(String(repeating: "★", count: v.stars) + String(repeating: "☆", count: 5 - v.stars)).foregroundStyle(Tone.gold)
                Text(v.reason).font(.subheadline)
                Text("💡 " + v.tip).font(.footnote).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Text("这个动作怎么样").font(.headline)
                Text("在下面填上动作名（比如 T 杠划船），就能按部位评价这个阻力适不适合。").font(.subheadline).foregroundStyle(.secondary)
            }
            Text("依据拉长位训练相关研究（见参考文献），属于估算。增肌最关键的还是练到接近力竭，阻力曲线是加分项。").font(.caption2).foregroundStyle(.tertiary)
        }
        .card()
    }
}
