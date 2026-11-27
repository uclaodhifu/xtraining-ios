import SwiftUI
import Charts

// 进步页：按部位左右滑动看
// 进步页上哪张图的长按弹框开着（同一时间只开一个，点空白处收起）
final class ChartPopup: ObservableObject {
    static let shared = ChartPopup()
    @Published var owner: String? = nil
}

struct ProgressPage: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var popup = ChartPopup.shared
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
                // 长按弹框开着时，点屏幕任意地方（包括空白处）都收起
                .overlay {
                    if popup.owner != nil {
                        Color.black.opacity(0.001).contentShape(Rectangle())
                            .onTapGesture { popup.owner = nil }
                            .gesture(DragGesture(minimumDistance: 8).onEnded { _ in popup.owner = nil })
                    }
                }
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
        let ss = sessions          // 只排一次序，下面几块都用它（以前每块各算一遍，滑动卡）
        let nm = names(ss)
        return ScrollView {
            VStack(spacing: 14) {
                YesterdayCard()   // 跟着页面一起滚走
                MuscleMapCard()   // 训练分布（从首页挪过来）
                if ss.isEmpty {
                    VStack(spacing: 8) {
                        Text("📈").font(.system(size: 44))
                        Text("还没练过\(part)").font(.headline)
                        Text("记几次训练，这里就会出现曲线").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 50).card()
                } else {
                    sessionStrip(ss)
                    tiles(ss)
                    SetsChart(part: part, rows: setRows(ss))
                    ForEach(Array(charts.enumerated()), id: \.offset) { i, name in
                        LiftChart(part: part, index: i, name: name, options: nm, sessions: ss)
                    }
                    Button {
                        var list = charts; list.append(nm.first ?? "__first")
                        store.liftCharts[part] = list
                    } label: { Label("再加一张目标重量图", systemImage: "plus.circle") }
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                    exerciseList(ss, nm)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 30)
            .frame(maxWidth: 720).frame(maxWidth: .infinity)
        }
        .sheet(item: $editing) { w in EntryView(workout: w) }
    }

    // 每次训练的日期框，左右滑，点开看那次练了什么
    @ViewBuilder private func sessionStrip(_ list: [Workout]) -> some View {
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
    private func names(_ ss: [Workout]) -> [String] {
        var seen = Set<String>(), out: [String] = []
        for w in ss.reversed() { for x in w.exercises(of: part) where seen.insert(x.name).inserted { out.append(x.name) } }
        return out
    }
    private var charts: [String] {
        if let c = store.liftCharts[part], !c.isEmpty { return c }
        let def = part == "肩" ? "飞鸟" : part == "腿" ? "深蹲" : "__first"
        return [def]
    }

    private func tiles(_ ss: [Workout]) -> some View {
        let m = ss.filter { $0.date.hasPrefix(month) }
        let sets = m.reduce(0) { $0 + $1.exercises(of: part).reduce(0) { $0 + $1.sets.count } }
        let last = ss.last.map { Day.ago($0.date) } ?? "—"
        return HStack {
            StatTile(value: "\(m.count)", label: "本月次数")
            StatTile(value: "\(sets)", label: "本月组数")
            StatTile(value: last, label: "上次")
        }
        .card()
    }

    // 每月平均每次练几组（固定最近 8 个月，没练的是 0）
    private func setRows(_ ss: [Workout]) -> [Pt] {
        var byMonth: [String: (Int, Int)] = [:]
        for w in ss {
            let k = String(w.date.prefix(7))
            let n = w.exercises(of: part).reduce(0) { $0 + $1.sets.count }
            let v = byMonth[k] ?? (0, 0)
            byMonth[k] = (v.0 + n, v.1 + 1)
        }
        let start = Day.date(String(Day.today.prefix(7)) + "-01")
        return (0..<8).reversed().map { back in
            let d = Calendar.current.date(byAdding: .month, value: -back, to: start) ?? start
            let k = String(Day.str(d).prefix(7))
            let v = byMonth[k] ?? (0, 0)
            return Pt(id: k, v: v.1 == 0 ? 0 : Double(v.0) / Double(v.1))
        }
    }

    // 每个动作：第一次 → 最近一次的最佳重量
    private func exerciseList(_ sessions: [Workout], _ names: [String]) -> some View {
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

// 目标重量图：给动作自己定一个目标重量，每次训练的最重一组都跟它比
struct LiftChart: View {
    @EnvironmentObject var store: Store
    let part: String
    let index: Int
    let name: String
    let options: [String]
    let sessions: [Workout]
    @AppStorage("xt.targets") private var targetsData = Data()   // { 动作名: 目标kg }
    @State private var sel: Int? = nil
    @State private var editing = false
    @State private var input = ""

    private var resolved: String {
        if name == "__first" { return options.first ?? "" }
        return options.first { $0 == name } ?? options.first { $0.contains(name) } ?? name
    }
    private var targets: [String: Double] { (try? JSONDecoder().decode([String: Double].self, from: targetsData)) ?? [:] }
    private func setTarget(_ v: Double?) {
        var t = targets; t[resolved] = v
        targetsData = (try? JSONEncoder().encode(t)) ?? targetsData
    }

    var body: some View {
        let ex = resolved
        let pts: [(date: String, best: Double)] = sessions.compactMap { w in
            let ws = w.exercises.filter { $0.name == ex }.flatMap(\.sets).map(\.weight).filter { $0 > 0 }
            return ws.max().map { (w.date, $0) }
        }
        let shown = Array(pts.suffix(8))
        let target = targets[ex]
        let accent = Color(hex: 0x0a84ff), good = Color(hex: 0x2f9e44)
        let hit = target.map { t in shown.filter { $0.best >= t }.count } ?? 0
        let bestEver = pts.map(\.best).max() ?? 0

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("目标重量").font(.title3.bold())
                Spacer()
                Menu {
                    ForEach(options, id: \.self) { n in Button(n) { set(n) } }
                    if index > 0 { Divider(); Button("删掉这张图", role: .destructive) { remove() } }
                } label: {
                    HStack(spacing: 4) { Text(ex.isEmpty ? "选动作" : ex); Image(systemName: "chevron.down") }.font(.subheadline.bold())
                }
            }
            if let latest = shown.last {
                let cur = sel.flatMap { $0 < shown.count ? shown[$0] : nil } ?? latest
                Text(verdict(cur.best, target, sel == nil ? "最近一次" : slashDate(cur.date))).font(.subheadline.bold())
                Divider()
                HStack(alignment: .top, spacing: 28) {
                    Button { input = target.map(fmtNum) ?? ""; editing = true } label: {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 3) { Text("目标").font(.caption); Image(systemName: "pencil").font(.caption2) }.foregroundStyle(.orange)
                            if let target { kg(target).foregroundStyle(.orange) } else { Text("点这里设").font(.title3.bold()).foregroundStyle(.orange).padding(.vertical, 4) }
                        }
                    }
                    .buttonStyle(.plain)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(sel != nil ? slashDate(cur.date) : (latest.date == Day.today ? "今天" : "最近一次")).font(.caption).foregroundStyle(accent)
                        kg(cur.best).foregroundStyle(target.map { cur.best >= $0 } == true ? good : accent)
                    }
                    Spacer()
                }
                let pad = 8 - shown.count
                let hi = sel ?? (shown.count - 1)
                Chart {
                    ForEach(Array(shown.enumerated()), id: \.offset) { i, p in
                        let ok = target.map { p.best >= $0 } == true
                        let base = ok ? good : accent
                        BarMark(x: .value("次", "\(i + pad)"), y: .value("最重", p.best), width: .ratio(0.45))
                            .foregroundStyle(i == hi ? base : base.opacity(sel == nil ? 0.5 : 0.25))
                            .cornerRadius(6)
                            .annotation(position: .top) {
                                Text(fmtNum(p.best)).font(.caption2.weight(i == hi ? .bold : .regular)).foregroundStyle(i == hi ? base : .secondary)
                            }
                    }
                    if let target {
                        RuleMark(y: .value("目标", target))
                            .foregroundStyle(Color.orange)
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 4]))
                            .annotation(position: .top, alignment: .leading) { Text("目标 \(fmtNum(target))").font(.caption2.bold()).foregroundStyle(.orange) }
                    }
                }
                .chartXScale(domain: (0..<8).map { "\($0)" })
                .chartXAxis {
                    AxisMarks { v in
                        AxisValueLabel {
                            if let s = v.as(String.self), let k = Int(s), k - pad >= 0, k - pad < shown.count {
                                Text(slashDate(shown[k - pad].date)).font(.caption2).foregroundStyle(k - pad == hi ? accent : Color.secondary)
                            }
                        }
                    }
                }
                .chartYAxis(.hidden)
                .chartYScale(domain: 0...(max(bestEver, target ?? 0) * 1.15 + 1))
                .chartOverlay { proxy in
                    GeometryReader { g in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .onTapGesture { loc in
                                guard let f = proxy.plotFrame, let s: String = proxy.value(atX: loc.x - g[f].origin.x), let k = Int(s) else { return }
                                let i = k - pad
                                var t = Transaction(); t.disablesAnimations = true
                                withTransaction(t) { sel = (i < 0 || i >= shown.count || sel == i) ? nil : i }
                                Haptic.tap()
                            }
                    }
                }
                .transaction { $0.animation = nil }
                .frame(height: 190)
                Divider()
                HStack {
                    StatTile(value: target == nil ? "—" : "\(hit)/\(shown.count)", label: "最近达标")
                    StatTile(value: fmtNum(bestEver) + "kg", label: "最好一次")
                    StatTile(value: target.map { t in latest.best >= t ? "已达标" : "差" + fmtNum(t - latest.best) + "kg" } ?? "—", label: "离目标")
                }
            } else {
                Text("还没有“\(ex)”的重量记录").font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 20)
            }
        }
        .card()
        .alert("\(ex) 的目标重量", isPresented: $editing) {
            TextField("比如 60", text: $input).keyboardType(.decimalPad)
            Button("保存") { if let v = Double(input.replacingOccurrences(of: ",", with: ".")), v > 0 { setTarget(v) } }
            if target != nil { Button("清除目标", role: .destructive) { setTarget(nil) } }
            Button("取消", role: .cancel) {}
        } message: { Text("每次训练的最重一组都会跟这个重量比") }
    }

    private func kg(_ v: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(fmtNum(v)).font(.system(size: 30, weight: .bold, design: .rounded))
            Text("kg").font(.subheadline.bold())
        }
    }
    private func verdict(_ v: Double, _ target: Double?, _ who: String) -> String {
        guard let target else { return "\(who) \(fmtNum(v))kg · 设个目标重量，每次都跟它比" }
        if v >= target { return v > target ? "\(who)超过目标 \(fmtNum(v - target))kg，可以加目标了 💪" : "\(who)刚好达到目标 ✓" }
        return "\(who)离目标还差 \(fmtNum(target - v))kg"
    }
    private func current() -> [String] {
        if let c = store.liftCharts[part], !c.isEmpty { return c }
        return [part == "肩" ? "飞鸟" : part == "腿" ? "深蹲" : "__first"]
    }
    private func set(_ n: String) {
        var c = current(); if index < c.count { c[index] = n }; store.liftCharts[part] = c
        sel = nil
    }
    private func remove() {
        var c = current(); if index < c.count { c.remove(at: index) }; store.liftCharts[part] = c
    }
}

