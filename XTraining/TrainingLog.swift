import SwiftUI

enum Trend { case up, same, down, none }

// 和上一次同一动作比：最重一组更重、或同重量多做几次 = 进步；反过来 = 退步
func trend(_ a: Exercise, _ b: Exercise?) -> Trend {
    guard let b else { return .none }
    let ab = a.best, bb = b.best
    if ab > bb { return .up }
    if ab < bb { return .down }
    guard ab > 0 else { return .same }
    let ar = a.sets.filter { $0.weight == ab }.map(\.reps).max() ?? 0
    let br = b.sets.filter { $0.weight == bb }.map(\.reps).max() ?? 0
    return ar > br ? .up : ar < br ? .down : .same
}
func trendColor(_ t: Trend) -> Color {
    switch t { case .up: return Color(hex: 0x2f9e44); case .down: return Color(hex: 0xe03131); default: return .primary }
}
func setLabel(_ s: SetRow) -> String {
    if let pt = s.platesText { return s.r.isEmpty ? "\(pt)片" : "\(pt)×\(s.r)" }
    return s.w.isEmpty ? (s.r.isEmpty ? "—" : "\(s.r)次") : (s.r.isEmpty ? s.w : "\(s.w)×\(s.r)")
}

// 每个月可以指定一次训练当“初始重量”：这个月之后的训练都跟它比（不再跟上一次比）
// 存成 { "胸|2026-11": 训练id }
enum Baseline {
    static let key = "xt.baseline"
    static func all(_ data: Data) -> [String: String] { (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:] }
    static func id(_ data: Data, part: String, month: String) -> String? { all(data)[part + "|" + month] }
    static func toggle(_ data: inout Data, part: String, month: String, id: String) {
        var m = all(data); let k = part + "|" + month
        m[k] = m[k] == id ? nil : id
        data = (try? JSONEncoder().encode(m)) ?? data
    }
    // 这次训练该跟谁比：同月、在初始训练之后 → 初始那次；否则 → 上一次
    static func ref(_ data: Data, part: String, name: String, w: Workout, all hist: [Workout], prev: Exercise?) -> (Exercise?, Bool) {
        let month = String(w.date.prefix(7))
        guard let bid = id(data, part: part, month: month), bid != w.id,
              let bw = hist.first(where: { $0.id == bid }), bw.date <= w.date,
              let bx = bw.exercises(of: part).first(where: { $0.name == name }) else { return (prev, false) }
        return (bx, true)
    }
}

// 长按动作名：改它属于哪个部位
struct PartMenuItems: View {
    @EnvironmentObject var store: Store
    let name: String
    var body: some View {
        Section("「\(name)」算哪个部位") {
            ForEach(Parts.all, id: \.self) { p in
                Button { store.setPart(name, p); Haptic.success() } label: {
                    if Parts.of(name) == p { Label(p, systemImage: "checkmark") } else { Text(p) }
                }
            }
        }
    }
}

// 动作名的手写笔迹（最近一次写过的）
func inkName(_ name: String, part: String, in ws: [Workout]) -> String? {
    for w in ws.reversed() { if let x = w.exercises(of: part).first(where: { $0.name == name }), let ink = InkStore.has(x.inkName) { return ink } }
    return nil
}

// 训练日志表（竖屏）：固定显示最近几次（colCount）练这个部位的训练，不用左右滑
// 每格是那天这个动作最重的一组：手写的显示原样笔迹，下面小字是认出来的数字；比上次进步绿↑、退步红↓
struct TrainingLogTable: View {
    static let colCount = 4          // 竖屏显示最近几次训练
    @EnvironmentObject var store: Store
    let part: String
    var maxRows = 5
    @State private var showAll = false
    @AppStorage(Baseline.key) private var baseData = Data()
    var onOpen: (Workout) -> Void = { _ in }
    var onExpand: (() -> Void)? = nil

    // 同一天练两次合成一列
    private var history: [Workout] {
        let ws = store.workouts.filter { !$0.exercises(of: part).isEmpty }
            .sorted { $0.date != $1.date ? $0.date < $1.date : $0.createdAt < $1.createdAt }
        var out: [Workout] = []
        for w in ws {
            guard var last = out.last, last.date == w.date else { out.append(w); continue }
            for x in w.exercises(of: part) {
                if let k = last.exercises.firstIndex(where: { $0.name == x.name }) { last.exercises[k].sets += x.sets }
                else { last.exercises.append(x) }
            }
            for p in w.parts where !last.parts.contains(p) { last.parts.append(p) }
            out[out.count - 1] = last
        }
        return out
    }
    // 一个动作那天最重的一组（一样重取次数多的）
    private func top(_ x: Exercise) -> SetRow? {
        x.sets.filter { $0.weight > 0 || $0.reps > 0 || $0.p != nil }
            .max { ($0.weight, $0.reps) < ($1.weight, $1.reps) } ?? x.sets.last
    }
    private func original(_ w: Workout) -> Workout {
        store.workouts.filter { $0.date == w.date && !$0.exercises(of: part).isEmpty }.max { $0.createdAt < $1.createdAt } ?? w
    }

