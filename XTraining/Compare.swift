import SwiftUI

// MARK: 选年月（滚轮）
struct MonthPicker: View {
    @Environment(\.dismiss) private var dismiss
    let month: String                 // "2026-11"
    var onPick: (String) -> Void
    @State private var y = 2026
    @State private var m = 11

    private var thisYear: Int { Int(Day.today.prefix(4)) ?? 2026 }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                Picker("年", selection: $y) {
                    ForEach((thisYear - 6)...thisYear, id: \.self) { Text(String(format: "%d年", $0)).tag($0) }
                }
                .pickerStyle(.wheel)
                Picker("月", selection: $m) {
                    ForEach(1...12, id: \.self) { Text("\($0)月").tag($0) }
                }
                .pickerStyle(.wheel)
            }
            .padding(.horizontal)
            .navigationTitle("跳到年月").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .principal) {
                    Button("本月") { y = thisYear; m = Int(Day.today.dropFirst(5).prefix(2)) ?? 1 }.font(.subheadline)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        var s = String(format: "%04d-%02d", y, m)
                        if s > String(Day.today.prefix(7)) { s = String(Day.today.prefix(7)) }
                        onPick(s); Haptic.tap(); dismiss()
                    }.bold()
                }
            }
        }
        .onAppear {
            let p = month.split(separator: "-")
            if p.count == 2 { y = Int(p[0]) ?? thisYear; m = Int(p[1]) ?? 1 }
        }
    }
}

func ymCN(_ m: String) -> String {
    let p = m.split(separator: "-"); return p.count >= 2 ? "\(p[0])年\(Int(p[1]) ?? 0)月" : m
}
func prevMonth(_ m: String) -> String {
    String(Day.str(Calendar.current.date(byAdding: .month, value: -1, to: Day.date(m + "-01")) ?? Date()).prefix(7))
}

// 多了绿、少了红
func diffColor(_ a: Double, _ b: Double) -> Color { a > b ? Color(hex: 0x2f9e44) : a < b ? Color(hex: 0xe03131) : .secondary }
func diffText(_ a: Double, _ b: Double, _ unit: String = "") -> String {
    let d = a - b
    if abs(d) < 0.001 { return "持平" }
    return (d > 0 ? "+" : "") + fmtNum((d * 10).rounded() / 10) + unit
}

