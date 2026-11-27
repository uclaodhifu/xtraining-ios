import Foundation
import PencilKit

// 专门认手写数字：先按左右位置把笔画拆成一个个字，再拿每个字去和数字模板比形状（$P 点云算法）
// 模板 = 内置的 0~9 写法 + 你自己改对过的写法（改一次记一次，越用越像你的字）
enum DigitReader {
    typealias P = CGPoint
    private static let N = 32
    private static let key = "xt.digitTemplates"

    // 拆字：x 方向重叠的笔画算同一个字；很小、靠下的一笔算小数点
    static func clusters(_ d: PKDrawing) -> [[[P]]] {
        let strokes: [[P]] = d.strokes.map { s in
            s.path.interpolatedPoints(by: .distance(3)).map { $0.location.applying(s.transform) }
        }.filter { !$0.isEmpty }
        let boxed = strokes.map { ($0, box($0)) }.sorted { $0.1.minX < $1.1.minX }
        var out: [([[P]], CGRect)] = []
        for (pts, b) in boxed {
            if let last = out.last {
                let overlap = min(last.1.maxX, b.maxX) - max(last.1.minX, b.minX)
                // 只有左右重叠一大半才算同一个字（4、5、7 的两笔）；挨得近的 2 和 0 不能合成一个，不然 120 会认成 12
                // 又细又高的一笔（1）贴在另一个字的左边：是单独的 1，不能合进去（不然 12 会认成 2）
                let lone = { (n: CGRect, o: CGRect) -> Bool in
                    n.width < n.height * 0.4 && n.height > max(n.height, o.height) * 0.6 && n.midX < o.minX + o.width * 0.3
                }
                if overlap > min(last.1.width, b.width) * 0.55 && !lone(last.1, b) && !lone(b, last.1) {
                    out[out.count - 1].0.append(pts); out[out.count - 1].1 = last.1.union(b); continue
                }
            }
            out.append(([pts], b))
        }
        return out.map { $0.0 }
    }

    static func read(_ d: PKDrawing) -> (text: String, digits: Int) {
        let cs = clusters(d)
        guard !cs.isEmpty else { return ("", 0) }
        let boxes = cs.map { box($0.flatMap { $0 }) }
        let hs = boxes.map(\.height).sorted()
        let h = hs[hs.count / 2]
        let bottom = boxes.map(\.maxY).max() ?? 0
        let tpl = templates()
        var s = "", n = 0
        for (i, c) in cs.enumerated() {
            let b = boxes[i]
            if b.width < h * 0.3 && b.height < h * 0.3 && b.midY > bottom - h * 0.45 { s += "."; continue }
            n += 1
            if b.width < b.height * 0.35 { s += "1"; continue }   // 又细又高就是 1
            s += classify(c, tpl)
        }
        // 只留一个小数点
        var seen = false
        s = String(s.filter { c in if c == "." { if seen { return false }; seen = true }; return true })
        if s.hasPrefix(".") { s.removeFirst() }
        return (s, n)
    }

    // 你在「认成」里改对了：笔画拆出来的字数和你写的数字位数一样，就把每个字记成模板
    static func learn(_ d: PKDrawing, answer: String) {
        let cs = clusters(d)
        let boxes = cs.map { box($0.flatMap { $0 }) }
        guard let h = boxes.map(\.height).sorted().dropFirst(boxes.count / 2).first else { return }
        let bottom = boxes.map(\.maxY).max() ?? 0
        let chars = cs.indices.filter { i in
            let b = boxes[i]
            return !(b.width < h * 0.3 && b.height < h * 0.3 && b.midY > bottom - h * 0.45)
        }
        let digits = answer.filter(\.isNumber).map(String.init)
        guard chars.count == digits.count, !digits.isEmpty else { return }
        var mine = (UserDefaults.standard.dictionary(forKey: key) as? [String: [[[Double]]]]) ?? [:]
        for (k, i) in chars.enumerated() {
            let pts = normalize(cs[i].flatMap { $0 })
            var list = mine[digits[k]] ?? []
            list.append(pts.map { [Double($0.x), Double($0.y)] })
            mine[digits[k]] = Array(list.suffix(12))
        }
        UserDefaults.standard.set(mine, forKey: key)
    }
    // 两边合起来：系统识别和逐个字比形状。位数对不上就信逐个字的；对得上时，你教过的数字信逐个字的
    static func fuse(_ vision: String, _ mine: (text: String, digits: Int)) -> String {
        guard !mine.text.isEmpty else { return vision }
        let v = Array(vision), m = Array(mine.text)
        if vision.isEmpty { return mine.text }
        let vd = v.filter(\.isNumber).count
        if vd > mine.digits { return vision }          // 系统认出的位数更多：多半是这边把两个字拆成了一个，信系统的（防止吞 0）
        if vd != mine.digits || v.count != m.count { return mine.text }
        let taught = taughtDigits
        return String(zip(v, m).map { a, b in a == b ? a : (b.isNumber && (taught[String(b)] ?? 0) >= 2 ? b : a) })
    }
    private static var taughtDigits: [String: Int] {
        ((UserDefaults.standard.dictionary(forKey: key) as? [String: [[[Double]]]]) ?? [:]).mapValues(\.count)
    }
    static var learnedCount: Int {
        ((UserDefaults.standard.dictionary(forKey: key) as? [String: [[[Double]]]]) ?? [:]).values.reduce(0) { $0 + $1.count }
    }

