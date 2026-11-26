import SwiftUI

// 备赛训练计划：独立的一套训练内容，不受周期计划影响，也不改首页选的部位
struct PrepEx: Codable, Identifiable, Hashable {
    var id = UUID()
    var name = ""
    var sets = 4
    var reps = "8-12"          // 目标次数，可以写范围
    var note = ""
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
            Exercise(name: x.name, sets: (0..<(Parts.of(x.name) == "有氧" ? 1 : max(1, x.sets))).map { _ in SetRow() })
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
            .background(Color(.systemGroupedBackground))
            .navigationTitle(day.name).navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("\(i + 1)").font(.caption.bold()).foregroundStyle(.white)
                    .frame(width: 22, height: 22).background(Circle().fill(color))
                TextField("动作", text: bind(x.id, \.name)).font(.subheadline.bold())
                Button(role: .destructive) {
                    withAnimation(.snappy) { day.exercises.removeAll { $0.id == x.id } }
                } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                .buttonStyle(.plain)
            }
            HStack {
                if !cardio {
                    Stepper("\(x.sets) 组", value: bindInt(x.id), in: 1...10).fixedSize()
                    Text("×").foregroundStyle(.secondary)
                }
                TextField(cardio ? "时长，如 30分钟" : "次数，如 8-12", text: bind(x.id, \.reps))
                    .multilineTextAlignment(.trailing)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(.tertiarySystemFill)))
            }
            .font(.subheadline)
            TextField("备注（可不填）", text: bind(x.id, \.note)).font(.caption)
        }
        .padding(14)
        .background(shape.fill(Color(.secondarySystemGroupedBackground)))
        .overlay(shape.strokeBorder(lifting ? color : Color.primary.opacity(0.1), lineWidth: lifting ? 2 : 1))
        .opacity(lifting ? 0.55 : 1)
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
        .dropDestination(for: String.self) { _, _ in
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

    private func beginDrag(_ id: UUID) -> String {
        DispatchQueue.main.async { dragging = id; Haptic.tap(.medium) }
        return id.uuidString
    }
    private func bind(_ id: UUID, _ k: WritableKeyPath<PrepEx, String>) -> Binding<String> {
        Binding(get: { day.exercises.first { $0.id == id }?[keyPath: k] ?? "" },
                set: { v in if let i = day.exercises.firstIndex(where: { $0.id == id }) { day.exercises[i][keyPath: k] = v } })
    }
    private func bindInt(_ id: UUID) -> Binding<Int> {
        Binding(get: { day.exercises.first { $0.id == id }?.sets ?? 4 },
                set: { v in if let i = day.exercises.firstIndex(where: { $0.id == id }) { day.exercises[i].sets = v } })
    }

    private func add(_ n: String) {
        let t = n.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        withAnimation { day.exercises.append(PrepEx(name: t, sets: Parts.of(t) == "有氧" ? 1 : 4, reps: Parts.of(t) == "有氧" ? "30分钟" : "8-12")) }
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