// MARK: 月份对比：两个月的运动量和每个动作的最好成绩
struct MonthCompare: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var a: String
    @State private var b = ""
    @State private var pickA = false
    @State private var pickB = false
    @State private var ha: [String: DayAct] = [:]
    @State private var hb: [String: DayAct] = [:]

    init(a: String) { _a = State(initialValue: a) }

    private struct Stat { var days = 0, count = 0, sets = 0; var minutes = 0.0, kcal = 0.0; var parts: [String: Int] = [:] }

    private func stat(_ m: String, _ h: [String: DayAct]) -> Stat {
        var s = Stat()
        let ws = store.workouts.filter { $0.date.hasPrefix(m) }
        var days = Set(ws.map(\.date))
        for (d, x) in h where d.hasPrefix(m) && x.count > 0 { days.insert(d); s.minutes += x.minutes; s.kcal += x.kcal; s.count += x.count }
        if s.count == 0 { s.count = ws.count }
        s.days = days.count
        for w in ws {
            for x in w.exercises where !x.isCardio {
                s.sets += x.sets.count
                let p = Parts.of(x.name) ?? w.parts.first { $0 != "有氧" } ?? ""
                if !p.isEmpty { s.parts[p, default: 0] += x.sets.count }
            }
        }
        return s
    }

    // 每个动作这个月最重的一组（同重量取次数最多）
    private func bests(_ m: String) -> [String: SetRow] {
        var out: [String: SetRow] = [:]
        for w in store.workouts where w.date.hasPrefix(m) {
            for x in w.exercises where !x.isCardio {
                for s in x.sets where s.weight > 0 {
                    if let o = out[x.name], o.weight > s.weight || (o.weight == s.weight && o.reps >= s.reps) { continue }
                    out[x.name] = s
                }
            }
        }
        return out
    }

    var body: some View {
        let sa = stat(a, ha), sb = stat(b, hb)
        let ba = bests(a), bb = bests(b)
        let both = store.allExerciseNames.filter { ba[$0] != nil && bb[$0] != nil }
        NavigationStack {
            List {
                Section {
                    HStack {
                        monthButton(b) { pickB = true }
                        Image(systemName: "arrow.right").foregroundStyle(.secondary).frame(maxWidth: .infinity)
                        monthButton(a) { pickA = true }
                    }
                    .buttonStyle(.plain)
                } footer: { Text("右边和左边比：多了绿色，少了红色。点月份可以换。") }
                Section("运动量") {
                    row("运动天数", Double(sb.days), Double(sa.days), "天")
                    row("运动次数", Double(sb.count), Double(sa.count), "次")
                    if sa.minutes + sb.minutes > 0 {
                        row("运动时长", sb.minutes.rounded(), sa.minutes.rounded(), "分钟")
                        row("消耗", sb.kcal.rounded(), sa.kcal.rounded(), "kcal")
                    }
                    row("力量总组数", Double(sb.sets), Double(sa.sets), "组")
                }
                Section("各部位组数") {
                    ForEach(Parts.strength, id: \.self) { p in
                        row(p, Double(sb.parts[p] ?? 0), Double(sa.parts[p] ?? 0), "组")
                    }
                }
                Section {
                    if both.isEmpty {
                        Text("两个月没有都练过的动作").foregroundStyle(.secondary)
                    }
                    ForEach(both, id: \.self) { n in
                        let x = bb[n]!, y = ba[n]!
                        HStack {
                            Text(n).font(.subheadline.bold()).lineLimit(1)
                            Spacer()
                            Text(setLabel(x)).foregroundStyle(.secondary).monospacedDigit()
                            Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                            Text(setLabel(y)).bold().monospacedDigit()
                                .foregroundStyle(y.weight != x.weight ? diffColor(y.weight, x.weight) : diffColor(y.reps, x.reps))
                        }
                    }
                } header: { Text("每个动作最好的一组") }
            }
            .navigationTitle("月份对比").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .sheet(isPresented: $pickA) { MonthPicker(month: a) { a = $0 }.presentationDetents([.height(320)]) }
            .sheet(isPresented: $pickB) { MonthPicker(month: b) { b = $0 }.presentationDetents([.height(320)]) }
            .task(id: a) { ha = await Health.shared.fetch(month: Day.date(a + "-01")) }
            .task(id: b) { if !b.isEmpty { hb = await Health.shared.fetch(month: Day.date(b + "-01")) } }
            .onAppear { if b.isEmpty { b = prevMonth(a) } }
        }
    }

    private func monthButton(_ m: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(ymCN(m)).font(.headline)
                Image(systemName: "chevron.down").font(.caption2.bold()).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Capsule().fill(Color(.tertiarySystemFill)))
        }
    }

    private func row(_ t: String, _ old: Double, _ new: Double, _ unit: String) -> some View {
        HStack {
            Text(t)
            Spacer()
            Text(fmtNum(old)).foregroundStyle(.secondary).monospacedDigit()
            Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
            Text(fmtNum(new) + unit).bold().monospacedDigit()
            Text(diffText(new, old)).font(.caption.bold()).foregroundStyle(diffColor(new, old))
                .frame(minWidth: 52, alignment: .trailing)
        }
    }
}