    // MARK: 比形状
    private static func classify(_ c: [[P]], _ tpl: [(String, [P], Bool)]) -> String {
        let pts = normalize(c.flatMap { $0 })
        var best = "", bestD = Double.infinity
        for (label, t, mine) in tpl {
            var d = cloud(pts, t)
            if mine { d *= 0.85 }   // 你自己的写法优先
            if d < bestD { bestD = d; best = label }
        }
        return best
    }
    private static func cloud(_ a: [P], _ b: [P]) -> Double {
        let step = max(1, Int(Double(N).squareRoot() * 0.5))
        var m = Double.infinity
        for i in stride(from: 0, to: N, by: step) {
            m = min(m, greedy(a, b, i), greedy(b, a, i))
        }
        return m
    }
    private static func greedy(_ a: [P], _ b: [P], _ start: Int) -> Double {
        var used = [Bool](repeating: false, count: N)
        var sum = 0.0, i = start
        repeat {
            var mi = -1, md = Double.infinity
            for j in 0..<N where !used[j] {
                let dx = a[i].x - b[j].x, dy = a[i].y - b[j].y
                let d = Double(dx * dx + dy * dy)
                if d < md { md = d; mi = j }
            }
            used[mi] = true
            let w = 1 - Double((i - start + N) % N) / Double(N)
            sum += w * md.squareRoot()
            i = (i + 1) % N
        } while i != start
        return sum
    }
    private static func box(_ p: [P]) -> CGRect {
        guard let f = p.first else { return .zero }
        var r = CGRect(origin: f, size: .zero)
        for q in p { r = r.union(CGRect(origin: q, size: .zero)) }
        return r
    }
    private static func box(_ s: [[P]]) -> CGRect { box(s.flatMap { $0 }) }
    // 取 N 个等距点，按最长边缩放到 1，挪到中心
    static func normalize(_ raw: [P]) -> [P] {
        guard raw.count > 1 else { return Array(repeating: raw.first ?? .zero, count: N) }
        var length: CGFloat = 0
        for i in 1..<raw.count { length += hypot(raw[i].x - raw[i - 1].x, raw[i].y - raw[i - 1].y) }
        let I = max(length / CGFloat(N - 1), 0.0001)
        var pts = [raw[0]], D: CGFloat = 0, src = raw, i = 1
        while i < src.count {
            let d = hypot(src[i].x - src[i - 1].x, src[i].y - src[i - 1].y)
            if D + d >= I, d > 0 {
                let t = (I - D) / d
                let q = P(x: src[i - 1].x + t * (src[i].x - src[i - 1].x), y: src[i - 1].y + t * (src[i].y - src[i - 1].y))
                pts.append(q); src.insert(q, at: i); D = 0
            } else { D += d }
            i += 1
        }
        while pts.count < N { pts.append(raw.last!) }
        pts = Array(pts.prefix(N))
        let b = box(pts)
        let sc = max(b.width, b.height, 0.0001)
        let cx = pts.reduce(0) { $0 + $1.x } / CGFloat(N), cy = pts.reduce(0) { $0 + $1.y } / CGFloat(N)
        return pts.map { P(x: ($0.x - cx) / sc, y: ($0.y - cy) / sc) }
    }

