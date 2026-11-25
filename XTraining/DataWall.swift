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

// 简化的人体：每块肌肉一个圆角块，按部位上色
struct BodyFigure: View {
    let back: Bool
    let level: (String) -> Double

    // 坐标都按 100 × 200 来画
    private struct Block { let part: String?; let r: CGRect; let radius: CGFloat }
    private var blocks: [Block] {
        func b(_ p: String?, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ rad: CGFloat = 6) -> Block {
            Block(part: p, r: CGRect(x: x, y: y, width: w, height: h), radius: rad)
        }
        var out: [Block] = [
            b(nil, 40, 2, 20, 22, 10),          // 头
            b(nil, 45, 24, 10, 7, 3),           // 脖子
            b("肩", 17, 31, 17, 15, 8), b("肩", 66, 31, 17, 15, 8),
            b(nil, 9, 74, 11, 28, 5), b(nil, 80, 74, 11, 28, 5),      // 前臂
        ]
        if back {
            out += [
                b("背", 37, 30, 26, 11, 5),                              // 斜方肌
                b("背", 30, 42, 19, 32, 7), b("背", 51, 42, 19, 32, 7),   // 背阔肌
                b(nil, 38, 74, 24, 10, 4),                               // 下背
                b("手臂", 12, 47, 12, 26, 6), b("手臂", 76, 47, 12, 26, 6), // 三头
                b("腿", 33, 85, 16, 17, 7), b("腿", 51, 85, 16, 17, 7),   // 臀
                b("腿", 33, 104, 15, 40, 7), b("腿", 52, 104, 15, 40, 7), // 腘绳肌
                b("腿", 35, 146, 12, 38, 6), b("腿", 53, 146, 12, 38, 6), // 小腿
            ]
        } else {
            out += [
                b("胸", 32, 33, 17, 17, 7), b("胸", 51, 33, 17, 17, 7),   // 胸
                b(nil, 37, 52, 26, 30, 7),                               // 腹
                b("手臂", 12, 47, 12, 26, 6), b("手臂", 76, 47, 12, 26, 6), // 二头
                b(nil, 34, 84, 32, 14, 6),                               // 髋
                b("腿", 33, 99, 16, 45, 8), b("腿", 51, 99, 16, 45, 8),   // 股四头
                b("腿", 35, 146, 12, 38, 6), b("腿", 53, 146, 12, 38, 6), // 小腿
            ]
        }
        return out
    }

    var body: some View {
        Canvas { g, size in
            let sx = size.width / 100, sy = size.height / 200
            for bl in blocks {
                let r = CGRect(x: bl.r.minX * sx, y: bl.r.minY * sy, width: bl.r.width * sx, height: bl.r.height * sy)
                let path = Path(roundedRect: r, cornerRadius: bl.radius * min(sx, sy), style: .continuous)
                if let p = bl.part {
                    let v = level(p)
                    g.fill(path, with: .color(Color(.tertiarySystemFill)))
                    if v > 0 { g.fill(path, with: .color(Parts.color(p).opacity(0.25 + 0.75 * v))) }
                } else {
                    g.fill(path, with: .color(Color.primary.opacity(0.08)))
                }
            }
        }
    }
}
