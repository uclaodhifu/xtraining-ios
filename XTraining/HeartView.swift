import SwiftUI
import Charts

// MARK: - 心率计算

enum HRMath {
    // 最大心率：取见过的最高心率，至少按 180 算
    static var maxHR: Double {
        get { max(180, UserDefaults.standard.double(forKey: "xt.hrMax")) }
    }
    static func see(_ pts: [HRPoint]) {
        if let m = pts.map(\.v).max(), Double(m) > UserDefaults.standard.double(forKey: "xt.hrMax"), m < 225 {
            UserDefaults.standard.set(Double(m), forKey: "xt.hrMax")
        }
    }
    static func merge(_ a: [HRPoint], _ b: [HRPoint]) -> [HRPoint] {
        var out: [HRPoint] = []
        for p in (a + b).sorted(by: { $0.t < $1.t }) {
            if let l = out.last, p.t - l.t < 1 { continue }
            out.append(p)
        }
        return out
    }
    // 离 t 最近的一条（within 秒以内）
    static func at(_ pts: [HRPoint], _ t: Double, within: Double = 15) -> Int? {
        guard let p = pts.min(by: { abs($0.t - t) < abs($1.t - t) }), abs(p.t - t) <= within else { return nil }
        return p.v
    }
    static func peak(_ pts: [HRPoint], _ a: Double, _ b: Double) -> Int? {
        pts.filter { $0.t >= a && $0.t <= b }.map(\.v).max()
    }
    static func zone(_ v: Int) -> Int {
        let p = Double(v) / maxHR
        return p >= 0.9 ? 4 : p >= 0.8 ? 3 : p >= 0.7 ? 2 : p >= 0.6 ? 1 : 0
    }
    // 心率负荷：按每段时间所在心率区间加权（越接近最大心率权重越高），单位≈分钟
    static func load(_ pts: [HRPoint]) -> Double {
        guard pts.count > 1 else { return 0 }
        var sum = 0.0
        for i in 0..<(pts.count - 1) {
            let dt = min(pts[i + 1].t - pts[i].t, 60) / 60
            let p = Double(pts[i].v) / maxHR
            let w: Double = p >= 0.9 ? 5 : p >= 0.8 ? 4 : p >= 0.7 ? 3 : p >= 0.6 ? 2 : p >= 0.5 ? 1 : 0
            sum += dt * w
        }
        return sum
    }
    // 5 个区间各占多少时间
    static func zones(_ pts: [HRPoint]) -> [Double] {
        var z = [Double](repeating: 0, count: 5)
        guard pts.count > 1 else { return z }
        for i in 0..<(pts.count - 1) { z[zone(pts[i].v)] += min(pts[i + 1].t - pts[i].t, 60) }
        let total = z.reduce(0, +)
        return total > 0 ? z.map { $0 / total } : z
    }
}

// 一天训练的心率：时间范围、心率点、组间休息
struct DayHR {
    var day: String
    var start: Double
    var end: Double
    var pts: [HRPoint]
    var rests: [RestMark]

    @MainActor static func load(_ day: String) async -> DayHR? {
        let rests = HRLog.rests(day)
        var a: Double, b: Double
        if let f = rests.first, let l = rests.last {
            a = f.t - 240
            b = (l.end ?? l.t + 120) + 180
        } else {
            let d0 = Calendar.current.startOfDay(for: Day.date(day))
            let spans = await Health.shared.workoutSpans(d0, d0.addingTimeInterval(86400))
            let use = spans.filter { $0.2 == "力量训练" }.ifEmpty(spans)
            guard let f = use.first, let l = use.last else {
                let local = HRLog.points(day)
                guard let f = local.first, let l = local.last, l.t - f.t > 300 else { return nil }
                return DayHR(day: day, start: f.t, end: l.t, pts: local, rests: [])
            }
            a = f.0.timeIntervalSince1970; b = l.1.timeIntervalSince1970
        }
        let local = HRLog.points(day).filter { $0.t >= a && $0.t <= b }
        let hk = await Health.shared.heart(Date(timeIntervalSince1970: a), Date(timeIntervalSince1970: b))
        let pts = HRMath.merge(local, hk)
        guard pts.count >= 5 else { return nil }
        HRMath.see(pts)
        return DayHR(day: day, start: a, end: b, pts: pts, rests: rests)
    }