// MARK: 个人纪录：选一个动作显示
struct PRPicker: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("prPinned") private var pinned = ""

    private struct Row { let name: String; let kg: Double; let reps: Double; let date: String }
    private var rows: [Row] {
        var best: [String: Row] = [:]
        for w in store.workouts.sorted(by: { $0.date < $1.date }) {
            for x in w.exercises where !x.isCardio {
                for s in x.sets where s.weight > 0 {
                    if let o = best[x.name], o.kg > s.weight || (o.kg == s.weight && o.reps >= s.reps) { continue }
                    best[x.name] = Row(name: x.name, kg: s.weight, reps: s.reps, date: w.date)
                }
            }
        }
        return best.values.sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { pinned = ""; Haptic.tap(); dismiss() } label: {
                        HStack {
                            Label("自动：显示最近破纪录的动作", systemImage: "sparkles")
                            Spacer()
                            if pinned.isEmpty { Image(systemName: "checkmark").foregroundStyle(Brand.pink) }
                        }
                    }
                    .foregroundStyle(.primary)
                }
                Section("选一个动作固定显示") {
                    ForEach(rows, id: \.name) { r in
                        Button { pinned = r.name; Haptic.tap(); dismiss() } label: {
                            HStack {
                                Circle().fill(Parts.of(r.name).map(Parts.color) ?? .gray).frame(width: 8, height: 8)
                                Text(r.name).font(.subheadline.bold())
                                Spacer()
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text("\(fmtNum(r.kg))kg" + (r.reps > 0 ? " × \(fmtNum(r.reps))" : "")).monospacedDigit().bold()
                                    Text(slashDate(r.date)).font(.caption2).foregroundStyle(.secondary)
                                }
                                if pinned == r.name { Image(systemName: "checkmark").foregroundStyle(Brand.pink) }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle("个人纪录").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}

// MARK: 阶段对比：自定义阶段（增肌期、减脂期…）+ 锚点（某个动作固定重量×次数）
struct Phase: Codable, Identifiable, Hashable {
    var id = UUID()
    var name = "增肌期"
    var start = Day.today
    var end = ""                     // 空 = 至今
    func contains(_ d: String) -> Bool { d >= start && (end.isEmpty || d <= end) }
    var range: String { slashDate(start) + " – " + (end.isEmpty ? "至今" : slashDate(end)) }
}
struct Anchor: Codable, Identifiable, Hashable {
    var id = UUID()
    var name = ""
    var kg = ""
    var reps = ""
}

@MainActor
final class AnchorStore: ObservableObject {
    static let shared = AnchorStore()
    @Published var phases: [Phase] = AnchorStore.load("xt.phases") ?? [] { didSet { save(phases, "xt.phases") } }
    @Published var anchors: [Anchor] = AnchorStore.load("xt.anchors") ?? [] { didSet { save(anchors, "xt.anchors") } }
    private static func load<T: Decodable>(_ k: String) -> T? {
        UserDefaults.standard.data(forKey: k).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }
    private func save<T: Encodable>(_ v: T, _ k: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(v), forKey: k)
    }
}

struct AnchorView: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var st = AnchorStore.shared
    @State private var filter: UUID? = nil         // nil = 全部
    @State private var editPhase: Phase? = nil
    @State private var editAnchor: Anchor? = nil

    private var phase: Phase? { st.phases.first { $0.id == filter } }

    var body: some View {
        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chip("全部", filter == nil) { filter = nil }
                        ForEach(st.phases) { p in
                            chip(p.name, filter == p.id) { filter = p.id }
                                .contextMenu {
                                    Button("编辑") { editPhase = p }
                                    Button("删除", role: .destructive) { st.phases.removeAll { $0.id == p.id }; if filter == p.id { filter = nil } }
                                }
                        }
                        Button { editPhase = Phase() } label: {
                            Label("阶段", systemImage: "plus").font(.subheadline.bold())
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(Capsule().strokeBorder(Color.primary.opacity(0.2)))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 2)
                }
                if let p = phase {
                    HStack {
                        Text("\(p.name) · \(p.range)").font(.footnote).foregroundStyle(.secondary)
                        Spacer()
                        Button("编辑") { editPhase = p }.font(.footnote.bold())
                    }
                }
            } footer: {
                Text("阶段自己定义，比如增肌期、减脂期、备赛期，填开始和结束日期。长按阶段可以编辑或删除。")
            }

            if st.anchors.isEmpty {
                Section {
                    Text("加一个锚点：选一个动作，定一个固定的重量和次数，比如 卧推 80kg × 8。之后每次练这个动作，都拿来跟锚点比，看次数和重量是上升还是下降。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            ForEach(st.anchors) { a in
                anchorSection(a)
            }
            Section {
                Button { editAnchor = Anchor() } label: { Label("加锚点", systemImage: "scope") }
            }
        }
        .navigationTitle("阶段对比")
        .sheet(item: $editPhase) { p in PhaseEditor(p: p) }
        .sheet(item: $editAnchor) { a in AnchorEditor(a: a) }
    }

    private func chip(_ t: String, _ on: Bool, _ action: @escaping () -> Void) -> some View {
        Button { withAnimation(.snappy) { action() }; Haptic.tap() } label: {
            Text(t).font(.subheadline.bold())
                .padding(.horizontal, 14).padding(.vertical, 7)
                .foregroundStyle(on ? Color(.systemBackground) : Color.primary)
                .background(Capsule().fill(on ? Color.primary : Color(.tertiarySystemFill)))
        }
        .buttonStyle(.plain)
    }

    private struct Hit { let date: String; let label: String; let dReps: Double?; let dKg: Double? }

    // 每次练这个动作，跟锚点比：
    // 做到锚点重量 → 比次数；没到锚点重量但次数够 → 比重量；都不够 → 只显示
    private func hits(_ a: Anchor) -> [Hit] {
        let kg = Double(a.kg) ?? 0, reps = Double(a.reps) ?? 0
        var out: [Hit] = []
        for w in store.sorted where phase?.contains(w.date) ?? true {
            guard let x = w.exercises.first(where: { $0.name == a.name }), !x.sets.isEmpty else { continue }
            let sets = x.sets.filter { $0.weight > 0 || $0.reps > 0 }
            guard !sets.isEmpty else { continue }
            if let s = sets.filter({ abs($0.weight - kg) < 0.01 }).max(by: { $0.reps < $1.reps }) {
                out.append(Hit(date: w.date, label: setLabel(s), dReps: s.reps - reps, dKg: nil))
            } else if let s = sets.filter({ $0.reps >= reps }).max(by: { $0.weight < $1.weight }) {
                out.append(Hit(date: w.date, label: setLabel(s), dReps: nil, dKg: s.weight - kg))
            } else if let s = sets.max(by: { $0.weight < $1.weight }) {
                out.append(Hit(date: w.date, label: setLabel(s), dReps: nil, dKg: s.weight - kg))
            }
        }
        return out
    }

    @ViewBuilder private func anchorSection(_ a: Anchor) -> some View {
        let hs = hits(a)
        let up = hs.filter { ($0.dReps ?? $0.dKg ?? 0) > 0 }.count
        let down = hs.filter { ($0.dReps ?? $0.dKg ?? 0) < 0 }.count
        Section {
            HStack(spacing: 14) {
                summary("\(hs.count)", "次", .primary)
                summary("\(up)", "高于锚点", Color(hex: 0x2f9e44))
                summary("\(down)", "低于锚点", Color(hex: 0xe03131))
            }
            if hs.isEmpty {
                Text(phase == nil ? "还没练过这个动作" : "这个阶段没练过这个动作").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(hs.prefix(30), id: \.date) { h in
                HStack {
                    Text(slashDate(h.date)).font(.subheadline).monospacedDigit().foregroundStyle(.secondary).frame(width: 56, alignment: .leading)
                    Text(h.label).font(.subheadline.bold()).monospacedDigit()
                    Spacer()
                    if let d = h.dReps {
                        Text(d == 0 ? "次数持平" : "次数 " + diffText(d, 0)).font(.caption.bold()).foregroundStyle(diffColor(d, 0))
                    } else if let d = h.dKg {
                        Text(d == 0 ? "重量持平" : "重量 " + diffText(d, 0, "kg")).font(.caption.bold()).foregroundStyle(diffColor(d, 0))
                    }
                }
            }
        } header: {
            HStack {
                Text("\(a.name) · 锚点 \(a.kg)kg × \(a.reps)")
                Spacer()
                Menu {
                    Button("编辑") { editAnchor = a }
                    Button("删除", role: .destructive) { st.anchors.removeAll { $0.id == a.id } }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
    }

    private func summary(_ v: String, _ t: String, _ c: Color) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.system(size: 24, weight: .heavy, design: .rounded)).foregroundStyle(c)
            Text(t).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct PhaseEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var st = AnchorStore.shared
    @State var p: Phase
    @State private var hasEnd = false

    var body: some View {
        NavigationStack {
            Form {
                Section("名称") {
                    TextField("比如 增肌期", text: $p.name)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(["增肌期", "减脂期", "维持期", "备赛期", "恢复期"], id: \.self) { n in
                                Button(n) { p.name = n }.buttonStyle(.bordered).buttonBorderShape(.capsule)
                            }
                        }
                    }
                }
                Section("时间") {
                    DatePicker("开始", selection: Binding(get: { Day.date(p.start) }, set: { p.start = Day.str($0) }), displayedComponents: .date)
                    Toggle("有结束日期", isOn: $hasEnd)
                    if hasEnd {
                        DatePicker("结束", selection: Binding(get: { Day.date(p.end.isEmpty ? Day.today : p.end) }, set: { p.end = Day.str($0) }),
                                   in: Day.date(p.start)..., displayedComponents: .date)
                    }
                }
            }
            .navigationTitle("阶段").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if !hasEnd { p.end = "" } else if p.end.isEmpty { p.end = Day.today }
                        if let i = st.phases.firstIndex(where: { $0.id == p.id }) { st.phases[i] = p } else { st.phases.append(p) }
                        Haptic.success(); dismiss()
                    }
                    .bold().disabled(p.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { hasEnd = !p.end.isEmpty }
        }
    }
}

