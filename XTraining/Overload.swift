import SwiftUI
import Charts

// 渐进超负荷：按动作看这次比上次有没有变强、该不该加重；训练安排体检；阻力曲线；参考文献 + 最新研究
// 判断方法：把「重量 × 次数」换算成力量估算（重量 × (1 + 次数/30)），加重量或加次数都算进步

enum Overload {
    struct Pt: Identifiable { let id = UUID(); let date: String; let w: Double; let r: Double; var e1: Double { Overload.e1(w, r) } }
    enum State { case done, same, miss, none }

    static func e1(_ w: Double, _ r: Double) -> Double { r <= 1 ? w : w * (1 + min(r, 15) / 30) }

    // 每次训练这个动作最强的一组
    static func points(_ name: String, part: String, in ss: [Workout]) -> [Pt] {
        var byDay: [String: Pt] = [:]
        for w in ss {
            for x in w.exercises(of: part) where x.name == name {
                for s in x.sets where s.weight > 0 && s.reps > 0 {
                    let p = Pt(date: w.date, w: s.weight, r: s.reps)
                    if (byDay[w.date]?.e1 ?? 0) < p.e1 { byDay[w.date] = p }
                }
            }
        }
        return byDay.values.sorted { $0.date < $1.date }
    }

    static func state(_ cur: Pt?, _ prev: Pt?) -> State {
        guard let cur, let prev else { return .none }
        if cur.e1 > prev.e1 * 1.005 { return .done }
        if cur.e1 >= prev.e1 * 0.995 { return .same }
        return .miss
    }

    // 下次目标：次数到 12 就加重（加 2.5%~5%，按杠铃片取整），次数回到 8；没到 12 就同重量多做 1 次
    static func next(after p: Pt, lower: Bool) -> (w: Double, r: Double) {
        if p.r >= 12 {
            let step = WU.lb ? 5.0 : 2.5
            let up = max(step, (p.w * (lower ? 0.05 : 0.025) / step).rounded() * step)
            return (p.w + up, 8)
        }
        return (p.w, p.r + 1)
    }

    // 动作在哪个位置最吃力（按动作类型粗分）
    enum Zone: String, CaseIterable { case long = "拉长位", mid = "中段", short = "缩短位" }
    static func zone(_ n: String) -> Zone {
        let long = ["飞鸟", "罗马尼亚", "直腿硬拉", "过头", "上斜弯举", "牧师", "保加利亚", "箭步", "弓步", "深蹲", "直臂下拉", "坐姿腿弯举", "拉伸", "山羊"]
        let short = ["夹胸", "蝴蝶机", "侧平举", "反向飞鸟", "面拉", "腿屈伸", "臀推", "下压", "耸肩", "提踵", "集中弯举", "俯身臂屈伸", "臀桥"]
        if n.contains("反向飞鸟") { return .short }
        if long.contains(where: n.contains) { return .long }
        if short.contains(where: n.contains) { return .short }
        return .mid
    }
    static let longTip: [String: String] = [
        "胸": "上斜哑铃飞鸟、大幅度绳索夹胸", "肩": "身后绳索侧平举、上斜侧平举", "背": "直臂下拉、全程引体向上",
        "腿": "罗马尼亚硬拉、保加利亚分腿蹲", "手臂": "上斜哑铃弯举、过头臂屈伸",
    ]

    struct Ref: Identifiable { let id = UUID(); let year: String; let text: String; let src: String }
    static let refs: [Ref] = [
        Ref(year: "2026", text: "Phillips SM, et al. ACSM Position Stand: Resistance Training Prescription for Muscle Function, Hypertrophy, and Physical Performance in Healthy Adults.", src: "Med Sci Sports Exerc, 2026"),
        Ref(year: "2026", text: "Lyristakis P, et al. The Influence of Individual Resistance Training Variables on Muscle Strength: A Systematic Review and Meta-analysis.", src: "Sports Med, 2026"),
        Ref(year: "2023", text: "Refalo MC, et al. Influence of Resistance Training Proximity-to-Failure on Skeletal Muscle Hypertrophy: A Systematic Review with Meta-analysis.", src: "Sports Med, 2023"),
        Ref(year: "2023", text: "Wolf M, et al. Partial vs Full Range of Motion Resistance Training: A Systematic Review and Meta-analysis.", src: "Int J Strength Cond, 2023"),
        Ref(year: "2022", text: "Plotkin D, et al. Progressive Overload Without Progressing Load? The Effects of Load or Repetition Progression on Muscular Adaptations.", src: "PeerJ, 2022"),
        Ref(year: "2021", text: "Lopez P, et al. Resistance Training Load Effects on Muscle Hypertrophy and Strength Gain: Systematic Review and Network Meta-analysis.", src: "Med Sci Sports Exerc, 2021"),
    ]
}

