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

// MARK: - 「我」页里的一行（放在列表里：固定高度、只读存好的摘要，不观察实时心率）

struct HeartRow: View {
    @AppStorage("xt.hrSummary") private var summary = ""      // "恢复|本周负荷|静息"，组间心率页算完存的
    var body: some View {
        let p = summary.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        let v = { (i: Int) -> String in i < p.count && !p[i].isEmpty ? p[i] : "--" }
        HStack(spacing: 12) {
            MeIcon(system: "heart.fill", colors: [Color(hex: 0xff5f6d), Color(hex: 0xe0245e)])
            VStack(alignment: .leading, spacing: 3) {
                Text("组间心率").font(.body.bold())
                Text("恢复能力 · 每周负荷 · 每组回放").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    chip("恢复 " + (v(0) == "--" ? "--" : "−" + v(0)))
                    chip("本周负荷 " + v(1))
                    chip("静息 " + v(2))
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }
    private func chip(_ t: String) -> some View {
        Text(t).font(.system(size: 11, weight: .semibold)).lineLimit(1)
            .foregroundStyle(Color(hex: 0xe0284f))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color(hex: 0xe0284f).opacity(0.1)))
    }
}

// 「我」页列表前面的彩色小图标
struct MeIcon: View {
    var system: String
    var colors: [Color]
    var body: some View {
        Image(systemName: system).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)))
    }
}