    var body: some View {
        let hist = history
        let cols = Array(hist.suffix(Self.colCount))
        let first = hist.count - cols.count
        let names = orderByLatest(cols)
        let rows = showAll ? names : Array(names.prefix(maxRows))
        let line = Color.primary.opacity(0.1)
        let nameW: CGFloat = 54, rowH: CGFloat = 66, headH: CGFloat = 34

        return VStack(alignment: .leading, spacing: 8) {
            if cols.isEmpty {
                Text("还没练过\(part)。记一次训练，这里就会出现表格。").font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 24)
            } else {
                VStack(spacing: 0) {
                    // 日期行：点日期打开那次训练修改，长按设本月初始重量
                    HStack(spacing: 0) {
                        Text("动作").font(.caption2).foregroundStyle(.secondary).frame(width: nameW, height: headH)
                        ForEach(Array(cols.enumerated()), id: \.offset) { _, w in
                            let isBase = Baseline.id(baseData, part: part, month: String(w.date.prefix(7))) == w.id
                            VStack(spacing: 0) {
                                Text(slashDate(w.date)).font(.caption.bold()).monospacedDigit()
                                if isBase { Text("初始").font(.system(size: 8, weight: .heavy)).foregroundStyle(Tone.gold) }
                            }
                            .foregroundStyle(w.date == Day.today ? Parts.color(part) : Color.primary)
                            .frame(maxWidth: .infinity).frame(height: headH)
                            .overlay(alignment: .leading) { Rectangle().fill(line).frame(width: 1) }
                            .contentShape(Rectangle())
                            .onTapGesture { onOpen(original(w)) }
                            .contextMenu {
                                Button { Baseline.toggle(&baseData, part: part, month: String(w.date.prefix(7)), id: w.id); Haptic.success() } label: {
                                    Label(isBase ? "取消初始重量" : "设为本月初始重量", systemImage: "flag")
                                }
                            }
                        }
                    }
                    ForEach(Array(rows.enumerated()), id: \.element) { ri, n in
                        HStack(spacing: 0) {
                            VStack(spacing: 2) {
                                Text("\(ri + 1)").font(.caption2.bold()).foregroundStyle(Parts.color(part))
                                if let ink = inkName(n, part: part, in: cols) { InkView(id: ink, height: 16) }
                                else { Text(n).font(.caption2.bold()).lineLimit(2).minimumScaleFactor(0.6).multilineTextAlignment(.center) }
                                if cols.contains(where: { $0.exercises.contains { $0.name == n && $0.isRP } }) {
                                    Text("（组内暂停）").font(.system(size: 8, weight: .bold)).foregroundStyle(.orange).lineLimit(1).minimumScaleFactor(0.6)
                                }
                            }
                            .frame(width: nameW, height: rowH)
                            .contentShape(Rectangle())
                            .contextMenu { PartMenuItems(name: n) }
                            ForEach(Array(cols.enumerated()), id: \.offset) { ci, w in
                                cell(n, w, hist, first + ci)
                                    .frame(maxWidth: .infinity).frame(height: rowH)
                                    .overlay(alignment: .leading) { Rectangle().fill(line).frame(width: 1) }
                                    .contentShape(Rectangle())
                                    .onTapGesture { onOpen(original(w)) }
                            }
                        }
                        .overlay(alignment: .top) { Rectangle().fill(line).frame(height: 1) }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.04)))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                HStack(spacing: 12) {
                    legend("arrow.up", .green, "进步")
                    legend("arrow.down", .red, "退步")
                    legend("equal", .primary, "持平")
                    Text("长按动作改部位").foregroundStyle(.secondary)
                    Spacer()
                    if names.count > maxRows {
                        Button(showAll ? "收起" : "全部 \(names.count) 个") { withAnimation(.snappy) { showAll.toggle() } }
                            .font(.caption.bold()).tint(Brand.pink)
                    }
                    if let onExpand {
                        Button { onExpand() } label: { Label("横屏看整月", systemImage: "arrow.up.left.and.arrow.down.right") }
                            .font(.caption.bold()).tint(Brand.pink)
                    }
                }
                .font(.caption2)
            }
        }
    }

    // 动作顺序：按最近一次训练里的顺序，最近没练的跟在后面
    private func orderByLatest(_ cols: [Workout]) -> [String] {
        var seen = Set<String>(), out: [String] = []
        for w in cols.reversed() { for x in w.exercises(of: part) where seen.insert(x.name).inserted { out.append(x.name) } }
        return out
    }

    private func legend(_ icon: String, _ c: Color, _ t: String) -> some View {
        HStack(spacing: 2) { Image(systemName: icon).foregroundStyle(c); Text(t).foregroundStyle(.secondary) }
    }

    @ViewBuilder private func cell(_ name: String, _ w: Workout, _ hist: [Workout], _ idx: Int) -> some View {
        if let x = w.exercises(of: part).first(where: { $0.name == name }), let s = top(x) {
            let last = hist[..<idx].reversed().lazy.compactMap { $0.exercises(of: self.part).first { $0.name == name } }.first
            let prev = Baseline.ref(baseData, part: part, name: name, w: w, all: hist, prev: last).0
            let t = trend(x, prev)
            let c: Color = t == .up ? Color(hex: 0x2f9e44) : t == .down ? Color(hex: 0xe03131) : .secondary
            let inked = InkStore.has(s.inkW) != nil || InkStore.has(s.inkR) != nil
            VStack(spacing: 1) {
                SetInkLabel(s: s, h: 26, font: .system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                    .foregroundStyle(inked ? Color.primary : (t == .up || t == .down ? c : .primary))
                if inked {
                    Text(setLabel(s)).font(.system(size: 10, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(c).lineLimit(1).minimumScaleFactor(0.6)
                }
            }
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topTrailing) {
                if t == .up || t == .down {
                    Image(systemName: t == .up ? "arrow.up" : "arrow.down").font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(c).padding(3)
                }
            }
        } else {
            Color.clear
        }
    }
}

// 首页的训练日志：上面选部位（左右滑），下面是表格
struct HomeLog: View {
    @EnvironmentObject var store: Store
    @State private var part = ""
    @State private var full = false
    @State private var prep = false
    var onOpen: (Workout) -> Void

    private var defaultPart: String {
        store.sorted.first?.parts.first { $0 != "有氧" } ?? "胸"
    }

    var body: some View {
        let p = part.isEmpty ? defaultPart : part
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("训练日志").font(.title3.bold())
                Spacer()
                Text("点日期可以修改").font(.caption2).foregroundStyle(.secondary)
                Button { Haptic.tap(); prep = true } label: {
                    Label("备赛", systemImage: "trophy.fill").font(.caption.bold())
                        .padding(.horizontal, 10).frame(height: 30)
                        .foregroundStyle(.white).background(Capsule().fill(Brand.gradient))
                }
                .buttonStyle(PressScale())
                Button { Haptic.tap(); full = true } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.footnote.bold()).frame(width: 30, height: 30)
                        .background(Circle().fill(Color(.tertiarySystemFill)))
                }
                .buttonStyle(PressScale())
                .accessibilityLabel("横屏全屏查看")
            }
            Picker("部位", selection: Binding(get: { p }, set: { v in withAnimation(.snappy) { part = v } })) {
                ForEach(Parts.strength, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)
            TrainingLogTable(part: p, onOpen: onOpen, onExpand: { Haptic.tap(); full = true })
                .id("\(p)-\(store.rev)")   // 改完训练回来马上刷新（不用切部位）
                .transition(.opacity)
        }
        .card()
        .fullScreenCover(isPresented: $full) { LogFullScreen(part: p) }
        .sheet(isPresented: $prep) { PrepLogView() }
    }
}

