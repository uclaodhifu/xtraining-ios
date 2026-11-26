import SwiftUI

// 备赛训练计划：独立的一套训练内容，不受周期计划影响，也不改首页选的部位
struct PrepEx: Codable, Identifiable, Hashable {
    var id = UUID()
    var name = ""
    var sets = 4
    var reps = "8-12"          // 目标次数，可以写范围
    var note = ""
    var rows: [SetRow]? = nil  // 每组的重量、次数、挂片（和训练本一样）；旧数据没有，按 sets 补空行
    var cardio: Bool { Parts.of(name) == "有氧" }
    var setRows: [SetRow] { rows ?? (0..<max(1, cardio ? 1 : sets)).map { _ in SetRow() } }
}
struct PrepDay: Codable, Identifiable, Hashable {
    var id = UUID()
    var name = "训练 A"
    var exercises: [PrepEx] = []
}
struct PrepPlan: Codable, Hashable {
    var name = ""              // 比赛名
    var contest = ""           // 比赛日期 yyyy-MM-dd
    var days: [PrepDay] = []
    var next = 0               // 下次练第几天
}

@MainActor
final class PrepStore: ObservableObject {
    static let shared = PrepStore()
    @Published var plan: PrepPlan = {
        UserDefaults.standard.data(forKey: "xt.prep").flatMap { try? JSONDecoder().decode(PrepPlan.self, from: $0) } ?? PrepPlan()
    }() { didSet { UserDefaults.standard.set(try? JSONEncoder().encode(plan), forKey: "xt.prep") } }
    var active: Bool { !plan.days.isEmpty }
    var daysLeft: Int? { plan.contest.isEmpty ? nil : Day.between(Day.today, plan.contest) }

    // 开始某一天：生成一次训练，标题“备赛 · 训练 A”，组数照计划，数字空着
    func workout(for day: PrepDay) -> Workout {
        var w = Workout()
        w.title = "备赛 · " + day.name
        w.exercises = day.exercises.filter { !$0.name.isEmpty }.map { x in
            // 计划里填好的重量、次数、挂片直接带进来
            Exercise(name: x.name, sets: x.cardio ? [SetRow(min: x.setRows.first?.min ?? "")] : x.setRows.map { SetRow(w: $0.w, r: $0.r, p: $0.p) })
        }
        var ps: [String] = []
        for x in w.exercises { if let p = Parts.of(x.name), !ps.contains(p) { ps.append(p) } }
        w.parts = Parts.all.filter { ps.contains($0) }
        return w
    }
    func advance(after day: PrepDay) {
        guard let i = plan.days.firstIndex(where: { $0.id == day.id }) else { return }
        plan.next = (i + 1) % max(plan.days.count, 1)
    }
}

