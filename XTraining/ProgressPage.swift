import SwiftUI
import Charts

// 进步页：按部位左右滑动看
struct ProgressPage: View {
    @EnvironmentObject var store: Store
    @State private var part = "胸"

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("部位", selection: $part.animation(.snappy)) {
                    ForEach(Parts.strength, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16).padding(.bottom, 8)
                TabView(selection: $part) {
                    ForEach(Parts.strength, id: \.self) { p in
                        PartProgress(part: p).tag(p)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("进步")
        }
    }
}

struct PartProgress: View {
    @EnvironmentObject var store: Store
    let part: String

    private var sessions: [Workout] { store.workouts.filter { $0.parts.contains(part) }.sorted { $0.date < $1.date } }
    private var month: String { String(Day.today.prefix(7)) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if sessions.isEmpty {
                    VStack(spacing: 8) {
                        Text("📈").font(.system(size: 44))
                        Text("还没练过\(part)").font(.headline)
                        Text("记几次训练，这里就会出现曲线").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 50).card()
                } else {
                    tiles
                    setsChart
                    ForEach(Array(charts.enumerated()), id: \.offset) { i, name in
                        LiftChart(part: part, index: i, name: name, options: names)
                    }
                    Button {
                        var list = charts; list.append(names.first ?? "__first")
                        store.liftCharts[part] = list
                    } label: { Label("再加一张动作重量图", systemImage: "plus.circle") }
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                    exerciseList
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 30)
            .frame(maxWidth: 720).frame(maxWidth: .infinity)
        }
    }

    // 这个部位练过的所有动作
    private var names: [String] {
        var seen = Set<String>(), out: [String] = []
        for w in sessions.reversed() { for x in w.exercises(of: part) where seen.insert(x.name).inserted { out.append(x.name) } }
        return out
    }
    private var charts: [String] {
        if let c = store.liftCharts[part], !c.isEmpty { return c }
        let def = part == "肩" ? "飞鸟" : part == "腿" ? "深蹲" : "__first"
        return [def]
    }

    private var tiles: some View {
        let m = sessions.filter { $0.date.hasPrefix(month) }
        let sets = m.reduce(0) { $0 + $1.exercises(of: part).reduce(0) { $0 + $1.sets.count } }
        let last = sessions.last.map { Day.ago($0.date) } ?? "—"
        return HStack {
            StatTile(value: "\(m.count)", label: "本月次数")
            StatTile(value: "\(sets)", label: "本月组数")
            StatTile(value: last, label: "上次")
        }
        .card()
    }

    // 每月平均每次练几组
    private var setsChart: some View {
        var byMonth: [String: (Int, Int)] = [:]
        for w in sessions {
            let k = String(w.date.prefix(7))
            let n = w.exercises(of: part).reduce(0) { $0 + $1.sets.count }
            let v = byMonth[k] ?? (0, 0)
            byMonth[k] = (v.0 + n, v.1 + 1)
        }
        let rows = byMonth.keys.sorted().suffix(8).map { k in Pt(id: k, v: Double(byMonth[k]!.0) / Double(max(1, byMonth[k]!.1))) }
        return VStack(alignment: .leading, spacing: 8) {
            Text("平均组数").font(.headline)
            Text("每次练\(part)平均几组，按月").font(.caption).foregroundStyle(.secondary)
            Chart(rows) { r in
                BarMark(x: .value("月", monthLabel(r.id)), y: .value("组", r.v))
                    .foregroundStyle(Parts.color(part).gradient)
                    .cornerRadius(6)
                    .annotation(position: .top) { Text(fmtNum(r.v)).font(.caption2).foregroundStyle(.secondary) }
            }
            .frame(height: 170)
        }
        .card()
    }