// 文献和建议数值放在网上（xtraining-events 仓库 public/science.json），每月更新不用发版
final class Science: ObservableObject {
    static let shared = Science()
    struct Ref: Codable { let year: String; let text: String; let src: String; var url: String? = nil }
    struct Rules: Codable {
        var setsMin = 10.0, setsMax = 20.0, freqMin = 2.0, repsMin = 5.0, repsMax = 20.0, gapMax = 5
        var setsTip = "建议每个部位每周 10 组以上，太多恢复不过来"
        var freqTip = "同一部位每周练 2 次以上效果更好"
        var repsTip = "增肌在 5–20 次都有效，接近力竭比次数本身更重要"
        var gapTip = "同一部位隔 2–5 天练一次比较合适"
        var longTip = "拉长位练得少。研究显示在肌肉拉长的位置发力更利于增肌，可以加："
    }
    struct Doc: Codable { var updated: String; var refs: [Ref]; var rules: Rules }
    @Published var doc: Doc
    private let key = "xt.science"
    init() {
        if let d = UserDefaults.standard.data(forKey: key), let x = try? JSONDecoder().decode(Doc.self, from: d) { doc = x }
        else { doc = Doc(updated: "2026-11-27", refs: Overload.refs.map { Ref(year: $0.year, text: $0.text, src: $0.src) }, rules: Rules()) }
    }
    @MainActor func refresh() async {
        guard let u = URL(string: "https://xtraining-events.vercel.app/science.json"),
              let (d, _) = try? await URLSession.shared.data(from: u),
              let x = try? JSONDecoder().decode(Doc.self, from: d), !x.refs.isEmpty else { return }
        doc = x
        UserDefaults.standard.set(d, forKey: key)
    }
}

