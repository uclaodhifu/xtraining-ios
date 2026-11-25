import SwiftUI
import Charts

// MARK: 首页“身体数据”卡片墙：两列小方块 + 肌肉分布图
struct DataWall: View {
    @EnvironmentObject var store: Store
    var onWeight: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("身体数据").font(.title3.bold())
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                Button(action: onWeight) { WeightTile() }.buttonStyle(PressScale())
                VolumeTile()
                PRTile()
                StreakTile()
            }
            MuscleMapCard()
        }
    }
}

// 小方块的外壳
struct Tile<Content: View>: View {
    let title: String
    let icon: String
    var tint: Color = Brand.pink
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon).font(.caption.bold()).foregroundStyle(tint)
            content
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
        .card()
    }
}

// 体重 + 小折线
struct WeightTile: View {
    @EnvironmentObject var store: Store
    var body: some View {
        let rows = Array(store.weights.suffix(14))
        Tile(title: "体重", icon: "scalemass.fill", tint: Color(hex: 0x30d158)) {
            if let last = rows.last {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(fmtNum(last.kg)).font(.system(size: 26, weight: .heavy, design: .rounded)).monospacedDigit()
                    Text("kg").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if rows.count > 1, let first = rows.first {
                        let d = last.kg - first.kg
                        Text((d > 0 ? "+" : "") + fmtNum((d * 10).rounded() / 10)).font(.caption.bold()).monospacedDigit()
                            .foregroundStyle(d > 0 ? Color.orange : Color.green)
                    }
                }
                .foregroundStyle(Color.primary)
                if rows.count > 1 {
                    let lo = (rows.map(\.kg).min() ?? 0) - 0.5, hi = (rows.map(\.kg).max() ?? 0) + 0.5
                    Chart(rows) { r in
                        LineMark(x: .value("d", r.date), y: .value("kg", r.kg))
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(Color(hex: 0x30d158))
                        AreaMark(x: .value("d", r.date), yStart: .value("lo", lo), yEnd: .value("kg", r.kg))
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(LinearGradient(colors: [Color(hex: 0x30d158).opacity(0.3), .clear], startPoint: .top, endPoint: .bottom))
                    }
                    .chartYScale(domain: lo...hi)
                    .chartXAxis(.hidden).chartYAxis(.hidden)
                    .frame(height: 34)
                }
            } else {
                Text("—").font(.system(size: 26, weight: .heavy, design: .rounded)).foregroundStyle(Color.primary)
                Text("点一下记体重").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

// 本周训练容量（重量 × 次数），和上周比
struct VolumeTile: View {
    @EnvironmentObject var store: Store
    var body: some View {
        let cal = Calendar(identifier: .iso8601)
        let start = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        let mon = Day.str(start), lastMon = Day.add(mon, -7)
        let elapsed = max(0, Day.between(mon, Day.today))
        let this = store.workouts.filter { $0.date >= mon }.reduce(0) { $0 + $1.volume }
        // 上周同一时间段，比较才公平
        let prev = store.workouts.filter { $0.date >= lastMon && $0.date <= Day.add(lastMon, elapsed) }.reduce(0) { $0 + $1.volume }
        // 每天的柱子
        let days = (0..<7).map { i -> Double in
            let d = Day.add(mon, i); return store.workouts.filter { $0.date == d }.reduce(0) { $0 + $1.volume }
        }
        let top = max(days.max() ?? 0, 1)
        Tile(title: "本周训练容量", icon: "flame.fill", tint: .orange) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(this >= 10000 ? fmtNum((this / 100).rounded() / 10) : fmtNum(this))
                    .font(.system(size: 26, weight: .heavy, design: .rounded)).monospacedDigit()
                Text(this >= 10000 ? "吨" : "kg").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if prev > 0 {
                    let pct = Int(((this - prev) / prev * 100).rounded())
                    Text((pct > 0 ? "+" : "") + "\(pct)%").font(.caption.bold()).monospacedDigit()
                        .foregroundStyle(pct >= 0 ? Color.green : Color.red)
                }
            }
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(0..<7, id: \.self) { i in
                    let isToday = Day.add(mon, i) == Day.today
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(isToday ? Color.orange : Color.orange.opacity(days[i] > 0 ? 0.45 : 0.12))
                        .frame(height: max(4, 30 * days[i] / top))
                }
            }
            .frame(height: 30, alignment: .bottom)
            Text("近 7 天 \(store.sets7) 组").font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// 个人纪录：最近一次破纪录的动作
struct PRTile: View {
    @EnvironmentObject var store: Store
    private struct PR { let name: String; let kg: Double; let date: String; let gain: Double }
    private var latest: PR? {
        var best: [String: Double] = [:]
        var last: PR? = nil
        for w in store.workouts.sorted(by: { $0.date < $1.date }) {
            for x in w.exercises where !x.isCardio && x.best > 0 {
                let old = best[x.name]
                if old == nil || x.best > old! {
                    if let o = old { last = PR(name: x.name, kg: x.best, date: w.date, gain: x.best - o) }
                    best[x.name] = x.best
                }
            }
        }
        if last == nil, let m = best.max(by: { $0.value < $1.value }) { return PR(name: m.key, kg: m.value, date: "", gain: 0) }
        return last
    }
    var body: some View {
        Tile(title: "个人纪录", icon: "trophy.fill", tint: Color(hex: 0xffcc00)) {
            if let p = latest {
                Text(p.name).font(.subheadline.bold()).lineLimit(1).foregroundStyle(Color.primary)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(fmtNum(p.kg)).font(.system(size: 26, weight: .heavy, design: .rounded)).monospacedDigit()
                    Text("kg").font(.caption).foregroundStyle(.secondary)
                    if p.gain > 0 {
                        Text("+\(fmtNum(p.gain))").font(.caption.bold()).foregroundStyle(.green)
                    }
                }
                Text(p.date.isEmpty ? "目前最重" : "\(slashDate(p.date)) 破纪录").font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("—").font(.system(size: 26, weight: .heavy, design: .rounded))
                Text("练几次就有了").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

// 连续天数 + 本周次数
struct StreakTile: View {
    @EnvironmentObject var store: Store
    var body: some View {
        Tile(title: "坚持", icon: "bolt.heart.fill", tint: Color(hex: 0xff375f)) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(store.streak)").font(.system(size: 26, weight: .heavy, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText())
                Text("天连续").font(.caption).foregroundStyle(.secondary)
            }
            // 本周 7 个点，练了的点亮
            let cal = Calendar(identifier: .iso8601)
            let mon = Day.str(cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date())
            let days = Set(store.workouts.map(\.date))
            HStack(spacing: 5) {
                ForEach(0..<7, id: \.self) { i in
                    let d = Day.add(mon, i)
                    VStack(spacing: 3) {
                        Circle().fill(days.contains(d) ? Color(hex: 0xff375f) : Color(.tertiarySystemFill))
                            .frame(width: 13, height: 13)
                            .overlay { if d == Day.today { Circle().strokeBorder(Color.primary.opacity(0.5), lineWidth: 1.5) } }
                        Text(["一", "二", "三", "四", "五", "六", "日"][i]).font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
            }
            Text("本周练了 \(store.weekCount) 天").font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: 肌肉分布图：人体正面 + 背面，近 14 天组数越多颜色越深
struct MuscleMapCard: View {
    @EnvironmentObject var store: Store
    @State private var range = 14

    private var sets: [String: Int] {
        var out: [String: Int] = [:]
        for w in store.workouts where Day.between(w.date, Day.today) < range {
            for x in w.exercises where !x.isCardio {
                let p = Parts.of(x.name) ?? w.parts.first { $0 != "有氧" } ?? ""
                out[p, default: 0] += x.sets.count
            }
        }
        return out
    }

    var body: some View {
        let s = sets
        let top = max(s.values.max() ?? 0, 1)
        let level: (String) -> Double = { p in Double(s[p] ?? 0) / Double(top) }
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("训练分布", systemImage: "figure.strengthtraining.traditional").font(.caption.bold()).foregroundStyle(Brand.pink)
                Spacer()
                Picker("", selection: $range.animation(.snappy)) {
                    Text("2 周").tag(14); Text("1 月").tag(30)
                }
                .pickerStyle(.segmented).frame(width: 120)
            }
            HStack(alignment: .center, spacing: 6) {
                VStack(spacing: 4) {
                    BodyFigure(back: false, level: level).frame(width: 78, height: 156)
                    Text("正面").font(.caption2).foregroundStyle(.secondary)
                }
                VStack(spacing: 4) {
                    BodyFigure(back: true, level: level).frame(width: 78, height: 156)
                    Text("背面").font(.caption2).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Parts.strength, id: \.self) { p in
                        let n = s[p] ?? 0
                        HStack(spacing: 6) {
                            Text(p).font(.caption.bold()).frame(width: 30, alignment: .leading)
                            GeometryReader { g in
                                Capsule().fill(Color(.tertiarySystemFill))
                                    .overlay(alignment: .leading) {
                                        Capsule().fill(Parts.color(p)).frame(width: max(n > 0 ? 6 : 0, g.size.width * Double(n) / Double(top)))
                                    }
                            }
                            .frame(height: 8)
                            Text("\(n)").font(.caption2.bold()).monospacedDigit().frame(width: 24, alignment: .trailing)
                        }
                    }
                    Text(tip(s)).font(.caption2).foregroundStyle(.secondary).padding(.top, 2)
                }
                .padding(.leading, 6)
            }
        }
        .card()
    }

    // 一句话：哪个练得多、哪个落下了
    private func tip(_ s: [String: Int]) -> String {
        let total = s.values.reduce(0, +)
        if total == 0 { return "这段时间还没有力量训练" }
        let most = Parts.strength.max { (s[$0] ?? 0) < (s[$1] ?? 0) } ?? ""
        let least = Parts.strength.min { (s[$0] ?? 0) < (s[$1] ?? 0) } ?? ""
        if (s[least] ?? 0) == 0 { return "\(most)练得最多，\(least)还没练" }
        return "\(most)练得最多，\(least)练得最少"
    }
}

// 人体肌肉图：每块肌肉一条路径（坐标按 100 × 200），按部位上色
struct BodyFigure: View {
    let back: Bool
    let level: (String) -> Double

    static let front: [(String?, String)] = [
        (nil, "M 50,3 C 55,3 58,7 58,13 C 58,19 55,23 50,23 C 45,23 42,19 42,13 C 42,7 45,3 50,3 Z"),
        (nil, "M 20,72 C 23,72 26,73 27,75 C 25,82 22,90 19,97 C 17,98 15,98 14,97 C 15,88 17,80 20,72 Z"),
        (nil, "M 80,72 C 77,72 74,73 73,75 C 75,82 78,90 81,97 C 83,98 85,98 86,97 C 85,88 83,80 80,72 Z"),
        (nil, "M 37,186 C 40,185 43,185 45,186 L 46,192 C 42,193 38,193 35,192 Z"),
        (nil, "M 63,186 C 60,185 57,185 55,186 L 54,192 C 58,193 62,193 65,192 Z"),
        (nil, "M 46,23 L 54,23 L 56,31 L 44,31 Z"),
        ("肩", "M 37,31 C 29,29 21,33 20,41 C 19,46 20,50 22,53 C 25,46 30,41 38,37 Z"),
        ("肩", "M 63,31 C 71,29 79,33 80,41 C 81,46 80,50 78,53 C 75,46 70,41 62,37 Z"),
        ("胸", "M 49,34 C 44,33 40,35 38,38 C 34,42 33,48 34,53 C 38,57 44,57 49,55 Z"),
        ("胸", "M 51,34 C 56,33 60,35 62,38 C 66,42 67,48 66,53 C 62,57 56,57 51,55 Z"),
        ("手臂", "M 21,55 C 23,51 27,49 31,51 C 32,58 30,65 27,70 C 24,71 22,70 21,68 C 20,63 20,59 21,55 Z"),
        ("手臂", "M 79,55 C 77,51 73,49 69,51 C 68,58 70,65 73,70 C 76,71 78,70 79,68 C 80,63 80,59 79,55 Z"),
        (nil, "M 34,57 C 36,58 38,60 39,62 L 40,86 C 37,84 35,80 35,76 C 34,70 34,63 34,57 Z"),
        (nil, "M 66,57 C 64,58 62,60 61,62 L 60,86 C 63,84 65,80 65,76 C 66,70 66,63 66,57 Z"),
        (nil, "M 41,58 C 44,58 47,58 49,58 L 49,66 L 41,66 Z"),
        (nil, "M 59,58 C 56,58 53,58 51,58 L 51,66 L 59,66 Z"),
        (nil, "M 41,68 L 49,68 L 49,76 L 41,76 Z"),
        (nil, "M 59,68 L 51,68 L 51,76 L 59,76 Z"),
        (nil, "M 41,78 L 49,78 L 49,90 C 46,89 43,87 41,85 Z"),
        (nil, "M 59,78 L 51,78 L 51,90 C 54,89 57,87 59,85 Z"),
        ("腿", "M 35,92 C 40,93 46,97 48,103 C 49,113 48,125 46,135 C 44,140 41,142 38,141 C 35,135 33,125 33,113 C 33,105 33,98 35,92 Z"),
        ("腿", "M 65,92 C 60,93 54,97 52,103 C 51,113 52,125 54,135 C 56,140 59,142 62,141 C 65,135 67,125 67,113 C 67,105 67,98 65,92 Z"),
        ("腿", "M 36,148 C 39,146 43,146 45,148 C 46,158 45,170 44,180 C 42,184 39,184 38,181 C 36,170 35,158 36,148 Z"),
        ("腿", "M 64,148 C 61,146 57,146 55,148 C 54,158 55,170 56,180 C 58,184 61,184 62,181 C 64,170 65,158 64,148 Z"),
    ]
    static let backSide: [(String?, String)] = [
        (nil, "M 50,3 C 55,3 58,7 58,13 C 58,19 55,23 50,23 C 45,23 42,19 42,13 C 42,7 45,3 50,3 Z"),
        (nil, "M 20,72 C 23,72 26,73 27,75 C 25,82 22,90 19,97 C 17,98 15,98 14,97 C 15,88 17,80 20,72 Z"),
        (nil, "M 80,72 C 77,72 74,73 73,75 C 75,82 78,90 81,97 C 83,98 85,98 86,97 C 85,88 83,80 80,72 Z"),
        (nil, "M 37,186 C 40,185 43,185 45,186 L 46,192 C 42,193 38,193 35,192 Z"),
        (nil, "M 63,186 C 60,185 57,185 55,186 L 54,192 C 58,193 62,193 65,192 Z"),
        ("背", "M 50,24 C 47,28 42,31 37,33 C 42,36 47,42 50,50 C 53,42 58,36 63,33 C 58,31 53,28 50,24 Z"),
        ("肩", "M 36,34 C 28,32 21,35 20,43 C 19,47 20,51 22,53 C 25,46 30,41 36,38 Z"),
        ("肩", "M 64,34 C 72,32 79,35 80,43 C 81,47 80,51 78,53 C 75,46 70,41 64,38 Z"),
        ("背", "M 48,51 C 44,45 39,40 35,40 C 32,46 32,56 34,64 C 38,72 43,78 48,82 Z"),
        ("背", "M 52,51 C 56,45 61,40 65,40 C 68,46 68,56 66,64 C 62,72 57,78 52,82 Z"),
        ("手臂", "M 21,55 C 23,51 27,49 31,51 C 32,58 30,65 27,70 C 24,71 22,70 21,68 C 20,63 20,59 21,55 Z"),
        ("手臂", "M 79,55 C 77,51 73,49 69,51 C 68,58 70,65 73,70 C 76,71 78,70 79,68 C 80,63 80,59 79,55 Z"),
        (nil, "M 49,84 C 45,83 41,81 38,79 L 38,86 C 42,88 46,88 49,88 Z"),
        (nil, "M 51,84 C 55,83 59,81 62,79 L 62,86 C 58,88 54,88 51,88 Z"),
        ("腿", "M 49,90 C 43,88 37,89 34,93 C 32,99 33,105 37,108 C 42,110 46,109 49,106 Z"),
        ("腿", "M 51,90 C 57,88 63,89 66,93 C 68,99 67,105 63,108 C 58,110 54,109 51,106 Z"),
        ("腿", "M 35,111 C 40,112 45,112 48,111 C 48,121 47,131 45,140 C 43,144 39,144 37,141 C 35,132 34,121 35,111 Z"),
        ("腿", "M 65,111 C 60,112 55,112 52,111 C 52,121 53,131 55,140 C 57,144 61,144 63,141 C 65,132 66,121 65,111 Z"),
        ("腿", "M 36,148 C 39,145 43,145 45,148 C 47,156 46,166 44,176 C 42,181 39,181 37,177 C 35,168 34,157 36,148 Z"),
        ("腿", "M 64,148 C 61,145 57,145 55,148 C 53,156 54,166 56,176 C 58,181 61,181 63,177 C 65,168 66,157 64,148 Z"),
    ]
    // 解析简单的 SVG 路径（M / L / C / Z）
    static func path(_ d: String, sx: CGFloat, sy: CGFloat) -> Path {
        var p = Path(); var nums: [CGPoint] = []; var cmd = ""
        func flush() {
            switch cmd {
            case "M": if let a = nums.first { p.move(to: a) }
            case "L": nums.forEach { p.addLine(to: $0) }
            case "C": stride(from: 0, to: nums.count - 2, by: 3).forEach { i in p.addCurve(to: nums[i + 2], control1: nums[i], control2: nums[i + 1]) }
            default: break
            }
            nums = []
        }
        for t in d.split(separator: " ") {
            if t.first?.isLetter == true {
                flush(); cmd = String(t)
                if cmd == "Z" { p.closeSubpath() }
            } else {
                let xy = t.split(separator: ",").compactMap { Double($0) }
                if xy.count == 2 { nums.append(CGPoint(x: xy[0] * sx, y: xy[1] * sy)) }
            }
        }
        flush()
        return p
    }

    var body: some View {
        Canvas { g, size in
            let sx = size.width / 100, sy = size.height / 200
            for (part, d) in back ? Self.backSide : Self.front {
                let path = Self.path(d, sx: sx, sy: sy)
                if let p = part {
                    let v = level(p)
                    g.fill(path, with: .color(Color.gray.opacity(0.18)))
                    if v > 0 { g.fill(path, with: .color(Parts.color(p).opacity(0.25 + 0.75 * v))) }
                } else {
                    g.fill(path, with: .color(Color.primary.opacity(0.08)))
                }
            }
        }
    }
}