    // 每组练完 1 分钟内心率掉了多少
    var drops: [Int] {
        rests.compactMap { r in
            guard (r.end ?? r.t + 90) - r.t >= 55,
                  let p = HRMath.peak(pts, r.t - 30, r.t + 10),
                  let after = HRMath.at(pts, r.t + 60, within: 12), p > after else { return nil }
            return p - after
        }
    }
}

extension Array {
    func ifEmpty(_ other: [Element]) -> [Element] { isEmpty ? other : self }
}

// MARK: - 「我」页：心率档案

// 「我」→ 组间心率：单独一页（用 ScrollView，不放进列表）
struct HeartPage: View {
    var body: some View {
        ScrollView {
            HeartCard()
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
                .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("组间心率")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct HeartCard: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var health = Health.shared
    // 不观察 HeartLive：它在训练时和训练后 10 分钟内每秒都在更新心率，
    // 这张卡在「我」页的列表里，每秒重算会让列表反复重新排版，保存训练/切页时 iOS 判定排版死循环直接闪退（第 49 版）
    @AppStorage("xt.hrBLE") private var bleOn = false
    @AppStorage("xt.hrSession2") private var sessionWanted = true
    @State private var weeks: [(Int, Double)] = []          // (几周前, 平均掉多少)
    @State private var weekLoad: [(String, Double)] = []    // 本周每天
    @State private var baseline = 0.0                       // 前 4 周平均每周负荷
    @State private var resting: [(String, Double)] = []
    @State private var sources: Set<String> = []
    @State private var lastDay: String?
    @State private var loading = true
    @State private var sheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("组间心率", systemImage: "heart.text.square.fill").font(.headline).foregroundStyle(.red)
                Spacer()
                Button { sheet = true } label: { Image(systemName: "gearshape").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
            }
            if !health.connected && HRLog.restDays().isEmpty {
                Text("连接 Apple 健康，或者在记录页休息条上点 ♡ 连耳机/手环，练几次后这里会出现你的组间恢复能力、每周心率负荷和静息心率。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            recovery
            loadView
            restingView
            if let d = lastDay {
                NavigationLink { HeartDays() } label: {
                    HStack {
                        Image(systemName: "waveform.path.ecg").foregroundStyle(.red)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("组间心率回放").font(.subheadline.bold())
                            Text("最近一次：\(Day.label(d)) · 每组心率、歇够没有").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            sourceRow
        }
        .sheet(isPresented: $sheet) { HeartSheet().presentationDetents([.medium, .large]) }
        .task(id: health.connected) { await reload() }
    }

    // 组间恢复能力：每周平均
    @ViewBuilder private var recovery: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("组间恢复能力").font(.subheadline.bold())
                Spacer()
                if let f = weeks.first(where: { $0.1 > 0 }), let l = weeks.last(where: { $0.1 > 0 }), f.0 != l.0, f.1 > 0 {
                    let pct = Int(((l.1 - f.1) / f.1 * 100).rounded())
                    Text(pct >= 0 ? "比 \(f.0) 周前快 \(pct)%" : "比 \(f.0) 周前慢 \(-pct)%")
                        .font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 3)
                        .foregroundStyle(pct >= 0 ? Color.green : Color.orange)
                        .background(Capsule().fill((pct >= 0 ? Color.green : .orange).opacity(0.14)))
                }
            }
            Text("每组练完 1 分钟内心率掉多少，掉得越快体能越好").font(.caption2).foregroundStyle(.secondary)
            if weeks.isEmpty {
                empty(loading ? "正在读取…" : "练的时候连上心率并用休息计时，几次后就有")
            } else {
                Chart(weeks, id: \.0) { w in
                    BarMark(x: .value("周", w.0 == 0 ? "本周" : "\(w.0)周前"), y: .value("掉", w.1))
                        .foregroundStyle(w.0 == weeks.last?.0 ? Color.red.gradient : Color.red.opacity(0.25).gradient)
                        .cornerRadius(4)
                        .annotation(position: .top) {
                            if w.0 == weeks.last?.0 { Text("−\(Int(w.1))").font(.caption2.bold()).foregroundStyle(.red) }
                        }
                }
                .chartYAxis(.hidden)
                .frame(height: 110)
            }
        }
    }

    // 本周心率负荷
    @ViewBuilder private var loadView: some View {
        let total = weekLoad.reduce(0) { $0 + $1.1 }
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("本周心率负荷").font(.subheadline.bold())
                Spacer()
                Text(total > 0 ? "\(Int(total))" : "--").font(.subheadline.bold()).monospacedDigit()
            }
            if total == 0 {
                empty(loading ? "正在读取…" : "这周还没有带心率的训练")
            } else {
                Chart(weekLoad, id: \.0) { d in
                    BarMark(x: .value("天", weekday(d.0)), y: .value("负荷", d.1))
                        .foregroundStyle(color(d.1).gradient)
                        .cornerRadius(5)
                }
                .chartYAxis(.hidden)
                .frame(height: 90)
            }
            if let t = tip(total) {
                Text(t).font(.caption).foregroundStyle(Color(hex: 0x7a2aa5))
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(LinearGradient(colors: [Color(hex: 0xfff1f6), Color(hex: 0xf6efff)], startPoint: .leading, endPoint: .trailing)))
            }
        }
    }

    @ViewBuilder private var restingView: some View {
        if let last = resting.last {
            let avg = resting.map(\.1).reduce(0, +) / Double(resting.count)
            HStack {
                Text("静息心率").font(.subheadline.bold())
                Spacer()
                Text("\(Int(last.1.rounded()))").font(.title3.bold()).monospacedDigit()
                Text("平时 \(Int(avg.rounded()))").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var sourceRow: some View {
        let on = sources.union(bleOn ? ["手环"] : []).union(sessionWanted ? ["耳机"] : [])
        return HStack(spacing: 8) {
            ForEach([("手表", "applewatch"), ("耳机", "airpodspro"), ("手环", "dot.radiowaves.left.and.right")], id: \.0) { s in
                Label(s.0, systemImage: s.1).font(.caption.bold())
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .foregroundStyle(on.contains(s.0) ? Color.red : Color.secondary)
                    .background(RoundedRectangle(cornerRadius: 10).fill(on.contains(s.0) ? Color.red.opacity(0.12) : Color(.tertiarySystemFill)))
            }
        }
    }

    private func empty(_ s: String) -> some View {
        Text(s).font(.caption).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.tertiarySystemFill)))
    }
    private func weekday(_ d: String) -> String {
        let w = Calendar.current.component(.weekday, from: Day.date(d))
        return ["日", "一", "二", "三", "四", "五", "六"][w - 1] + (d == Day.today ? "·今" : "")
    }
    private func color(_ v: Double) -> Color {
        v > 120 ? .red : v > 70 ? .orange : Color(hex: 0xffc078)
    }
    private func tip(_ total: Double) -> String? {
        var parts: [String] = []
        if baseline > 0, total > 0 {
            let pct = Int(((total - baseline) / baseline * 100).rounded())
            if pct >= 20 { parts.append("本周负荷 \(Int(total))，比平时高 \(pct)%。") }
            else if pct <= -30 { parts.append("本周负荷 \(Int(total))，比平时低 \(-pct)%。") }
        }
        if resting.count >= 10 {
            let base = resting.dropLast(3).map(\.1).reduce(0, +) / Double(resting.count - 3)
            let last3 = resting.suffix(3).map(\.1)
            if last3.allSatisfy({ $0 >= base + 3 }) {
                parts.append("静息心率连续 3 天偏高（\(Int(last3.last!.rounded()))，平时 \(Int(base.rounded()))），可能还没恢复好，可以安排减量或多睡一会儿。")
            }
        }
        return parts.isEmpty ? nil : parts.joined()
    }

    private func reload() async {
        // 以前连过 Apple 健康的，补一次心率权限
        if health.connected && !UserDefaults.standard.bool(forKey: "xt.health2") { _ = await health.connect() }
        let today = Day.today
        // 组间恢复：最近 8 周有休息记录的日子
        var byWeek: [Int: [Int]] = [:]
        for d in HRLog.restDays() where Day.between(d, today) < 56 {
            if let h = await DayHR.load(d) {
                let ds = h.drops
                if !ds.isEmpty { byWeek[Day.between(d, today) / 7, default: []] += ds }
            }
        }
        let newWeeks = byWeek.map { ($0.key, Double($0.value.reduce(0, +)) / Double($0.value.count)) }.sorted { $0.0 > $1.0 }
        // 每天的负荷：最近 35 天里有训练的日子
        let trainDays = Set(store.workouts.map(\.date)).union(HRLog.restDays())
        var loads: [String: Double] = [:]
        let d0 = Calendar.current.startOfDay(for: Date().addingTimeInterval(-34 * 86400))
        let hkDays = Set(await health.workoutSpans(d0, Date()).map { Day.str($0.0) })
        for i in 0..<35 {
            let d = Day.add(today, -i)
            guard trainDays.contains(d) || hkDays.contains(d) else { continue }
            if let h = await DayHR.load(d) { loads[d] = HRMath.load(h.pts) }
        }
        let newRest = await health.resting(days: 30)
        let newSources = await health.heartSources()
        // 全部算完再一次性更新，卡片高度只变一次（以前每读完一项就改一次，列表跟着反复重排）
        weeks = newWeeks
        weekLoad = (0..<7).reversed().map { i in let d = Day.add(today, -i); return (d, loads[d] ?? 0) }
        baseline = (7..<35).map { loads[Day.add(today, -$0)] ?? 0 }.reduce(0, +) / 4
        lastDay = (0..<35).map { Day.add(today, -$0) }.first { loads[$0] != nil }
        resting = newRest
        sources = newSources
        loading = false
    }
}