// 进步页上的入口卡片
struct OverloadEntry: View {
    let part: String
    let sessions: [Workout]
    let names: [String]
    var body: some View {
        let sum = OverloadSummary(part: part, ss: sessions, names: names)
        NavigationLink { OverloadPage(part: part) } label: {
            HStack(spacing: 14) {
                Ring(frac: sum.frac, size: 62, line: 8)
                    .overlay { Text(sum.total == 0 ? "—" : "\(Int(sum.frac * 100))%").font(.system(size: 15, weight: .heavy, design: .rounded)) }
                VStack(alignment: .leading, spacing: 4) {
                    Text("渐进超负荷").font(.title3.bold()).foregroundStyle(Color.primary)
                    Text(sum.total == 0 ? "同一个动作练两次以上就能看" : "本月 \(sum.done)/\(sum.total) 次比上次强" + (sum.addCount > 0 ? " · \(sum.addCount) 个该加重" : ""))
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("训练安排体检 · 阻力曲线 · 参考文献").font(.caption).foregroundStyle(.tertiary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .card()
    }
}

struct Ring: View {
    let frac: Double
    var size: CGFloat = 96
    var line: CGFloat = 12
    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.08), lineWidth: line)
            Circle().trim(from: 0, to: max(0.001, frac))
                .stroke(Brand.gradient, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }
}

// 本月汇总
struct OverloadSummary {
    var done = 0, total = 0, streak = 0, addCount = 0
    var gain = 0.0
    var frac: Double { total == 0 ? 0 : Double(done) / Double(total) }
    init(part: String, ss: [Workout], names: [String]) {
        let month = String(Day.today.prefix(7))
        var gains: [Double] = []
        var weeksDone = Set<String>()
        for n in names {
            let pts = Overload.points(n, part: part, in: ss)
            guard pts.count >= 2 else { continue }
            for i in 1..<pts.count {
                let st = Overload.state(pts[i], pts[i - 1])
                if st == .done { weeksDone.insert(Self.week(pts[i].date)) }
                if pts[i].date.hasPrefix(month) { total += 1; if st == .done { done += 1 } }
            }
            let start = pts.first { $0.date.hasPrefix(month) } ?? pts[0]
            if let last = pts.last, start.e1 > 0, last.date != start.date { gains.append(last.e1 / start.e1 - 1) }
            if pts.count >= 2, pts.suffix(2).allSatisfy({ $0.r >= 12 }) { addCount += 1 }
        }
        gain = gains.isEmpty ? 0 : gains.reduce(0, +) / Double(gains.count)
        var d = Date()
        while weeksDone.contains(Self.week(Day.str(d))) { streak += 1; d = Calendar.current.date(byAdding: .day, value: -7, to: d) ?? d }
    }
    static func week(_ day: String) -> String {
        let c = Calendar(identifier: .iso8601).dateComponents([.yearForWeekOfYear, .weekOfYear], from: Day.date(day))
        return "\(c.yearForWeekOfYear ?? 0)-\(c.weekOfYear ?? 0)"
    }
}

struct OverloadPage: View {
    @EnvironmentObject var store: Store
    @State var part: String
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Picker("部位", selection: $part.animation(.snappy)) {
                    ForEach(Parts.strength, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
                OverloadBody(part: part).id(part)
            }
            .padding(.horizontal, 16).padding(.bottom, 30)
            .frame(maxWidth: 720).frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("渐进超负荷")
        .navigationBarTitleDisplayMode(.large)
    }
}

struct OverloadBody: View {
    @EnvironmentObject var store: Store
    let part: String
    var body: some View {
        let ss = store.workouts.filter { !$0.exercises(of: part).isEmpty }.sorted { $0.date < $1.date }
        var seen = Set<String>(), names: [String] = []
        for w in ss.reversed() { for x in w.exercises(of: part) where seen.insert(x.name).inserted { names.append(x.name) } }
        let sum = OverloadSummary(part: part, ss: ss, names: names)
        return VStack(spacing: 14) {
            SummaryCard(sum: sum)
            ExerciseCards(part: part, ss: ss, names: names)
            CheckupCard(part: part, ss: ss)
            CurveCard(part: part, ss: ss)
            RefsCard()
            Text("数据只是估算，用来对比自己前后的变化\n有伤病或不适请先咨询医生或教练")
                .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }
}

private struct SummaryCard: View {
    let sum: OverloadSummary
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("本月进度").font(.title3.bold()); Spacer(); Text(ymCN(String(Day.today.prefix(7)))).font(.subheadline).foregroundStyle(.secondary) }
            HStack(spacing: 16) {
                Ring(frac: sum.frac)
                    .overlay {
                        VStack(spacing: 0) {
                            Text(sum.total == 0 ? "—" : "\(Int(sum.frac * 100))%").font(.system(size: 24, weight: .heavy, design: .rounded))
                            Text("渐进完成").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                    GridRow { tile("\(sum.done)/\(sum.total)", "次训练有进步"); tile("\(sum.streak) 周", "连续完成") }
                    GridRow {
                        tile((sum.gain >= 0 ? "+" : "") + String(format: "%.1f%%", sum.gain * 100), "比起点变强", sum.gain > 0 ? Tone.up : nil)
                        tile("\(sum.addCount)", "个动作该加重")
                    }
                }
            }
        }
        .card()
    }
    private func tile(_ v: String, _ l: String, _ c: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(v).font(.system(size: 18, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(c ?? Color.primary)
            Text(l).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))
    }
}

private struct ExerciseCards: View {
    let part: String
    let ss: [Workout]
    let names: [String]
    @State private var showAll = false
    var body: some View {
        let rows = names.map { ($0, Overload.points($0, part: part, in: ss)) }.filter { !$0.1.isEmpty }
        let shown = showAll ? rows : Array(rows.prefix(5))
        VStack(alignment: .leading, spacing: 0) {
            HStack { Text("按动作").font(.title3.bold()); Spacer(); Text("每次最强的一组跟上次比").font(.caption).foregroundStyle(.secondary) }
                .padding(.bottom, 12)
            if rows.isEmpty { Text("还没有带重量和次数的记录").font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 12) }
            ForEach(Array(shown.enumerated()), id: \.offset) { i, r in
                if i > 0 { Divider().padding(.vertical, 12) }
                ExerciseRow(name: r.0, pts: r.1, lower: part == "腿" || part == "背")
            }
            if rows.count > 5 {
                Button(showAll ? "收起" : "还有 \(rows.count - 5) 个动作") { withAnimation(.snappy) { showAll.toggle() } }
                    .font(.subheadline.bold()).frame(maxWidth: .infinity).padding(.top, 12)
            }
        }
        .card()
    }
}

