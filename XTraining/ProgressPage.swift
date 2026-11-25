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
    @State private var picked: String? = nil
    @State private var showAll = false
    @State private var editing: Workout? = nil

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
                    logTable
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

    // 训练日志表：横着是每次训练的日期，竖着是动作，格子里是 重量×次数，比上次进步标绿色箭头
    @ViewBuilder private var logTable: some View {
        let cols = sessions
        let rows = Array(names.prefix(10))
        let lineH: CGFloat = 15
        let heights: [CGFloat] = rows.map { n in
            let m = cols.map { w in w.exercises(of: part).first { $0.name == n }?.sets.count ?? 0 }.max() ?? 1
            return CGFloat(max(1, m)) * lineH + 14
        }
        let nameW: CGFloat = 78, colW: CGFloat = 70, headH: CGFloat = 30
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("训练日志").font(.headline)
                Spacer()
                HStack(spacing: 3) { Image(systemName: "arrow.up").foregroundStyle(.green); Text("比上次进步") }
                    .font(.caption2).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("动作").font(.caption.bold()).foregroundStyle(.secondary)
                        .frame(width: nameW, height: headH, alignment: .leading)
                    ForEach(rows.indices, id: \.self) { i in
                        Text(rows[i]).font(.caption.bold()).lineLimit(2).minimumScaleFactor(0.7)
                            .frame(width: nameW, height: heights[i], alignment: .leading)
                            .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1) }
                    }
                }
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 0) {
                            ForEach(Array(cols.enumerated()), id: \.element.id) { ci, w in
                                VStack(spacing: 0) {
                                    Text(slashDate(w.date)).font(.caption.bold()).monospacedDigit()
                                        .foregroundStyle(picked == w.id ? Parts.color(part) : Color.primary)
                                        .frame(width: colW, height: headH)
                                    ForEach(rows.indices, id: \.self) { i in
                                        logCell(rows[i], cols, ci, lineH)
                                            .frame(width: colW, height: heights[i])
                                            .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1) }
                                    }
                                }
                                .overlay(alignment: .leading) { Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1) }
                                .background(picked == w.id ? Parts.color(part).opacity(0.08) : Color.clear)
                                .contentShape(Rectangle())
                                .onTapGesture { withAnimation(.snappy) { picked = picked == w.id ? nil : w.id } }
                                .id(w.id)
                            }
                        }
                    }
                    .onAppear { if let last = cols.last { proxy.scrollTo(last.id, anchor: .trailing) } }
                }
            }
            if names.count > rows.count {
                Text("只列了最近练的 \(rows.count) 个动作").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .card()
    }

    @ViewBuilder private func logCell(_ name: String, _ cols: [Workout], _ ci: Int, _ lineH: CGFloat) -> some View {
        if let x = cols[ci].exercises(of: part).first(where: { $0.name == name }) {
            let prev = cols[..<ci].reversed().lazy.compactMap { $0.exercises(of: self.part).first { $0.name == name } }.first
            let up = prev.map { better(x, than: $0) } ?? false
            VStack(spacing: 0) {
                ForEach(x.sets) { s in
                    Text(s.w.isEmpty ? (s.r.isEmpty ? "—" : "\(s.r)次") : (s.r.isEmpty ? s.w : "\(s.w)×\(s.r)"))
                        .font(.system(size: 11, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                        .frame(height: lineH)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topTrailing) {
                if up { Image(systemName: "arrow.up").font(.system(size: 9, weight: .heavy)).foregroundStyle(.green).padding(3) }
            }
            .foregroundStyle(up ? Color.green : Color.primary)
        } else {
            Color.clear
        }
    }

    // 进步：最重的一组更重，或者同样重量做了更多次
    private func better(_ a: Exercise, than b: Exercise) -> Bool {
        let ab = a.best, bb = b.best
        if ab > bb { return true }
        if ab == bb, ab > 0 {
            let ar = a.sets.filter { $0.weight == ab }.map(\.reps).max() ?? 0
            let br = b.sets.filter { $0.weight == bb }.map(\.reps).max() ?? 0
            return ar > br
        }
        return false
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
        let accent = Color.orange

        return VStack(alignment: .leading, spacing: 10) {
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
            if let latest {
                Text(verdict(latest.best, avgBest, prev?.best)).font(.subheadline.bold())
                Divider()
                HStack(alignment: .top, spacing: 28) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("平均").font(.caption).foregroundStyle(.secondary)
                        kg(avgBest).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(latest.date == Day.today ? "今天" : "最近一次").font(.caption).foregroundStyle(accent)
                        kg(latest.best).foregroundStyle(accent)
                    }
                    Spacer()
                }
                Chart {
                    ForEach(Array(shown.enumerated()), id: \.offset) { i, p in
                        let last = i == shown.count - 1
                        BarMark(x: .value("次", "\(i)"), y: .value("最重", p.best), width: .ratio(0.62))
                            .foregroundStyle(last ? accent.opacity(0.3) : Color.gray.opacity(0.22))
                            .cornerRadius(7)
                        BarMark(x: .value("次", "\(i)"), y: .value("平均", p.mean), width: .ratio(0.62))
                            .foregroundStyle(last ? accent : Color.gray.opacity(0.55))
                            .cornerRadius(7)
                    }
                    RuleMark(y: .value("平均", avgBest))
                        .foregroundStyle(Color.gray.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .annotation(position: .top, alignment: .trailing) { Text("平均").font(.caption2).foregroundStyle(.secondary) }
                }
                .chartXAxis {
                    AxisMarks { v in
                        AxisValueLabel {
                            if let s = v.as(String.self), let i = Int(s), i < shown.count {
                                Text(shortDate(shown[i].date)).font(.caption2)
                                    .foregroundStyle(i == shown.count - 1 ? accent : Color.secondary)
                            }
                        }
                    }
                }
                .chartYAxis(.hidden)
                .frame(height: 190)
                HStack(spacing: 14) {
                    HStack(spacing: 4) { Circle().fill(Color.gray.opacity(0.25)).frame(width: 8); Text("最重一组") }
                    HStack(spacing: 4) { Circle().fill(Color.gray.opacity(0.6)).frame(width: 8); Text("平均每组") }
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
