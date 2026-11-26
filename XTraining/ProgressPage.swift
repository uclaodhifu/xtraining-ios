import SwiftUI
import Charts

// 进步页：按部位左右滑动看
struct ProgressPage: View {
    @EnvironmentObject var store: Store
    @State private var part = "胸"

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                YesterdayCard().padding(.horizontal, 16).padding(.bottom, 12)
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
    @State private var picked: String? = nil
    @State private var showAll = false
    @State private var editing: Workout? = nil
    @State private var setSel: String? = nil   // 平均组数图点中的月份

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
                    sessionStrip
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
        .sheet(item: $editing) { w in EntryView(workout: w) }
    }

    // 每次训练的日期框，左右滑，点开看那次练了什么
    @ViewBuilder private var sessionStrip: some View {
        let list = sessions
        VStack(alignment: .leading, spacing: 10) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(list) { w in
                            let on = picked == w.id
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { picked = on ? nil : w.id }
                                Haptic.tap()
                            } label: {
                                VStack(spacing: 3) {
                                    Text(slashDate(w.date)).font(.headline).monospacedDigit()
                                    Text(weekdayCN(w.date)).font(.caption2).opacity(0.7)
                                }
                                .foregroundStyle(on ? Color.white : (w.date == Day.today ? Parts.color(part) : Color.primary))
                                .frame(minWidth: 60, minHeight: 56).padding(.horizontal, 4)
                                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(on ? AnyShapeStyle(Parts.color(part).gradient) : AnyShapeStyle(.regularMaterial)))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
                                .scaleEffect(on ? 1.06 : 1)
                            }
                            .buttonStyle(.plain)
                            .id(w.id)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onAppear { if let last = list.last { proxy.scrollTo(last.id, anchor: .trailing) } }
            }
            if let id = picked, let w = list.first(where: { $0.id == id }) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("\(Day.label(w.date)) · \(Day.ago(w.date))").font(.headline)
                        Spacer()
                        Button("修改") { editing = w }.font(.subheadline)
                    }
                    ForEach(w.exercises(of: part)) { x in
                        HStack(alignment: .firstTextBaseline) {
                            Text(x.name).font(.subheadline)
                            Spacer()
                            Text(setsText(x)).font(.caption.bold()).foregroundStyle(Parts.color(part)).lineLimit(1)
                        }
                    }
                    let others = w.exercises.filter { (Parts.of($0.name) ?? w.parts.first ?? "") != part }
                    if !others.isEmpty {
                        Text("同一天还练了：" + others.map(\.name).joined(separator: "、")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .card()
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
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
        // 固定显示最近 8 个月（没练的月份是 0）
        let start = Day.date(String(Day.today.prefix(7)) + "-01")
        let rows: [Pt] = (0..<8).reversed().map { back in
            let d = Calendar.current.date(byAdding: .month, value: -back, to: start) ?? start
            let k = String(Day.str(d).prefix(7))
            let v = byMonth[k] ?? (0, 0)
            return Pt(id: k, v: v.1 == 0 ? 0 : Double(v.0) / Double(v.1))
        }
        return VStack(alignment: .leading, spacing: 8) {
            Text("平均组数").font(.title3.bold())
            Text("每次练\(part)平均几组，按月").font(.caption).foregroundStyle(.secondary)
            Chart(rows) { r in
                let blue = Color(hex: 0x0a84ff)
                let on = r.id == (setSel ?? rows.last?.id)
                BarMark(x: .value("月", monthLabel(r.id)), y: .value("组", r.v), width: .ratio(0.45))
                    .foregroundStyle(on ? blue.gradient : (setSel == nil ? blue.opacity(0.45).gradient : Color.gray.opacity(0.35).gradient))
                    .cornerRadius(6)
                    .annotation(position: .top) {
                        Text(r.v > 0 ? fmtNum(r.v) : "").font(.caption2.weight(on && setSel != nil ? .bold : .regular))
                            .foregroundStyle(on && setSel != nil ? Color(hex: 0x0a84ff) : .secondary)
                    }
            }
            .chartOverlay { proxy in
                GeometryReader { g in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onTapGesture { loc in
                            guard let f = proxy.plotFrame else { return }
                            guard let lab: String = proxy.value(atX: loc.x - g[f].origin.x),
                                  let r = rows.first(where: { monthLabel($0.id) == lab }) else { return }
                            withAnimation(.snappy) { setSel = setSel == r.id ? nil : r.id }
                            Haptic.tap()
                        }
                }
            }
            .frame(height: 170)
        }
        .card()
    }

    // 每个动作：第一次 → 最近一次的最佳重量
    private var exerciseList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("每个动作的进步").font(.title3.bold())
            ForEach(showAll ? names : Array(names.prefix(3)), id: \.self) { n in
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
            if names.count > 3 {
                Button {
                    withAnimation(.snappy) { showAll.toggle() }
                } label: {
                    HStack {
                        Text(showAll ? "收起" : "查看全部 \(names.count) 个动作")
                        Spacer()
                        Image(systemName: "chevron.right").rotationEffect(.degrees(showAll ? 90 : 0))
                    }
                    .font(.subheadline)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .card()
    }
}

func weekdayCN(_ d: String) -> String {
    ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][Calendar.current.component(.weekday, from: Day.date(d)) - 1]
}
func slashDate(_ d: String) -> String {
    let p = d.split(separator: "-"); return p.count == 3 ? "\(Int(p[1]) ?? 0)/\(Int(p[2]) ?? 0)" : d
}
func monthCN(_ d: String) -> String {
    let p = d.split(separator: "-"); return p.count == 3 ? "\(Int(p[1]) ?? 0)月" : ""
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
    @State private var sel: Int? = nil   // 点中的柱子（在 shown 里的位置）

    private var resolved: String {
        if name == "__first" { return options.first ?? "" }
        return options.first { $0 == name } ?? options.first { $0.contains(name) } ?? name
    }
    // 每次训练这个动作的 最重一组 和 平均每组重量
    private var points: [(date: String, best: Double, mean: Double)] {
        store.workouts.filter { $0.parts.contains(part) }.sorted { $0.date < $1.date }.compactMap { w in
            let sets = w.exercises.filter { $0.name == resolved }.flatMap(\.sets).map(\.weight).filter { $0 > 0 }
            guard let best = sets.max() else { return nil }
            return (w.date, best, sets.reduce(0, +) / Double(sets.count))
        }
    }

    var body: some View {
        let pts = points
        let shown = Array(pts.suffix(8))
        let avgBest = shown.isEmpty ? 0 : shown.map(\.best).reduce(0, +) / Double(shown.count)
        let latest = shown.last
        let prev = shown.dropLast().last
        // 突破：比之前最重的更重
        var top = 0.0, breaks: [String] = []
        for p in pts { if p.best > top { if top > 0 { breaks.append(p.date) }; top = p.best } }
        let gaps = zip(breaks.dropFirst(), breaks).map { Day.between($1, $0) }
        let avg = gaps.isEmpty ? nil : Double(gaps.reduce(0, +)) / Double(gaps.count)
        let since = breaks.last.map { Day.between($0, Day.today) }
        let accent = Color(hex: 0x0a84ff)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("动作重量").font(.title3.bold())
                Spacer()
                Menu {
                    ForEach(options, id: \.self) { n in Button(n) { set(n) } }
                    if index > 0 { Divider(); Button("删掉这张图", role: .destructive) { remove() } }
                } label: {
                    HStack(spacing: 4) { Text(resolved.isEmpty ? "选动作" : resolved); Image(systemName: "chevron.down") }
                        .font(.subheadline.bold())
                }
            }
            if let latest {
                Text(verdict(latest.best, avgBest, prev?.best)).font(.subheadline.bold())
                Divider()
                HStack(alignment: .top, spacing: 28) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("平均").font(.caption).foregroundStyle(.secondary)
                        kg(avgBest).foregroundStyle(.secondary)
                    }
                    let cur = sel.flatMap { $0 < shown.count ? shown[$0] : nil } ?? latest
                    VStack(alignment: .leading, spacing: 0) {
                        Text(sel != nil ? slashDate(cur.date) : (latest.date == Day.today ? "今天" : "最近一次")).font(.caption).foregroundStyle(accent)
                        kg(cur.best).foregroundStyle(accent)
                    }
                    Spacer()
                }
                // 固定 8 个位置，柱子窄一点；点一根柱子，其他变灰
                let pad = 8 - shown.count
                let hi = sel ?? (shown.count - 1)
                Chart {
                    ForEach(Array(shown.enumerated()), id: \.offset) { i, p in
                        let on = i == hi
                        let c: Color = sel == nil ? (on ? accent : accent.opacity(0.5)) : (on ? accent : Color.gray.opacity(0.35))
                        BarMark(x: .value("次", "\(i + pad)"), y: .value("最重", p.best), width: .ratio(0.45))
                            .foregroundStyle(c.opacity(on ? 0.3 : 0.35))
                            .cornerRadius(6)
                        BarMark(x: .value("次", "\(i + pad)"), y: .value("平均", p.mean), width: .ratio(0.45))
                            .foregroundStyle(c)
                            .cornerRadius(6)
                            .annotation(position: .top) {
                                if on && sel != nil { Text(fmtNum(p.best)).font(.caption2.bold()).foregroundStyle(accent) }
                            }
                    }
                    RuleMark(y: .value("平均", avgBest))
                        .foregroundStyle(Color.gray.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .annotation(position: .top, alignment: .trailing) { Text("平均").font(.caption2).foregroundStyle(.secondary) }
                }
                .chartXScale(domain: (0..<8).map { "\($0)" })
                .chartXAxis {
                    AxisMarks { v in
                        AxisValueLabel {
                            if let s = v.as(String.self), let k = Int(s), k - pad >= 0, k - pad < shown.count {
                                Text(shortDate(shown[k - pad].date)).font(.caption2)
                                    .foregroundStyle(k - pad == hi ? accent : Color.secondary)
                            }
                        }
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { g in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .onTapGesture { loc in
                                guard let f = proxy.plotFrame else { return }
                                let x = loc.x - g[f].origin.x
                                guard let s: String = proxy.value(atX: x), let k = Int(s) else { return }
                                let i = k - pad
                                withAnimation(.snappy) { sel = (i < 0 || i >= shown.count || sel == i) ? nil : i }
                                Haptic.tap()
                            }
                    }
                }
                .chartYAxis(.hidden)
                .frame(height: 190)
                HStack(spacing: 14) {
                    HStack(spacing: 4) { Circle().fill(Color(hex: 0x0a84ff).opacity(0.25)).frame(width: 8); Text("最重一组") }
                    HStack(spacing: 4) { Circle().fill(Color(hex: 0x0a84ff).opacity(0.6)).frame(width: 8); Text("平均每组") }
                }
                .font(.caption2).foregroundStyle(.secondary)
                Divider()
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
            } else {
                Text("还没有“\(resolved)”的重量记录").font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 20)
            }
        }
        .card()
    }

    private func kg(_ v: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(fmtNum(v)).font(.system(size: 30, weight: .bold, design: .rounded))
                .contentTransition(.numericText()).animation(.snappy, value: v)
            Text("kg").font(.subheadline.bold())
        }
    }
    private func shortDate(_ d: String) -> String {
        let p = d.split(separator: "-"); return p.count == 3 ? "\(Int(p[1]) ?? 0)/\(Int(p[2]) ?? 0)" : d
    }
    private func verdict(_ last: Double, _ avg: Double, _ prev: Double?) -> String {
        let who = "最近一次"
        if let prev, last > prev { return "\(who)比上次重 \(fmtNum(last - prev))kg，进步了 💪" }
        if last > avg + 0.01 { return "\(who)比平均重 \(fmtNum(last - avg))kg，状态不错" }
        if abs(last - avg) <= 0.01 { return "\(who)和平均持平，继续保持" }
        return "\(who)比平均轻 \(fmtNum(avg - last))kg，下次加把劲"
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