private struct ExerciseRow: View {
    let name: String
    let pts: [Overload.Pt]
    let lower: Bool
    var body: some View {
        let cur = pts.last!, prev = pts.count >= 2 ? pts[pts.count - 2] : nil
        let st = Overload.state(cur, prev)
        let target = prev.map { Overload.next(after: $0, lower: lower) }
        let misses = missStreak
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(name).font(.headline)
                tag(st, misses)
                Spacer()
            }
            HStack(spacing: 6) {
                if let prev {
                    box("上次 \(slashDate(prev.date))", txt(prev.w, prev.r), .primary)
                    arrow
                }
                if let target, st != .done {
                    box("目标", txt(target.w, target.r), .orange)
                    arrow
                }
                box((cur.date == Day.today ? "今天" : "这次 \(slashDate(cur.date))"), txt(cur.w, cur.r), color(st))
                if let prev, st == .done {
                    arrow
                    box("力量估算", String(format: "+%.0f%%", (cur.e1 / prev.e1 - 1) * 100), Tone.up)
                }
            }
            if pts.count >= 3 { MiniBars(pts: Array(pts.suffix(8))) }
            if let t = tip(st, misses, cur, prev) {
                HStack(alignment: .top, spacing: 6) {
                    Text(t.0)
                    Text(t.1).fixedSize(horizontal: false, vertical: true)
                }
                .font(.footnote)
                .foregroundStyle(t.2 ? Color(hex: 0x8134af) : Color(hex: 0xa35f00))
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(t.2 ? Color(hex: 0xdd2a7b).opacity(0.08) : Color.orange.opacity(0.12)))
            }
        }
    }
    private var missStreak: Int {
        var n = 0, i = pts.count - 1
        while i >= 1, Overload.state(pts[i], pts[i - 1]) == .miss { n += 1; i -= 1 }
        return n
    }
    private func txt(_ w: Double, _ r: Double) -> String { "\(fmtNum(w)) × \(fmtNum(r))" }
    private var arrow: some View { Image(systemName: "chevron.right").font(.caption2.bold()).foregroundStyle(.tertiary) }
    private func box(_ l: String, _ v: String, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(l).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            Text(v).font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(c).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
    }
    private func color(_ s: Overload.State) -> Color {
        switch s { case .done: return Tone.up; case .same: return .orange; case .miss: return Tone.down; case .none: return .primary }
    }
    @ViewBuilder private func tag(_ s: Overload.State, _ misses: Int) -> some View {
        let (t, c): (String, Color) = {
            switch s {
            case .done: return ("✓ 完成", Tone.up)
            case .same: return ("持平", .orange)
            case .miss: return (misses >= 2 ? "\(misses) 次没完成" : "没完成", Tone.down)
            case .none: return ("第一次", .secondary)
            }
        }()
        Text(t).font(.caption.bold()).foregroundStyle(c)
            .padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(c.opacity(0.13)))
    }
    // (图标, 文字, 是不是好消息)
    private func tip(_ s: Overload.State, _ misses: Int, _ cur: Overload.Pt, _ prev: Overload.Pt?) -> (String, String, Bool)? {
        if pts.count >= 2, pts.suffix(2).allSatisfy({ $0.r >= 12 }) {
            let n = Overload.next(after: cur, lower: lower)
            return ("⬆️", "该加重了：连续 2 次都做到 12 次以上，下次试 \(fmtNum(n.w))\(WU.s) × 8", true)
        }
        if misses >= 2, let base = pts.dropLast(misses).last {
            return ("💡", "连续 \(misses) 次没达标，先退回 \(fmtNum(base.w))\(WU.s)，把次数练上去再加", false)
        }
        if s == .done, let prev, cur.w > prev.w, cur.r < prev.r {
            return ("👍", "重量加了、次数少了也算进步，加重量和加次数都是有效的渐进方式", true)
        }
        return nil
    }
}