struct MeLinkLabel: View {
    var system: String
    var colors: [Color]
    var title: String
    var sub: String
    var body: some View {
        HStack(spacing: 12) {
            MeIcon(system: system, colors: colors)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(sub).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 组间心率页（单独一页，用 ScrollView，不放进列表）

struct HeartPage: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var health = Health.shared
    // 不观察 HeartLive（训练时每秒更新），这页只看历史
    @AppStorage("xt.hrBLE") private var bleOn = false
    @AppStorage("xt.hrSession2") private var sessionWanted = true
    @AppStorage("xt.hrLine") private var line = 115
    @AppStorage("xt.hrSummary") private var summary = ""
    @State private var weeks: [(Int, Double)] = []          // (几周前, 平均掉多少)，从远到近
    @State private var weekLoad: [(String, Double)] = []    // 本周每天
    @State private var baseline = 0.0                       // 前 4 周平均每周负荷
    @State private var resting: [(String, Double)] = []
    @State private var sources: Set<String> = []
    @State private var recent: [DaySum] = []
    @State private var loading = true
    @State private var sheet = false

    struct DaySum: Identifiable {
        var id: String { day }
        var day: String
        var sets: Int
        var avg: Int
        var bad: Int
    }

    private static let pink = Color(hex: 0xe0245e)

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                hero
                tiles
                loadCard
                replayCard
                sourceRow
                if !health.connected && HRLog.restDays().isEmpty {
                    Text("连接 Apple 健康，或者在记录页休息条上点 ♡ 连耳机/手环，练几次后这里会出现你的组间恢复能力、每周心率负荷和每组心率。")
                        .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 4)
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("组间心率")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { sheet = true } label: { Image(systemName: "gearshape") }
            }
        }
        .sheet(isPresented: $sheet) { HeartSheet().presentationDetents([.medium, .large]) }
        .task(id: health.connected) { await reload() }
    }

    // 顶部：组间恢复能力
    private var hero: some View {
        let last = weeks.last?.1
        return VStack(alignment: .leading, spacing: 6) {
            Text("组间恢复能力 · 每组练完 1 分钟心率掉多少").font(.caption).opacity(0.88)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(last.map { "−\(Int($0.rounded()))" } ?? "--")
                            .font(.system(size: 52, weight: .heavy, design: .rounded)).monospacedDigit()
                        Text("次/分").font(.subheadline.bold()).opacity(0.9)
                    }
                    Text(badge ?? (loading ? "正在读取…" : "练的时候连上心率、用休息计时，几次后就有"))
                        .font(.caption.bold()).padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(.white.opacity(0.22)))
                }
                Spacer(minLength: 8)
                spark.frame(width: 130, height: 64)
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(LinearGradient(colors: [Color(hex: 0xff5f6d), Self.pink, Color(hex: 0x9b1fb5)], startPoint: .topLeading, endPoint: .bottomTrailing)))
    }

    private var badge: String? {
        guard let f = weeks.first, let l = weeks.last, f.0 != l.0, f.1 > 0 else { return nil }
        let pct = Int(((l.1 - f.1) / f.1 * 100).rounded())
        return pct >= 0 ? "比 \(f.0) 周前快 \(pct)%" : "比 \(f.0) 周前慢 \(-pct)%"
    }

    // 恢复能力每周的小折线
    private var spark: some View {
        GeometryReader { g in
            let vs = weeks.map(\.1)
            if vs.count >= 2, let lo = vs.min(), let hi = vs.max() {
                let pts = vs.enumerated().map { i, v in
                    CGPoint(x: g.size.width * CGFloat(i) / CGFloat(vs.count - 1),
                            y: g.size.height - 6 - (g.size.height - 12) * CGFloat(hi > lo ? (v - lo) / (hi - lo) : 0.5))
                }
                Path { p in p.addLines(pts) }
                    .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                if let e = pts.last { Circle().fill(.white).frame(width: 10, height: 10).position(e) }
            }
        }
    }

    private var weekTotal: Double { weekLoad.reduce(0) { $0 + $1.1 } }

    private var tiles: some View {
        let total = weekTotal
        let pct = baseline > 0 && total > 0 ? Int(((total - baseline) / baseline * 100).rounded()) : nil
        let avgRest = resting.isEmpty ? nil : resting.map(\.1).reduce(0, +) / Double(resting.count)
        return HStack(spacing: 10) {
            tile("本周负荷", total > 0 ? "\(Int(total))" : "--",
                 pct.map { $0 >= 0 ? "比平时 +\($0)%" : "比平时 \($0)%" } ?? "按心率算", pct.map { $0 >= 20 ? Color.orange : Color.green } ?? Color.secondary)
            tile("静息心率", resting.last.map { "\(Int($0.1.rounded()))" } ?? "--",
                 avgRest.map { "平时 \(Int($0.rounded()))" } ?? "Apple 健康", .green)
            Button { sheet = true } label: { tile("恢复线", "\(line)", "点这里改", .secondary) }
                .buttonStyle(.plain)
        }
    }

    private func tile(_ t: String, _ v: String, _ note: String, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(t).font(.caption2).foregroundStyle(.secondary)
            Text(v).font(.system(size: 22, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(.primary)
            Text(note).font(.system(size: 11, weight: .bold)).foregroundStyle(c).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }

    private func card<C: View>(_ title: String, _ note: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer()
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
            c()
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }

    private var loadCard: some View {
        card("本周心率负荷", "按心率算每天练得多累") {
            if weekTotal == 0 {
                empty(loading ? "正在读取…" : "这周还没有带心率的训练")
            } else {
                let mx = max(1, weekLoad.map(\.1).max() ?? 1)
                HStack(alignment: .bottom, spacing: 9) {
                    ForEach(weekLoad, id: \.0) { d in
                        VStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(d.1 > 0 ? barColor(d.1 / mx) : Color(.tertiarySystemFill))
                                .frame(height: max(4, 76 * d.1 / mx))
                            Text(weekday(d.0)).font(.system(size: 10.5)).foregroundStyle(d.0 == Day.today ? Self.pink : .secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 96, alignment: .bottom)
            }
            if let t = tip {
                Text(t).font(.caption).foregroundStyle(Color(hex: 0x8a2a52))
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Self.pink.opacity(0.08)))
            }
        }
    }

    private var replayCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("每组心率回放").font(.headline)
                Spacer()
                NavigationLink { HeartDays() } label: { Text("全部 ›").font(.caption) }
            }
            if recent.isEmpty {
                empty(loading ? "正在读取…" : "练的时候戴手表 / AirPods Pro 3 或连手环，每组做完点一下休息计时")
            }
            ForEach(Array(recent.enumerated()), id: \.1.id) { i, r in
                if i > 0 { Divider() }
                NavigationLink { HeartReplay(day: r.day) } label: { replayRow(r) }
                    .buttonStyle(.plain)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }

    private func replayRow(_ r: DaySum) -> some View {
        let p = r.day.split(separator: "-")
        let md = p.count == 3 ? "\(Int(p[1]) ?? 0)/\(Int(p[2]) ?? 0)" : r.day
        let title = store.workouts.filter { $0.date == r.day }.map(\.displayTitle).joined(separator: "、").ifEmpty("训练")
        return HStack(spacing: 10) {
            Text(md).font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(Self.pink)
                .frame(width: 44, height: 40)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Self.pink.opacity(0.1)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold()).lineLimit(1)
                Text((r.sets > 0 ? "\(r.sets) 组 · " : "") + "平均 \(r.avg)" + (r.sets > 0 ? (r.bad > 0 ? " · \(r.bad) 组没歇够" : " · 都歇够了") : ""))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if r.sets > 0 {
                Text(r.bad > 0 ? "\(r.bad) 组" : "歇够").font(.caption2.bold())
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .foregroundStyle(r.bad > 0 ? Color.orange : Color.green)
                    .background(Capsule().fill((r.bad > 0 ? Color.orange : Color.green).opacity(0.13)))
            }
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private var sourceRow: some View {
        let on = sources.union(bleOn ? ["手环"] : []).union(sessionWanted ? ["耳机"] : [])
        return HStack(spacing: 8) {
            ForEach([("手表", "applewatch"), ("耳机", "airpodspro"), ("手环", "dot.radiowaves.left.and.right")], id: \.0) { s in
                Button { sheet = true } label: {
                    Label(s.0, systemImage: s.1).font(.caption.bold())
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .foregroundStyle(on.contains(s.0) ? Self.pink : Color.secondary)
                        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(on.contains(s.0) ? Self.pink.opacity(0.1) : Color(.secondarySystemGroupedBackground)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func empty(_ s: String) -> some View {
        Text(s).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.tertiarySystemFill)))
    }
    private func weekday(_ d: String) -> String {
        if d == Day.today { return "今" }
        let w = Calendar.current.component(.weekday, from: Day.date(d))
        return ["日", "一", "二", "三", "四", "五", "六"][w - 1]
    }
    private func barColor(_ f: Double) -> Color {
        f > 0.85 ? Self.pink : f > 0.5 ? Color(hex: 0xff6b88) : Color(hex: 0xffb3c1)
    }
    private var tip: String? {
        let total = weekTotal
        var parts: [String] = []
        var restHigh = false
        if resting.count >= 10 {
            let base = resting.dropLast(3).map(\.1).reduce(0, +) / Double(resting.count - 3)
            let last3 = resting.suffix(3).map(\.1)
            if last3.allSatisfy({ $0 >= base + 3 }), let l = last3.last {
                restHigh = true
                parts.append("静息心率连续 3 天偏高（\(Int(l.rounded()))，平时 \(Int(base.rounded()))），可能还没恢复好，可以安排减量或多睡一会儿。")
            }
        }
        if baseline > 0, total > 0 {
            let pct = Int(((total - baseline) / baseline * 100).rounded())
            if pct >= 20 { parts.insert("本周比平时练得累 \(pct)%" + (restHigh ? "。" : "，静息心率也正常，状态不错。"), at: 0) }
            else if pct <= -30 { parts.insert("本周比平时练得少 \(-pct)%。", at: 0) }
        }
        return parts.isEmpty ? nil : parts.joined()
    }

    private func reload() async {
        // 以前连过 Apple 健康的，补一次心率权限
        if health.connected && !UserDefaults.standard.bool(forKey: "xt.health2") { _ = await health.connect() }
        let today = Day.today
        let lineNow = line
        // 组间恢复：最近 8 周有休息记录的日子
        var byWeek: [Int: [Int]] = [:]
        for d in HRLog.restDays() where Day.between(d, today) < 56 {
            if let h = await DayHR.load(d) {
                let ds = h.drops
                if !ds.isEmpty { byWeek[Day.between(d, today) / 7, default: []] += ds }
            }
        }
        let newWeeks = byWeek.map { ($0.key, Double($0.value.reduce(0, +)) / Double($0.value.count)) }.sorted { $0.0 > $1.0 }
        // 每天的负荷 + 最近几次的摘要：最近 35 天里有训练的日子
        let trainDays = Set(store.workouts.map(\.date)).union(HRLog.restDays())
        var loads: [String: Double] = [:]
        var sums: [DaySum] = []
        let d0 = Calendar.current.startOfDay(for: Date().addingTimeInterval(-34 * 86400))
        let hkDays = Set(await health.workoutSpans(d0, Date()).map { Day.str($0.0) })
        for i in 0..<35 {
            let d = Day.add(today, -i)
            guard trainDays.contains(d) || hkDays.contains(d) else { continue }
            guard let h = await DayHR.load(d) else { continue }
            loads[d] = HRMath.load(h.pts)
            if sums.count < 3 {
                let vs = h.pts.map(\.v)
                let bad = h.rests.filter { r in (HRMath.at(h.pts, r.end ?? r.t + 90, within: 15) ?? 0) > lineNow }.count
                sums.append(DaySum(day: d, sets: h.rests.count, avg: vs.isEmpty ? 0 : vs.reduce(0, +) / vs.count, bad: bad))
            }
        }
        let newRest = await health.resting(days: 30)
        let newSources = await health.heartSources()
        // 全部算完再一次性更新
        weeks = newWeeks
        weekLoad = (0..<7).reversed().map { i in let d = Day.add(today, -i); return (d, loads[d] ?? 0) }
        baseline = (7..<35).map { loads[Day.add(today, -$0)] ?? 0 }.reduce(0, +) / 4
        resting = newRest
        sources = newSources
        recent = sums
        loading = false
        // 「我」页那一行显示的摘要
        let rec = newWeeks.last.map { String(Int($0.1.rounded())) } ?? ""
        let total = weekLoad.reduce(0) { $0 + $1.1 }
        let rest = newRest.last.map { String(Int($0.1.rounded())) } ?? ""
        let s = "\(rec)|\(total > 0 ? String(Int(total)) : "")|\(rest)"
        if s != summary { summary = s }
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