struct AnchorEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var st = AnchorStore.shared
    @State var a: Anchor

    private var names: [String] {
        let all = store.allExerciseNames.filter { Parts.of($0) != "有氧" }
        let q = a.name.trimmingCharacters(in: .whitespaces)
        return Array((q.isEmpty ? all : all.filter { $0.contains(q) && $0 != q }).prefix(12))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("动作，比如 卧推", text: $a.name)
                    if !names.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(names, id: \.self) { n in
                                    Button(n) { pick(n) }.buttonStyle(.bordered).buttonBorderShape(.capsule)
                                }
                            }
                        }
                    }
                } header: { Text("动作") }
                Section {
                    HStack {
                        TextField("重量", text: $a.kg).keyboardType(.decimalPad).multilineTextAlignment(.center)
                        Text("kg ×").foregroundStyle(.secondary)
                        TextField("次数", text: $a.reps).keyboardType(.numberPad).multilineTextAlignment(.center)
                        Text("次").foregroundStyle(.secondary)
                    }
                    .font(.title3.bold())
                } header: { Text("锚点（固定的重量和次数）") } footer: {
                    Text("做到锚点重量时比次数；没做到这个重量、但次数够时比重量。")
                }
            }
            .navigationTitle("锚点").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        a.name = a.name.trimmingCharacters(in: .whitespaces)
                        if let i = st.anchors.firstIndex(where: { $0.id == a.id }) { st.anchors[i] = a } else { st.anchors.append(a) }
                        Haptic.success(); dismiss()
                    }
                    .bold().disabled(a.name.trimmingCharacters(in: .whitespaces).isEmpty || Double(a.kg) == nil || Double(a.reps) == nil)
                }
            }
        }
    }

    // 选动作时，用最近一次最重的一组当默认锚点
    private func pick(_ n: String) {
        a.name = n
        if a.kg.isEmpty, let x = store.sorted.lazy.compactMap({ $0.exercises.first { $0.name == n } }).first,
           let s = x.sets.filter({ $0.weight > 0 }).max(by: { $0.weight < $1.weight }) {
            a.kg = s.w; a.reps = s.r
        }
    }
}