private struct MiniBars: View {
    let pts: [Overload.Pt]
    var body: some View {
        let lo = (pts.map(\.e1).min() ?? 0) * 0.85, hi = (pts.map(\.e1).max() ?? 1) * 1.02
        Chart {
            ForEach(Array(pts.enumerated()), id: \.offset) { i, p in
                let st = i == 0 ? Overload.State.none : Overload.state(p, pts[i - 1])
                // 柱子从图的底边开始画（不是从 0），不会画到卡片外面
                BarMark(x: .value("d", "\(i)"), yStart: .value("lo", lo), yEnd: .value("e", p.e1), width: .ratio(0.5))
                    .foregroundStyle(st == .done ? Tone.up.opacity(0.75) : st == .miss ? Tone.down.opacity(0.55) : Color(hex: 0x0a84ff).opacity(0.3))
                    .cornerRadius(4)
            }
        }
        .chartXAxis {
            AxisMarks { v in
                AxisValueLabel {
                    if let s = v.as(String.self), let i = Int(s), i < pts.count { Text(slashDate(pts[i].date)).font(.system(size: 9)) }
                }
            }
        }
        .chartYAxis(.hidden)
        .chartYScale(domain: lo...hi)
        .chartPlotStyle { $0.clipped() }
        .frame(height: 64)
        .clipped()
        .transaction { $0.animation = nil }
    }
}