// 平均组数柱状图：单独一个小视图，点柱子只重画这张图，颜色立刻变（不带动画，跟手）
struct SetsChart: View {
    let part: String
    let rows: [Pt]
    @State private var sel: String? = nil
    var body: some View {
        let blue = Color(hex: 0x0a84ff)
        VStack(alignment: .leading, spacing: 8) {
            Text("平均组数").font(.title3.bold())
            Text("每次练\(part)平均几组，按月").font(.caption).foregroundStyle(.secondary)
            Chart(rows) { r in
                let on = r.id == (sel ?? rows.last?.id)
                BarMark(x: .value("月", monthLabel(r.id)), y: .value("组", r.v), width: .ratio(0.45))
                    .foregroundStyle(on ? blue : (sel == nil ? blue.opacity(0.45) : Color.gray.opacity(0.35)))
                    .cornerRadius(6)
                    .annotation(position: .top) {
                        Text(r.v > 0 ? fmtNum(r.v) : "").font(.caption2.weight(on && sel != nil ? .bold : .regular))
                            .foregroundStyle(on && sel != nil ? blue : .secondary)
                    }
            }
            .chartOverlay { proxy in
                GeometryReader { g in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        // 点哪根就立刻亮哪根（不带动画；再点一次取消）
                        .onTapGesture { loc in
                            guard let f = proxy.plotFrame,
                                  let lab: String = proxy.value(atX: loc.x - g[f].origin.x),
                                  let r = rows.first(where: { monthLabel($0.id) == lab }) else { return }
                            var t = Transaction(); t.disablesAnimations = true
                            withTransaction(t) { sel = sel == r.id ? nil : r.id }
                            Haptic.tap()
                        }
                }
            }
            .transaction { $0.animation = nil }
            .frame(height: 170)
        }
        .card()
    }
}

struct Pt: Identifiable {
    let id: String
    let v: Double
}