    // 每个动作：第一次 → 最近一次的最佳重量
    private var exerciseList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("每个动作的进步").font(.headline)
            ForEach(names, id: \.self) { n in
                let hist = sessions.compactMap { w in w.exercises(of: part).first { $0.name == n }.map { (w.date, $0.best) } }.filter { $0.1 > 0 }
                if let first = hist.first, let last = hist.last {
                    let pct = first.1 > 0 ? (last.1 - first.1) / first.1 * 100 : 0
                    let pr = hist.map { $0.1 }.max() ?? 0
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(n).font(.subheadline.bold())
                            Text("\(hist.count) 次 · 最佳 \(fmtNum(pr))kg").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(fmtNum(first.1)) → \(fmtNum(last.1))kg").font(.caption).monospacedDigit()
                        Text(pct >= 0 ? "+\(Int(pct.rounded()))%" : "\(Int(pct.rounded()))%")
                            .font(.caption.bold())
                            .foregroundStyle(pct > 0 ? Color.green : pct < 0 ? Color.orange : Color.secondary)
                            .frame(width: 48, alignment: .trailing)
                    }
                    Divider()
                }
            }
        }
        .card()
    }
}

func monthLabel(_ ym: String) -> String {
    let p = ym.split(separator: "-")
    return p.count == 2 ? "\(Int(p[1]) ?? 0)月" : ym
}

// 动作重量图：选一个动作，看每月最重多少，以及多久突破一次
struct LiftChart: View {
    @EnvironmentObject var store: Store
    let part: String
    let index: Int
    let name: String
    let options: [String]

    private var resolved: String {
        if name == "__first" { return options.first ?? "" }
        return options.first { $0 == name } ?? options.first { $0.contains(name) } ?? name
    }
    private var points: [(String, Double)] {
        store.workouts.filter { $0.parts.contains(part) }.sorted { $0.date < $1.date }.compactMap { w in
            let best = w.exercises.filter { $0.name == resolved }.map(\.best).max() ?? 0
            return best > 0 ? (w.date, best) : nil
        }
    }

    var body: some View {
        let pts = points
        var byMonth: [String: Double] = [:]
        for p in pts { byMonth[String(p.0.prefix(7)), default: 0] = max(byMonth[String(p.0.prefix(7))] ?? 0, p.1) }
        let rows = byMonth.keys.sorted().suffix(8).map { Pt(id: $0, v: byMonth[$0]!) }
        // 突破：比之前最重的更重
        var top = 0.0, breaks: [String] = []
        for p in pts { if p.1 > top { if top > 0 { breaks.append(p.0) }; top = p.1 } }
        let gaps = zip(breaks.dropFirst(), breaks).map { Day.between($1, $0) }
        let avg = gaps.isEmpty ? nil : Double(gaps.reduce(0, +)) / Double(gaps.count)
        let since = breaks.last.map { Day.between($0, Day.today) }

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("动作重量").font(.headline)
                Spacer()
                Menu {
                    ForEach(options, id: \.self) { n in Button(n) { set(n) } }
                    if index > 0 { Divider(); Button("删掉这张图", role: .destructive) { remove() } }
                } label: {
                    HStack(spacing: 4) { Text(resolved.isEmpty ? "选动作" : resolved); Image(systemName: "chevron.down") }
                        .font(.subheadline.bold())
                }
            }
            if rows.isEmpty {
                Text("还没有“\(resolved)”的重量记录").font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 20)
            } else {
                Chart(rows) { r in
                    BarMark(x: .value("月", monthLabel(r.id)), y: .value("kg", r.v))
                        .foregroundStyle(Brand.gradient)
                        .cornerRadius(6)
                        .annotation(position: .top) { Text(fmtNum(r.v)).font(.caption2).foregroundStyle(.secondary) }
                }
                .frame(height: 170)
                HStack {
                    StatTile(value: "\(breaks.count)", label: "突破次数")
                    StatTile(value: avg.map { "\(Int($0.rounded()))天" } ?? "—", label: "平均多久突破")
                    VStack(spacing: 2) {
                        Text(since.map { "\($0)天" } ?? "—").font(.title2.bold()).monospacedDigit()
                            .foregroundStyle((avg != nil && since != nil && Double(since!) > avg!) ? Color.orange : Color.primary)
                        Text("距上次突破").font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .card()
    }

    private func current() -> [String] {
        if let c = store.liftCharts[part], !c.isEmpty { return c }
        return [part == "肩" ? "飞鸟" : part == "腿" ? "深蹲" : "__first"]
    }
    private func set(_ n: String) {
        var c = current(); if index < c.count { c[index] = n }; store.liftCharts[part] = c
    }
    private func remove() {
        var c = current(); if index < c.count { c.remove(at: index) }; store.liftCharts[part] = c
    }
}

struct Pt: Identifiable {
    let id: String
    let v: Double
}