// 训练安排体检：最近 4 周
private struct CheckupCard: View {
    let part: String
    let ss: [Workout]
    @ObservedObject private var sci = Science.shared
    var body: some View {
        let R = sci.doc.rules
        let from = Day.str(Calendar.current.date(byAdding: .day, value: -27, to: Date()) ?? Date())
        let recent = ss.filter { $0.date >= from }
        let sets = recent.flatMap { $0.exercises(of: part).flatMap(\.sets) }.filter { $0.weight > 0 || $0.reps > 0 }
        let days = Array(Set(recent.map(\.date))).sorted()
        let weekly = Double(sets.count) / 4
        let freq = Double(days.count) / 4
        let reps = sets.map(\.reps).filter { $0 > 0 }.sorted()
        let mid = reps.isEmpty ? 0 : reps[reps.count / 2]
        let gaps = zip(days.dropFirst(), days).map { Calendar.current.dateComponents([.day], from: Day.date($1), to: Day.date($0)).day ?? 0 }
        let maxGap = gaps.max() ?? 0
        let items: [(String, String, String, Bool)] = [
            ("📊", "每周 \(fmtNum((weekly * 10).rounded() / 10)) 组" + (weekly >= R.setsMin && weekly <= R.setsMax ? " ✓" : weekly > R.setsMax ? " · 偏多" : " · 偏少"),
             R.setsTip, weekly >= R.setsMin && weekly <= R.setsMax),
            ("📅", "每周练 \(fmtNum((freq * 10).rounded() / 10)) 次" + (freq >= R.freqMin ? " ✓" : " · 偏少"), R.freqTip, freq >= R.freqMin),
            ("🔁", "常用次数 \(fmtNum(mid)) 次" + (mid >= R.repsMin && mid <= R.repsMax ? " ✓" : mid < R.repsMin ? " · 偏大重量" : " · 偏多"),
             R.repsTip, mid >= R.repsMin && mid <= R.repsMax),
            ("⏸", "最长隔了 \(maxGap) 天" + (maxGap <= R.gapMax ? " ✓" : " · 偏长"), R.gapTip, maxGap <= R.gapMax),
        ]
        let bad = items.filter { !$0.3 }.count
        let score = max(40, 100 - bad * 14)
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("训练安排体检").font(.title3.bold()); Spacer(); Text("最近 4 周 · \(part)").font(.caption).foregroundStyle(.secondary) }
            if days.count < 3 {
                Text("最近 4 周练\(part)不到 3 次，记多几次再来体检").font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 8)
            } else {
                HStack(alignment: .center, spacing: 12) {
                    Text("\(score)").font(.system(size: 44, weight: .heavy, design: .rounded)).foregroundStyle(Brand.gradient)
                    Text(bad == 0 ? "分 · 安排得很科学" : "分 · 还有 \(bad) 项可以改进").font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(Array(items.enumerated()), id: \.offset) { i, it in
                    if i > 0 { Divider() }
                    HStack(spacing: 10) {
                        Text(it.0).frame(width: 32, height: 32)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(it.3 ? Tone.up.opacity(0.13) : Color.orange.opacity(0.15)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(it.1).font(.subheadline.bold())
                            Text(it.2).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            }
        }
        .card()
    }
}

// 阻力曲线：这个部位的组数分别落在拉长位 / 中段 / 缩短位
private struct CurveCard: View {
    let part: String
    let ss: [Workout]
    var body: some View {
        let from = Day.str(Calendar.current.date(byAdding: .day, value: -27, to: Date()) ?? Date())
        let xs = ss.filter { $0.date >= from }.flatMap { $0.exercises(of: part) }
        var count: [Overload.Zone: Int] = [:], names: [Overload.Zone: [String]] = [:]
        for x in xs {
            let z = Overload.zone(x.name)
            count[z, default: 0] += max(1, x.sets.count)
            if !(names[z] ?? []).contains(x.name) { names[z, default: []].append(x.name) }
        }
        let total = max(1, count.values.reduce(0, +))
        let longShare = Double(count[.long] ?? 0) / Double(total)
        let colors: [Overload.Zone: Color] = [.long: Tone.down, .mid: Color(hex: 0x0a84ff), .short: Color(hex: 0x7048e8)]
        return VStack(alignment: .leading, spacing: 10) {
            HStack { Text("阻力曲线").font(.title3.bold()); Spacer(); Text("在哪个位置最吃力").font(.caption).foregroundStyle(.secondary) }
            if xs.isEmpty {
                Text("最近 4 周没练\(part)").font(.subheadline).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 6) {
                    ForEach(Overload.Zone.allCases, id: \.self) { z in
                        let c = colors[z] ?? .blue
                        VStack(spacing: 2) {
                            Text(z.rawValue).font(.caption2)
                            Text("\(Int((Double(count[z] ?? 0) / Double(total) * 100).rounded()))%").font(.system(size: 20, weight: .bold, design: .rounded))
                            Text((names[z] ?? []).prefix(2).joined(separator: " ")).font(.system(size: 10)).lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .foregroundStyle(c)
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(c.opacity(0.1)))
                    }
                }
                if longShare < 0.2 {
                    Text("💡 " + Science.shared.doc.rules.longTip + (Overload.longTip[part] ?? ""))
                        .font(.footnote).foregroundStyle(Color(hex: 0xa35f00))
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.orange.opacity(0.12)))
                }
                Text("按动作类型估算").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .card()
    }
}