// 训练日志全屏：竖着横着都能看，手机转过来就跟着转
struct LogFullScreen: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var part: String
    @State private var month = String(Day.today.prefix(7))
    @State private var editing: Workout? = nil
    @State private var picking = false
    @State private var comparing = false
    @Environment(\.verticalSizeClass) private var vClass
    private var landscape: Bool { vClass == .compact }

    private func shift(_ n: Int) {
        let d = Calendar.current.date(byAdding: .month, value: n, to: Day.date(month + "-01")) ?? Date()
        withAnimation(.snappy) { month = String(Day.str(d).prefix(7)) }
    }

    var body: some View {
        NavigationStack {
            // 表格自己上下滚，日期行固定在表格顶上
            VStack(spacing: 12) {
                Picker("部位", selection: $part.animation(.snappy)) {
                    ForEach(Parts.strength, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
                if landscape {
                    MonthLogTable(part: part, month: month) { w in editing = w }
                        .id(part + month)   // 不要跟着数据刷新重建，不然横着滑会被弹回去
                        .frame(maxHeight: .infinity, alignment: .top)
                        .card()
                } else {
                    // 竖着拿：跟首页一样，最近 4 次；转横屏才看整月
                    ScrollView {
                        TrainingLogTable(part: part, maxRows: 99, onOpen: { w in editing = w })
                            .id("\(part)-\(store.rev)")
                            .card()
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 8)
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if landscape { ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 4) {
                        Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                        Button { picking = true } label: {
                            HStack(spacing: 3) {
                                Text(ymCN(month)).font(.headline).monospacedDigit()
                                Image(systemName: "chevron.down").font(.caption2.bold())
                            }
                            .foregroundStyle(Color.primary)
                        }
                        Button { shift(1) } label: { Image(systemName: "chevron.right") }
                            .disabled(month >= String(Day.today.prefix(7)))
                    }
                } }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 14) {
                        Button { comparing = true } label: { Label("对比", systemImage: "arrow.left.arrow.right") }
                        Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary) }
                    }
                }
            }
            .sheet(item: $editing) { w in EntryView(workout: w) }
            .sheet(isPresented: $picking) { MonthPicker(month: month) { month = $0 }.presentationDetents([.height(320)]) }
            .sheet(isPresented: $comparing) { MonthCompare(a: month) }
        }
        // 不强制横屏：竖着看，把手机转横就自动变横屏
        .onAppear { Orientation.allow(.allButUpsideDown) }
        .onDisappear { Orientation.set(.portrait) }
    }
}