// MARK: - 训练心率回放：选哪天

struct HeartDays: View {
    @EnvironmentObject var store: Store
    private var days: [String] {
        let s = Set(store.workouts.map(\.date)).union(HRLog.restDays())
        return s.filter { Day.between($0, Day.today) < 60 }.sorted(by: >)
    }
    var body: some View {
        List(days, id: \.self) { d in
            NavigationLink { HeartReplay(day: d) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Day.label(d) + " · " + Day.ago(d)).font(.subheadline.bold())
                    Text(store.workouts.filter { $0.date == d }.map(\.displayTitle).joined(separator: "、").ifEmpty("训练"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("组间心率回放")
    }
}

// MARK: - 训练心率回放：一天

struct HeartReplay: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var hr = HeartLive.shared
    let day: String
    @State private var data: DayHR?
    @State private var loading = true

    struct SetHR: Identifiable {
        var id: Double { t }
        var t: Double
        var label: String
        var ex: String
        var n: Int
        var reps: Double
        var peak: Int?
        var back: Int?
        var rest: Double
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if loading {
                    ProgressView().padding(40)
                } else if let d = data {
                    summary(d)
                    setsCard(d)
                } else {
                    Text("这天没有心率数据。\n练的时候戴手表、AirPods Pro 3，或连上开了心率广播的手环，再用休息计时，练完就能看每组心率。")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(30)
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(Day.label(day) + " · " + store.workouts.filter { $0.date == day }.map(\.displayTitle).joined(separator: "、").ifEmpty("训练"))
        .navigationBarTitleDisplayMode(.inline)
        .task { data = await DayHR.load(day); loading = false }
    }

    private func card<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10, content: c)
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemGroupedBackground)))
    }

    private func kpi(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(v).font(.title3.bold()).monospacedDigit()
            Text(l).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.tertiarySystemFill)))
    }

    private static let zoneColors: [Color] = [Color(hex: 0x74c0fc), Color(hex: 0x69db7c), Color(hex: 0xffd43b), Color(hex: 0xff922b), Color(hex: 0xf03e3e)]

    private func summary(_ d: DayHR) -> some View {
        let vs = d.pts.map(\.v)
        let avg = vs.isEmpty ? 0 : vs.reduce(0, +) / vs.count
        let zs = HRMath.zones(d.pts)
        return card {
            HStack(spacing: 8) {
                kpi("\(avg)", "平均心率")
                kpi("\(vs.max() ?? 0)", "最高")
                kpi("\(Int(HRMath.load(d.pts)))", "心率负荷")
            }
            Chart {
                ForEach(sets(d)) { s in
                    RectangleMark(xStart: .value("开始", Date(timeIntervalSince1970: s.t - 40)), xEnd: .value("结束", Date(timeIntervalSince1970: s.t)))
                        .foregroundStyle(Color.purple.opacity(0.12))
                }
                ForEach(d.pts, id: \.t) { p in
                    LineMark(x: .value("时间", Date(timeIntervalSince1970: p.t)), y: .value("心率", p.v))
                        .foregroundStyle(Brand.pink).interpolationMethod(.catmullRom)
                }
                if hr.alertOn {
                    RuleMark(y: .value("恢复线", hr.line))
                        .foregroundStyle(.green).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .annotation(position: .top, alignment: .leading) { Text("\(hr.line) 恢复线").font(.caption2).foregroundStyle(.green) }
                }
            }
            .chartYScale(domain: max(40, (vs.min() ?? 60) - 10)...((vs.max() ?? 160) + 10))
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisValueLabel(format: .dateTime.hour().minute()) } }
            .frame(height: 170)
            GeometryReader { g in
                HStack(spacing: 0) {
                    ForEach(0..<5, id: \.self) { i in Self.zoneColors[i].frame(width: g.size.width * zs[i]) }
                }
            }
            .frame(height: 10).clipShape(Capsule())
            HStack {
                ForEach(Array(["热身", "燃脂", "有氧", "无氧", "极限"].enumerated()), id: \.0) { i, z in
                    Text("\(z) \(Int((zs[i] * 100).rounded()))%").font(.system(size: 10)).foregroundStyle(.secondary)
                    if i < 4 { Spacer(minLength: 0) }
                }
            }
        }
    }

    private func setsCard(_ d: DayHR) -> some View {
        let ss = sets(d)
        return card {
            HStack {
                Text("每组心率").font(.headline)
                Spacer()
                Text("最高 → 歇完回到").font(.caption).foregroundStyle(.secondary)
            }
            if ss.isEmpty {
                Text("这天没用休息计时，分不出每组。下次练的时候每组做完点一下休息计时就行。").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(ss) { s in
                HStack(spacing: 8) {
                    Text(s.label).font(.subheadline.bold()).lineLimit(1)
                    Spacer()
                    Text("\(s.peak.map(String.init) ?? "--") → \(s.back.map(String.init) ?? "--")").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    if let b = s.back {
                        let ok = b <= hr.line
                        Text(ok ? "歇够" : "没歇够").font(.caption2.bold())
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .foregroundStyle(ok ? Color.green : Color.red)
                            .background(Capsule().fill((ok ? Color.green : .red).opacity(0.12)))
                    }
                }
                Divider()
            }
            if let t = tip(ss) {
                Text(t).font(.caption).foregroundStyle(Color(hex: 0x7a2aa5))
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(LinearGradient(colors: [Color(hex: 0xfff1f6), Color(hex: 0xf6efff)], startPoint: .leading, endPoint: .trailing)))
            }
        }
    }

    // 第 n 次「X 后休息」对应这天 X 的第 n 组
    private func sets(_ d: DayHR) -> [SetHR] {
        let exs = store.workouts.filter { $0.date == day }.flatMap(\.exercises)
        var count: [String: Int] = [:]
        return d.rests.map { r in
            let n = count[r.ex, default: 0]
            count[r.ex] = n + 1
            var label = r.ex.isEmpty ? "第 \(n + 1) 组" : "\(r.ex) 第 \(n + 1) 组"
            var reps = 0.0
            if let e = exs.first(where: { $0.name == r.ex }), n < e.sets.count {
                let s = e.sets[n]
                reps = s.reps
                if !s.w.isEmpty || !s.r.isEmpty { label = "\(r.ex) \(s.w)\(WU.s) × \(s.r)" }
            }
            let end = r.end ?? r.t + 90
            return SetHR(t: r.t, label: label, ex: r.ex, n: n, reps: reps,
                         peak: HRMath.peak(d.pts, r.t - 60, r.t + 10),
                         back: HRMath.at(d.pts, end, within: 15), rest: end - r.t)
        }
    }

    private func tip(_ ss: [SetHR]) -> String? {
        guard !ss.isEmpty else { return nil }
        let line = hr.line
        // 没歇够之后，下一组次数掉了 → 是休息问题，不是力量退步
        for s in ss {
            guard let b = s.back, b > line,
                  let next = ss.first(where: { $0.ex == s.ex && $0.n == s.n + 1 }),
                  next.reps > 0, s.reps > 0, next.reps < s.reps else { continue }
            return "\(s.ex) 第 \(s.n + 2) 组次数掉了，开始时心率还在 \(b)，是没歇够，不是力量退步。下次可以等心率降到 \(line) 再开始。"
        }
        let bad = ss.filter { ($0.back ?? 0) > line }.count
        if bad > 0 { return "有 \(bad) 组开始时心率还没降到 \(line)，想冲重量的组可以多歇一会儿。" }
        return ss.contains(where: { $0.back != nil }) ? "每组都歇够了 👍" : nil
    }
}