private struct RefsCard: View {
    @State private var all = false
    @ObservedObject private var sci = Science.shared
    var body: some View {
        let refs = sci.doc.refs
        let list = all ? refs : Array(refs.prefix(3))
        VStack(alignment: .leading, spacing: 0) {
            HStack { Text("参考文献").font(.title3.bold()); Spacer(); Text("更新于 \(slashDate(sci.doc.updated))").font(.caption).foregroundStyle(.secondary) }
                .padding(.bottom, 8)
            ForEach(Array(list.enumerated()), id: \.offset) { i, r in
                if i > 0 { Divider() }
                (Text(r.year + "  ").font(.caption2.bold()).foregroundColor(Color(hex: 0xdd2a7b))
                 + Text(r.text + " ").font(.caption)
                 + Text(r.src).font(.caption).foregroundColor(.secondary))
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if refs.count > 3 { Button(all ? "收起" : "展开全部 \(refs.count) 篇") { withAnimation(.snappy) { all.toggle() } }
                .font(.subheadline.bold()).frame(maxWidth: .infinity).padding(.top, 6) }
        }
        .card()
        .task { await sci.refresh() }
    }
}

// 最新研究：每周从 PubMed 拉一次（免费公开接口），缓存在本机
final class PaperFeed: ObservableObject {
    static let shared = PaperFeed()
    struct Paper: Codable, Identifiable { let id: String; let title: String; let journal: String; let date: String }
    @Published var papers: [Paper] = []
    @Published var updated: Double = 0
    private let key = "xt.papers"
    init() {
        if let d = UserDefaults.standard.data(forKey: key), let c = try? JSONDecoder().decode(Cache.self, from: d) { papers = c.papers; updated = c.at }
    }
    private struct Cache: Codable { let papers: [Paper]; let at: Double }

    @MainActor func refresh(force: Bool = false) async {
        let now = Date().timeIntervalSince1970
        guard force || papers.isEmpty || now - updated > 7 * 86400 else { return }
        let term = "(\"progressive overload\" OR \"resistance training\") AND (hypertrophy OR strength) AND (meta-analysis[pt] OR systematic review[pt]) AND 2023:3000[dp]"
        var c = URLComponents(string: "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi")!
        c.queryItems = [.init(name: "db", value: "pubmed"), .init(name: "term", value: term), .init(name: "sort", value: "pub_date"),
                        .init(name: "retmax", value: "5"), .init(name: "retmode", value: "json")]
        guard let u = c.url, let (d, _) = try? await URLSession.shared.data(from: u),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let ids = (j["esearchresult"] as? [String: Any])?["idlist"] as? [String], !ids.isEmpty else { return }
        var s = URLComponents(string: "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi")!
        s.queryItems = [.init(name: "db", value: "pubmed"), .init(name: "id", value: ids.joined(separator: ",")), .init(name: "retmode", value: "json")]
        guard let su = s.url, let (sd, _) = try? await URLSession.shared.data(from: su),
              let sj = try? JSONSerialization.jsonObject(with: sd) as? [String: Any],
              let res = sj["result"] as? [String: Any] else { return }
        let list: [Paper] = ids.compactMap { id in
            guard let r = res[id] as? [String: Any], let t = r["title"] as? String else { return nil }
            return Paper(id: id, title: t, journal: (r["source"] as? String) ?? "", date: (r["pubdate"] as? String) ?? "")
        }
        guard !list.isEmpty else { return }
        papers = list; updated = now
        if let d = try? JSONEncoder().encode(Cache(papers: list, at: now)) { UserDefaults.standard.set(d, forKey: key) }
    }
}

private struct LatestPapersCard: View {
    @ObservedObject private var feed = PaperFeed.shared
    @Environment(\.openURL) private var openURL
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("最新研究").font(.title3.bold())
                Spacer()
                Text(feed.updated > 0 ? "更新于 " + slashDate(Day.str(Date(timeIntervalSince1970: feed.updated))) : "每周从 PubMed 自动更新")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.bottom, 8)
            if feed.papers.isEmpty {
                Text("正在获取最新论文…（需要联网）").font(.caption).foregroundStyle(.secondary).padding(.vertical, 6)
            }
            ForEach(Array(feed.papers.enumerated()), id: \.offset) { i, p in
                if i > 0 { Divider() }
                Button { if let u = URL(string: "https://pubmed.ncbi.nlm.nih.gov/\(p.id)/") { openURL(u) } } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(p.title).font(.caption).foregroundStyle(Color.primary).multilineTextAlignment(.leading)
                        Text("\(p.journal) · \(p.date)").font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .card()
        .task { await feed.refresh() }
    }
}