    // 内置写法（0~1 的格子里，y 向下），每个数字几种常见写法
    private static let builtIn: [(String, [[P]])] = {
        func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat, from a0: CGFloat = 0, to a1: CGFloat = 2 * .pi) -> [P] {
            stride(from: a0, through: a1, by: (a1 - a0) / 24).map { P(x: cx + rx * cos($0), y: cy + ry * sin($0)) }
        }
        func pl(_ xs: [(CGFloat, CGFloat)]) -> [P] { xs.map { P(x: $0.0, y: $0.1) } }
        return [
            ("0", [ellipse(0.5, 0.5, 0.35, 0.5)]),
            ("0", [ellipse(0.5, 0.5, 0.25, 0.5)]),
            ("1", [pl([(0.5, 0), (0.5, 1)])]),
            ("1", [pl([(0.25, 0.25), (0.55, 0), (0.55, 1)])]),
            ("2", [pl([(0.15, 0.25), (0.3, 0.05), (0.55, 0), (0.8, 0.12), (0.85, 0.32), (0.7, 0.55), (0.15, 1), (0.9, 1)])]),
            ("2", [pl([(0.2, 0.2), (0.5, 0), (0.85, 0.2), (0.15, 1), (0.9, 0.95)])]),
            ("3", [pl([(0.15, 0.12), (0.5, 0), (0.82, 0.15), (0.8, 0.35), (0.45, 0.5), (0.85, 0.65), (0.85, 0.88), (0.5, 1), (0.15, 0.9)])]),
            ("3", [pl([(0.15, 0), (0.85, 0), (0.45, 0.42), (0.85, 0.6), (0.8, 0.9), (0.45, 1), (0.15, 0.88)])]),
            ("4", [pl([(0.65, 1), (0.65, 0), (0.1, 0.7), (0.95, 0.7)])]),
            ("4", [pl([(0.35, 0), (0.12, 0.65), (0.9, 0.65)]), pl([(0.68, 0.3), (0.68, 1)])]),
            ("5", [pl([(0.85, 0), (0.25, 0), (0.18, 0.45), (0.55, 0.38), (0.85, 0.58), (0.82, 0.88), (0.45, 1), (0.15, 0.88)])]),
            ("5", [pl([(0.25, 0), (0.18, 0.45), (0.55, 0.38), (0.85, 0.58), (0.82, 0.88), (0.45, 1), (0.15, 0.88)]), pl([(0.25, 0), (0.85, 0)])]),
            ("6", [pl([(0.78, 0.05), (0.45, 0.08), (0.2, 0.4), (0.15, 0.75), (0.35, 1), (0.7, 0.95), (0.82, 0.72), (0.6, 0.52), (0.3, 0.55), (0.17, 0.7)])]),
            ("7", [pl([(0.1, 0), (0.9, 0), (0.4, 1)])]),
            ("7", [pl([(0.1, 0.1), (0.9, 0), (0.55, 0.5), (0.4, 1)]), pl([(0.35, 0.5), (0.75, 0.5)])]),
            ("8", [pl([(0.5, 0.48), (0.2, 0.3), (0.25, 0.08), (0.5, 0), (0.78, 0.08), (0.8, 0.3), (0.5, 0.48), (0.15, 0.7), (0.25, 0.95), (0.5, 1), (0.8, 0.92), (0.85, 0.7), (0.5, 0.48)])]),
            ("8", [ellipse(0.5, 0.25, 0.28, 0.25), ellipse(0.5, 0.74, 0.34, 0.26)]),
            ("9", [pl([(0.8, 0.28), (0.55, 0.45), (0.25, 0.38), (0.2, 0.15), (0.45, 0), (0.75, 0.05), (0.8, 0.3), (0.78, 0.65), (0.72, 1)])]),
            ("9", [ellipse(0.45, 0.25, 0.3, 0.25), pl([(0.75, 0.25), (0.7, 1)])]),
        ]
    }()

    private static func templates() -> [(String, [P], Bool)] {
        var out = builtIn.map { ($0.0, normalize($0.1.flatMap { $0 }), false) }
        let mine = (UserDefaults.standard.dictionary(forKey: key) as? [String: [[[Double]]]]) ?? [:]
        for (k, list) in mine { for t in list where t.count == N { out.append((k, t.map { P(x: $0[0], y: $0[1]) }, true)) } }
        return out
    }
}