struct PrepView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var ps = PrepStore.shared
    @State private var editingDay: PrepDay? = nil
    @State private var starting: Workout? = nil
    @State private var editInfo = false

    private static let presets: [(String, [PrepDay])] = [
        ("备赛四分化", [
            PrepDay(name: "胸 + 三头", exercises: [PrepEx(name: "上斜哑铃卧推"), PrepEx(name: "器械平推"), PrepEx(name: "绳索夹胸", sets: 3, reps: "12-15"), PrepEx(name: "绳索下压", sets: 3, reps: "12-15"), PrepEx(name: "爬坡走", sets: 1, reps: "30分钟")]),
            PrepDay(name: "背 + 二头", exercises: [PrepEx(name: "引体向上"), PrepEx(name: "杠铃划船"), PrepEx(name: "高位下拉", sets: 3, reps: "10-12"), PrepEx(name: "哑铃弯举", sets: 3, reps: "12"), PrepEx(name: "爬坡走", sets: 1, reps: "30分钟")]),
            PrepDay(name: "腿", exercises: [PrepEx(name: "深蹲"), PrepEx(name: "腿举", reps: "12-15"), PrepEx(name: "罗马尼亚硬拉"), PrepEx(name: "腿弯举", sets: 3, reps: "12-15")]),
            PrepDay(name: "肩 + 摆姿势", exercises: [PrepEx(name: "哑铃推举"), PrepEx(name: "哑铃侧平举", reps: "15-20"), PrepEx(name: "反向飞鸟", sets: 3, reps: "15"), PrepEx(name: "规定动作练习", sets: 1, reps: "20分钟", note: "对着镜子过一遍全部规定动作")]),
        ]),
        ("备赛三分化", [
            PrepDay(name: "推", exercises: [PrepEx(name: "器械平推"), PrepEx(name: "哑铃推举"), PrepEx(name: "哑铃侧平举", reps: "15-20"), PrepEx(name: "绳索下压", sets: 3)]),
            PrepDay(name: "拉", exercises: [PrepEx(name: "引体向上"), PrepEx(name: "坐姿划船"), PrepEx(name: "反向飞鸟", sets: 3, reps: "15"), PrepEx(name: "哑铃弯举", sets: 3)]),
            PrepDay(name: "腿", exercises: [PrepEx(name: "深蹲"), PrepEx(name: "腿举"), PrepEx(name: "腿弯举", sets: 3), PrepEx(name: "提踵", sets: 4, reps: "15-20")]),
        ]),
    ]

    var body: some View {
        NavigationStack {
            List {
                // 比赛 + 倒计时
                Section {
                    Button { editInfo = true } label: {
                        HStack(spacing: 14) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(ps.plan.name.isEmpty ? "设置目标比赛" : ps.plan.name).font(.title3.bold())
                                Text(ps.plan.contest.isEmpty ? "填比赛名和日期，显示倒计时" : Day.label(ps.plan.contest) + " · " + weekText)
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let n = ps.daysLeft {
                                VStack(spacing: 0) {
                                    Text(n >= 0 ? "\(n)" : "已结束").font(.system(size: n >= 0 ? 34 : 18, weight: .heavy, design: .rounded))
                                        .foregroundStyle(Brand.gradient)
                                    if n >= 0 { Text("天").font(.caption2).foregroundStyle(.secondary) }
                                }
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                } footer: { Text("备赛计划是单独的一套训练，不会改动周期计划和首页选的部位。") }

                Section {
                    NavigationLink { PhysiqueView() } label: {
                        HStack {
                            Label("体态照片对比", systemImage: "figure.arms.open")
                            Spacer()
                            Text("\(PhotoStore.shared.list.count) 张").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                if ps.plan.days.isEmpty {
                    Section("从模板开始") {
                        ForEach(Self.presets, id: \.0) { name, days in
                            Button { withAnimation { ps.plan.days = days.map { var d = $0; d.id = UUID(); return d }; ps.plan.next = 0 } } label: {
                                Label(name + "（\(days.count) 天）", systemImage: "doc.on.doc")
                            }
                        }
                        Button { withAnimation { ps.plan.days = [PrepDay()] } } label: { Label("自己从头写", systemImage: "square.and.pencil") }
                    }
                }

                ForEach(Array(ps.plan.days.enumerated()), id: \.element.id) { i, d in
                    Section {
                        ForEach(d.exercises) { x in
                            HStack {
                                Circle().fill(Parts.of(x.name).map(Parts.color) ?? .gray).frame(width: 8, height: 8)
                                Text(x.name).font(.subheadline.bold())
                                Spacer()
                                Text(Parts.of(x.name) == "有氧" ? x.reps : "\(x.sets) 组 × \(x.reps)").font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                            }
                            if !x.note.isEmpty { Text(x.note).font(.caption).foregroundStyle(.secondary) }
                        }
                        Button {
                            Haptic.tap(.medium)
                            starting = ps.workout(for: d)
                            ps.advance(after: d)
                        } label: {
                            Label("开始「\(d.name)」", systemImage: "play.fill").font(.subheadline.bold())
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .foregroundStyle(.white)
                                .background(Capsule().fill(i == ps.plan.next ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.gray.opacity(0.6))))
                        }
                        .buttonStyle(.plain)
                        .disabled(d.exercises.isEmpty)
                    } header: {
                        HStack {
                            Text("第 \(i + 1) 天 · \(d.name)")
                            if i == ps.plan.next { Text("下次").font(.caption2.bold()).foregroundStyle(.white).padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(Brand.pink)) }
                            Spacer()
                            Button("编辑") { editingDay = d }.font(.caption.bold())
                        }
                    }
                }
                .onMove { ps.plan.days.move(fromOffsets: $0, toOffset: $1) }

                if !ps.plan.days.isEmpty {
                    Section {
                        Button { let d = PrepDay(name: "训练 " + String(UnicodeScalar(65 + min(ps.plan.days.count, 25))!)); ps.plan.days.append(d); editingDay = d } label: {
                            Label("加一天", systemImage: "plus")
                        }
                        Button("清空备赛计划", role: .destructive) { withAnimation { ps.plan = PrepPlan() } }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { RestBar() }
            .navigationTitle("备赛计划").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .sheet(item: $editingDay) { d in PrepDayEditor(day: d) }
            .sheet(item: $starting) { w in EntryView(workout: w) }
            .sheet(isPresented: $editInfo) { PrepInfoEditor().presentationDetents([.medium]) }
        }
    }

    private var weekText: String {
        guard let n = ps.daysLeft else { return "" }
        if n < 0 { return "比赛已结束" }
        return n == 0 ? "今天比赛！" : "还剩 \(n / 7) 周 \(n % 7) 天"
    }
}

struct PrepInfoEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var ps = PrepStore.shared
    @State private var name = ""
    @State private var date = Date().addingTimeInterval(86400 * 84)
    @State private var hasDate = true
    var body: some View {
        NavigationStack {
            Form {
                TextField("比赛名，比如 2027 春季健美赛", text: $name)
                Toggle("比赛日期", isOn: $hasDate)
                if hasDate { DatePicker("日期", selection: $date, in: Date()..., displayedComponents: .date) }
            }
            .navigationTitle("目标比赛").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { ps.plan.name = name; ps.plan.contest = hasDate ? Day.str(date) : ""; Haptic.success(); dismiss() }.bold()
                }
            }
            .onAppear {
                name = ps.plan.name
                if !ps.plan.contest.isEmpty { date = Day.date(ps.plan.contest) } else if !ps.plan.name.isEmpty { hasDate = false }
            }
        }
    }
}

struct PrepDayEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var ps = PrepStore.shared
    @State var day: PrepDay
    // 旧计划没有每组的数据：先补成固定的空行，不然每次刷新都换新行，输入框填不进去
    init(day: PrepDay) {
        var d = day
        for i in d.exercises.indices where d.exercises[i].rows == nil { d.exercises[i].rows = d.exercises[i].setRows }
        _day = State(initialValue: d)
    }
    @State private var newName = ""

    private var suggestions: [String] {
        let have = Set(day.exercises.map(\.name))
        var pool = store.allExerciseNames
        for p in Parts.all { pool += Parts.library[p] ?? [] }
        var seen = Set<String>()
        pool = pool.filter { seen.insert($0).inserted && !have.contains($0) }
        let q = newName.trimmingCharacters(in: .whitespaces)
        return Array((q.isEmpty ? pool : pool.filter { $0.contains(q) }).prefix(14))
    }

    @State private var dragging: UUID? = nil
    @State private var plateFor: String? = nil
    @State private var infoFor: LibEx? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("这一天叫什么").font(.caption.bold()).foregroundStyle(.secondary)
                        TextField("比如 胸 + 三头", text: $day.name).font(.headline)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).card()

                    if day.exercises.count > 1 {
                        Label("按住动作卡片的空白处，可以拖动换顺序", systemImage: "hand.draw")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    ForEach(Array(day.exercises.enumerated()), id: \.element.id) { i, x in
                        exCard(i, x)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            TextField("加动作，比如 卧推", text: $newName).onSubmit { add(newName) }
                            Button { add(newName) } label: { Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(Color.primary) }
                                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(suggestions, id: \.self) { n in
                                    Button { add(n) } label: {
                                        HStack(spacing: 6) {
                                            Circle().fill(Parts.of(n).map(Parts.color) ?? .gray).frame(width: 7, height: 7)
                                            Text(n).font(.footnote.weight(.medium)).foregroundStyle(Color.primary)
                                        }
                                        .padding(.horizontal, 12).padding(.vertical, 7)
                                        .background(Capsule().fill(Color(.tertiarySystemFill)))
                                    }
                                    .buttonStyle(PressScale())
                                }
                            }
                        }
                    }
                    .card()

                    if ps.plan.days.count > 1 {
                        Button("删掉这一天", role: .destructive) {
                            ps.plan.days.removeAll { $0.id == day.id }
                            ps.plan.next = min(ps.plan.next, max(ps.plan.days.count - 1, 0))
                            dismiss()
                        }
                        .padding(.top, 6)
                    }
                }
                .padding(.horizontal, 14).padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
            .dropDestination(for: CardDrag.self) { _, _ in dragging = nil; return true }
            .safeAreaInset(edge: .bottom) { RestBar(exercise: day.exercises.first?.name ?? "") }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(day.name).navigationBarTitleDisplayMode(.inline)
            .sheet(item: $infoFor) { ExerciseInfoSheet(ex: $0) }
            .sheet(item: Binding(get: { plateFor.map(StrID.init) }, set: { plateFor = $0?.id })) { m in
                PlateSettings(name: m.id).presentationDetents([.medium])
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成") { hideKeyboard() } }
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if let i = ps.plan.days.firstIndex(where: { $0.id == day.id }) { ps.plan.days[i] = day } else { ps.plan.days.append(day) }
                        Haptic.success(); dismiss()
                    }.bold()
                }
            }
        }
    }

    // 一个动作一张卡片：按住空白处拖动换顺序
    private func exCard(_ i: Int, _ x: PrepEx) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        let color = Parts.of(x.name).map(Parts.color) ?? Brand.pink
        let cardio = Parts.of(x.name) == "有氧"
        let lifting = dragging == x.id
        let rows = x.setRows
        let hist = recent(x.name)
        let cols: [Workout?] = Array(repeating: nil, count: 2 - hist.count) + hist
        let cfg = cardio ? nil : store.plateCfg[x.name]
        let line = Color.primary.opacity(0.12)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("\(i + 1)").font(.caption.bold()).foregroundStyle(.white)
                    .frame(width: 22, height: 22).background(Circle().fill(color))
                TextField("动作", text: bind(x.id, \.name)).font(.subheadline.bold())
                if let lib = ExerciseLib.find(x.name) {
                    Button { infoFor = lib } label: { Image(systemName: "info.circle").foregroundStyle(.secondary) }
                        .buttonStyle(.plain)
                }
                if !cardio {
                    Button { plateFor = x.name } label: {
                        Label("挂片", systemImage: cfg != nil ? "circle.grid.2x1.fill" : "circle.grid.2x1")
                            .font(.caption.bold()).labelStyle(.titleAndIcon)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .foregroundStyle(cfg != nil ? Color(.systemBackground) : Color.secondary)
                            .background(Capsule().fill(cfg != nil ? Color.primary : Color(.tertiarySystemFill)))
                    }
                    .buttonStyle(.plain)
                }
                Button(role: .destructive) {
                    withAnimation(.snappy) { day.exercises.removeAll { $0.id == x.id } }
                } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            if cardio {
                HStack {
                    Text("时长").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    TextField("30", text: rowBind(x.id, rows[0].id, \.min))
                        .keyboardType(.decimalPad).multilineTextAlignment(.center).frame(width: 70)
                        .padding(.vertical, 6).background(RoundedRectangle(cornerRadius: 8).fill(Color(.tertiarySystemFill)))
                    Text("分钟").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12).padding(.bottom, 10)
            } else {
                // 表头：上上次 / 上次 / 计划
                HStack(spacing: 0) {
                    Text("").frame(width: 40)
                    ForEach(Array(cols.enumerated()), id: \.offset) { _, w in
                        Text(w.map { slashDate($0.date) } ?? "").font(.caption.bold()).monospacedDigit().foregroundStyle(.secondary)
                            .frame(width: 68, height: 24)
                            .overlay(alignment: .leading) { Rectangle().fill(line).frame(width: 1) }
                    }
                    Text("计划").font(.caption.bold()).foregroundStyle(color)
                        .frame(maxWidth: .infinity, minHeight: 24)
                        .overlay(alignment: .leading) { Rectangle().fill(line).frame(width: 1) }
                }
                .padding(.leading, 6)
                ForEach(Array(rows.enumerated()), id: \.element.id) { si, r in
                    HStack(spacing: 0) {
                        Text("组\(si + 1)").font(.caption.bold()).foregroundStyle(.secondary).frame(width: 40)
                        ForEach(Array(cols.enumerated()), id: \.offset) { _, w in
                            let hs = w?.exercises.first { $0.name == x.name }?.sets
                            Text(hs.flatMap { si < $0.count ? setLabel($0[si]) : nil } ?? "")
                                .font(.system(size: 16, weight: .semibold, design: .rounded)).monospacedDigit()
                                .foregroundStyle(Color.primary.opacity(0.8))
                                .lineLimit(1).minimumScaleFactor(0.6)
                                .frame(width: 68, height: 46)
                                .overlay(alignment: .leading) { Rectangle().fill(line).frame(width: 1) }
                        }
                        HStack(spacing: 4) {
                            if let cfg { plates(x.id, r, cfg) }
                            else { cell("kg", rowBind(x.id, r.id, \.w), .decimalPad) }
                            Text("×").font(.caption).foregroundStyle(.secondary)
                            cell(x.reps.isEmpty ? "次" : x.reps, rowBind(x.id, r.id, \.r), .numberPad)
                                .frame(maxWidth: cfg != nil ? 56 : .infinity)
                        }
                        .padding(.horizontal, 6)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .overlay(alignment: .leading) { Rectangle().fill(line).frame(width: 1) }
                    }
                    .padding(.leading, 6)
                    .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1) }
                    .contextMenu {
                        if rows.count > 1 {
                            Button("删掉这一组", role: .destructive) { editRows(x.id) { $0.removeAll { $0.id == r.id } } }
                        }
                    }
                }
                Button {
                    editRows(x.id) { $0.append($0.last.map { SetRow(w: $0.w, r: $0.r, p: $0.p) } ?? SetRow()) }
                    Haptic.tap()
                } label: {
                    Label("加一组", systemImage: "plus").font(.caption.bold()).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.plain)
            }
            TextField("备注（可不填）", text: bind(x.id, \.note)).font(.caption)
                .padding(.horizontal, 12).padding(.bottom, 10)
        }
        .padding(.vertical, 4)
        .background(shape.fill(Color(.secondarySystemGroupedBackground)))
        .overlay(shape.strokeBorder(lifting ? color : Color.primary.opacity(0.1), lineWidth: lifting ? 2 : 1))
        .contentShape(.dragPreview, shape)
        .draggable(beginDrag(x.id)) {
            HStack(spacing: 8) {
                Text("\(i + 1)").font(.caption.bold()).foregroundStyle(.white)
                    .frame(width: 24, height: 24).background(Circle().fill(color))
                Text(x.name).font(.headline)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(Capsule().fill(Color(.systemBackground)))
        }
        .dropDestination(for: CardDrag.self) { _, _ in
            dragging = nil; Haptic.success(); return true
        } isTargeted: { on in
            guard on, let d = dragging, d != x.id,
                  let from = day.exercises.firstIndex(where: { $0.id == d }),
                  let to = day.exercises.firstIndex(where: { $0.id == x.id }) else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                day.exercises.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
            }
            Haptic.tap()
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func beginDrag(_ id: UUID) -> CardDrag {
        DispatchQueue.main.async { dragging = id; Haptic.tap(.medium) }
        return CardDrag(id: id)
    }
    private func bind(_ id: UUID, _ k: WritableKeyPath<PrepEx, String>) -> Binding<String> {
        Binding(get: { day.exercises.first { $0.id == id }?[keyPath: k] ?? "" },
                set: { v in if let i = day.exercises.firstIndex(where: { $0.id == id }) { day.exercises[i][keyPath: k] = v } })
    }
    // 改某个动作的组（第一次改时把旧数据的组数变成空行）
    private func editRows(_ id: UUID, _ f: (inout [SetRow]) -> Void) {
        guard let i = day.exercises.firstIndex(where: { $0.id == id }) else { return }
        var r = day.exercises[i].setRows
        withAnimation(.snappy) {
            f(&r)
            day.exercises[i].rows = r
            day.exercises[i].sets = r.count
        }
    }
    private func rowBind(_ id: UUID, _ rid: UUID, _ k: WritableKeyPath<SetRow, String>) -> Binding<String> {
        Binding(get: { day.exercises.first { $0.id == id }?.setRows.first { $0.id == rid }?[keyPath: k] ?? "" },
                set: { v in
                    guard let i = day.exercises.firstIndex(where: { $0.id == id }) else { return }
                    var r = day.exercises[i].setRows
                    if let j = r.firstIndex(where: { $0.id == rid }) { r[j][keyPath: k] = v; day.exercises[i].rows = r }
                })
    }
    // 这个动作最近练过的两个不同日期，旧的在左
    private func recent(_ name: String) -> [Workout] {
        var seen = Set<String>(), out: [Workout] = []
        for w in store.sorted where w.exercises.contains(where: { $0.name == name }) {
            if seen.insert(w.date).inserted { out.append(w) }
            if out.count == 2 { break }
        }
        return out.reversed()
    }
    private func cell(_ hint: String, _ text: Binding<String>, _ kb: UIKeyboardType) -> some View {
        TextField("", text: text)
            .keyboardType(kb).multilineTextAlignment(.center)
            .font(.system(size: 19, weight: .bold, design: .rounded)).monospacedDigit()
            .overlay {
                if text.wrappedValue.isEmpty {
                    Text(hint).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.primary.opacity(0.3))
                        .lineLimit(1).minimumScaleFactor(0.6).allowsHitTesting(false)
                }
            }
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(.tertiarySystemFill)))
    }
    // 挂片：每根挂杆一行 − 2 +
    private func plates(_ id: UUID, _ r: SetRow, _ cfg: PlateCfg) -> some View {
        let p = r.p ?? Array(repeating: 0, count: cfg.pegs)
        return VStack(spacing: 3) {
            ForEach(0..<cfg.pegs, id: \.self) { k in
                HStack(spacing: 4) {
                    Text(cfg.labels[k]).font(.caption2).foregroundStyle(.secondary).frame(width: 16)
                    Button { bump(id, r.id, k, -1, cfg) } label: { Image(systemName: "minus.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(Color(.systemGray3))
                    Text("\(k < p.count ? p[k] : 0)").font(.system(size: 16, weight: .bold, design: .rounded)).monospacedDigit()
                        .frame(minWidth: 18)
                    Button { bump(id, r.id, k, 1, cfg) } label: { Image(systemName: "plus.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(Color.primary)
                }
                .font(.system(size: 18))
            }
            if r.p != nil { Text("\(fmtNum(cfg.total(p)))kg").font(.system(size: 9)).foregroundStyle(.secondary) }
        }
        .padding(.vertical, 4).frame(maxWidth: .infinity)
    }
    private func bump(_ id: UUID, _ rid: UUID, _ k: Int, _ d: Int, _ cfg: PlateCfg) {
        editRows(id) { rows in
            guard let j = rows.firstIndex(where: { $0.id == rid }) else { return }
            var p = rows[j].p ?? []
            if p.count < cfg.pegs { p += Array(repeating: 0, count: cfg.pegs - p.count) }
            p[k] = max(0, p[k] + d)
            rows[j].p = p
            rows[j].w = fmtNum(cfg.total(p))
        }
        Haptic.tap()
    }
    private func bindInt(_ id: UUID) -> Binding<Int> {
        Binding(get: { day.exercises.first { $0.id == id }?.sets ?? 4 },
                set: { v in if let i = day.exercises.firstIndex(where: { $0.id == id }) { day.exercises[i].sets = v } })
    }

    private func add(_ n: String) {
        let t = n.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        var x = PrepEx(name: t, sets: Parts.of(t) == "有氧" ? 1 : 4, reps: Parts.of(t) == "有氧" ? "30分钟" : "8-12")
        x.rows = x.setRows
        withAnimation { day.exercises.append(x) }
        newName = ""
        Haptic.tap()
    }
}

// 训练日志里的“备赛”：按备赛计划的每一天，列出练过的每次（日期一列，格子里是 重量×次数，比上次进步绿、退步红）
struct PrepLogView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var ps = PrepStore.shared
    @State private var editing: Workout? = nil
    @State private var showPlan = false

    private func sessions(_ d: PrepDay) -> [Workout] {
        store.workouts.filter { $0.title == "备赛 · " + d.name }.sorted { $0.date < $1.date }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if !ps.active {
                        VStack(spacing: 10) {
                            Image(systemName: "trophy").font(.largeTitle).foregroundStyle(Brand.gradient)
                            Text("还没有备赛计划").font(.headline)
                            Button("去建备赛计划") { showPlan = true }.buttonStyle(.borderedProminent)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 40).card()
                    } else {
                        if let n = ps.daysLeft, n >= 0 {
                            HStack {
                                Text(ps.plan.name.isEmpty ? "备赛" : ps.plan.name).font(.headline)
                                Spacer()
                                Text("还有 \(n) 天").font(.headline).foregroundStyle(Brand.gradient)
                            }
                            .card()
                        }
                        ForEach(ps.plan.days) { d in dayTable(d) }
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("备赛训练日志").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("计划") { showPlan = true } }
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
            .sheet(item: $editing) { w in EntryView(workout: w) }
            .sheet(isPresented: $showPlan) { PrepView() }
        }
    }

    private func dayTable(_ d: PrepDay) -> some View {
        let ws = sessions(d)
        var names = d.exercises.map(\.name).filter { !$0.isEmpty }
        for w in ws { for x in w.exercises where !names.contains(x.name) { names.append(x.name) } }
        let lineH: CGFloat = 15, nameW: CGFloat = 92, colW: CGFloat = 72, headH: CGFloat = 32
        let heights: [CGFloat] = names.map { n in
            CGFloat(max(1, ws.map { w in w.exercises.first { $0.name == n }?.sets.count ?? 0 }.max() ?? 1)) * lineH + 14
        }
        let line = Color.primary.opacity(0.1)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(d.name).font(.headline)
                Spacer()
                Text(ws.isEmpty ? "还没练过" : "练了 \(ws.count) 次").font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("动作").font(.caption.bold()).foregroundStyle(.secondary).frame(width: nameW, height: headH, alignment: .leading)
                    ForEach(names.indices, id: \.self) { i in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(names[i]).font(.caption.bold()).lineLimit(2).minimumScaleFactor(0.7)
                            if let x = d.exercises.first(where: { $0.name == names[i] }) {
                                Text(Parts.of(x.name) == "有氧" ? x.reps : "\(x.sets)×\(x.reps)").font(.system(size: 9)).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.top, 6)
                        .frame(width: nameW, height: heights[i], alignment: .topLeading)
                        .overlay(alignment: .top) { Rectangle().fill(line).frame(height: 1) }
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(ws.enumerated()), id: \.element.id) { ci, w in
                            VStack(spacing: 0) {
                                Text(slashDate(w.date)).font(.caption.bold()).monospacedDigit().frame(width: colW, height: headH)
                                ForEach(names.indices, id: \.self) { i in
                                    cell(names[i], ws, ci, lineH)
                                        .frame(width: colW, height: heights[i])
                                        .overlay(alignment: .top) { Rectangle().fill(line).frame(height: 1) }
                                }
                            }
                            .overlay(alignment: .leading) { Rectangle().fill(line).frame(width: 1) }
                            .contentShape(Rectangle())
                            .onTapGesture { editing = w }
                        }
                    }
                }
                .defaultScrollAnchor(.trailing)
            }
        }
        .card()
    }

    @ViewBuilder private func cell(_ name: String, _ ws: [Workout], _ ci: Int, _ lineH: CGFloat) -> some View {
        if let x = ws[ci].exercises.first(where: { $0.name == name }) {
            let prev = ws[..<ci].reversed().lazy.compactMap { $0.exercises.first { $0.name == name } }.first
            let t = trend(x, prev)
            VStack(spacing: 0) {
                ForEach(x.sets) { s in
                    Text(x.isCardio ? (s.min.isEmpty ? "—" : "\(s.min)分") : setLabel(s))
                        .font(.system(size: 11, weight: t == .up || t == .down ? .semibold : .regular, design: .rounded))
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7).frame(height: lineH)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(trendColor(t))
        } else {
            Color.clear
        }
    }
}
