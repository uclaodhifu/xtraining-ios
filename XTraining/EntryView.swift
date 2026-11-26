import SwiftUI
import PencilKit

// 记录一次训练：训练本样式。左边动作和组，中间是以前几次，最右一列今天填
struct EntryView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var workout: Workout
    @State private var newName = ""
    @State private var confirmDelete = false
    @State private var showMore = false
    @State private var plateFor: String? = nil
    @State private var infoFor: LibEx? = nil
    @State private var dragging: UUID? = nil
    @State private var writing: WriteCell? = nil   // 正在手写的格子
    @State private var addingByHand = false        // 全部手写模式：手写加动作
    @State private var nameInk: PKDrawing? = nil
    @State private var inkTick = 0
    @AppStorage(InputMode.key) private var inputMode = 0
    @State private var restored: Bool

    init(workout: Workout) {
        _workout = State(initialValue: workout)
        _restored = State(initialValue: !workout.exercises.isEmpty && EntryDraft.load()?.id == workout.id)
    }

    private var isNew: Bool { !store.workouts.contains { $0.id == workout.id } }
    private var dateBinding: Binding<Date> {
        Binding(get: { Day.date(workout.date) }, set: { workout.date = Day.str($0) })
    }
    // 以前两次练同样部位的训练（做表格的日期列）
    private var history: [Workout] {
        let ps = Set(workout.parts.filter { $0 != "有氧" })
        guard !ps.isEmpty else { return [] }
        return Array(store.sorted.filter { $0.id != workout.id && $0.date <= workout.date && !ps.isDisjoint(with: $0.parts) }.prefix(2).reversed())
    }
    private let labelW: CGFloat = 40
    private let histW: CGFloat = 68

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 14) {
                    if restored && isNew { draftBanner }
                    topCard
                    notebook
                    addCard
                    noteCard
                    if !isNew {
                        Button("删除这次训练", role: .destructive) { confirmDelete = true }
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 14).padding(.bottom, 40)
                .frame(maxWidth: 720).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            // 卡片拖到空白处松手，也要把“正在拖”的状态清掉，免得卡片一直是高亮的
            .dropDestination(for: CardDrag.self) { _, _ in dragging = nil; return true }
            .safeAreaInset(edge: .bottom) {
                // 写重量/次数时，底下换成手写板；写完收起来又是休息计时
                if addingByHand {
                    HandPad(value: $newName, title: "手写加动作", textMode: true, nextLabel: "加上这个动作",
                            onInk: { nameInk = $0 }, onNext: { addByHand() },
                            onClose: { withAnimation(.snappy) { addingByHand = false } })
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if let c = writing {
                    HandPad(value: cellBinding(c), title: cellTitle(c),
                            onInk: inputMode == 1 ? { saveInk(c, $0) } : nil,
                            onNext: { nextCell(c) },
                            onClose: { withAnimation(.snappy) { writing = nil } })
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    RestBar(exercise: workout.exercises.last?.name ?? "")
                }
            }
            // 打字（动作名、备注）时用系统键盘，手写板先收起
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                if writing != nil || addingByHand { withAnimation(.snappy) { writing = nil; addingByHand = false } }
            }
            .onChange(of: writing) { _, c in
                if let c { withAnimation(.snappy) { proxy.scrollTo(c.set, anchor: .center) } }
            }
            }
            .background(Color(.systemGroupedBackground))
            // 新的训练边记边存草稿，退出再进来还在
            .onChange(of: workout) { _, w in
                guard isNew else { return }
                if w.exercises.isEmpty && w.note.isEmpty { EntryDraft.clear() } else { EntryDraft.save(w) }
            }
            .navigationTitle(isNew ? "开始训练" : "修改训练")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.bold()
                        .disabled(workout.exercises.isEmpty && workout.parts.isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成") { hideKeyboard() } }
            }
            .sheet(item: $infoFor) { ExerciseInfoSheet(ex: $0) }
            .sheet(item: Binding(get: { plateFor.map(StrID.init) }, set: { plateFor = $0?.id })) { m in
                PlateSettings(name: m.id).presentationDetents([.medium])
            }
            .confirmationDialog("确定删除？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("删除", role: .destructive) { store.delete(workout); dismiss() }
            }
        }
    }

    // 接着上次没保存的记录
    private var draftBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.clockwise.circle.fill").font(.title3).foregroundStyle(Color(hex: 0x0a84ff))
            Text("已接上刚才没保存的记录").font(.subheadline.bold())
            Spacer()
            Button("清空重来") {
                EntryDraft.clear()
                var w = Workout(); w.parts = workout.parts
                withAnimation(.snappy) { workout = w; restored = false }
            }
            .font(.subheadline).foregroundStyle(.secondary)
        }
        .paperCard()
    }

    // 日期 + 部位
    private var topCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                DatePicker("", selection: dateBinding, in: ...Date(), displayedComponents: .date).labelsHidden()
                Spacer()
                TextField("分化名（可不填）", text: $workout.title).multilineTextAlignment(.trailing).font(.subheadline)
            }
            PartChips(parts: Parts.all, selected: $workout.parts)
        }
        .paperCard()
    }

    // 训练本表格
    private var notebook: some View {
        let hist = history
        let paper = Paper.bg
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return VStack(spacing: 10) {
            VStack(spacing: 0) {
                // 本子的抬头：手写日期 + 部位
                HStack(alignment: .firstTextBaseline) {
                    Text(slashDate(workout.date)).font(Paper.hand(26))
                    Text(workout.title.isEmpty ? (workout.parts.isEmpty ? "今天练什么" : workout.parts.joined(separator: " + ")) : workout.title)
                        .font(.system(size: 20, weight: .heavy))
                    Spacer()
                    Text("训练手记").font(.caption.bold()).foregroundStyle(Paper.pencil)
                }
                .foregroundStyle(Paper.ink)
                .padding(.horizontal, 16).padding(.vertical, 10)
                if workout.exercises.isEmpty {
                    Rectangle().fill(Paper.rule).frame(height: 1)
                    VStack(spacing: 6) {
                        Image(systemName: "square.and.pencil").font(.title).foregroundStyle(Brand.gradient)
                        Text("在下面加动作，或者点「照着上次练」").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 28)
                } else if workout.exercises.count > 1 {
                    Rectangle().fill(Paper.rule).frame(height: 1)
                    Label("按住动作卡片的空白处，可以拖动换顺序", systemImage: "hand.draw")
                        .font(.caption2).foregroundStyle(.secondary).padding(.vertical, 6)
                }
            }
            .background(paper)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(0.12)))

            // 每个动作一张卡片，按住拖动排序
            ForEach(Array(workout.exercises.enumerated()), id: \.element.id) { i, ex in
                let lifting = dragging == ex.id
                exerciseBlock(i, exBinding(ex.id), hist)
                    .padding(.bottom, 2)
                    .background(paper)
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(lifting ? (Parts.of(ex.name).map(Parts.color) ?? Brand.pink) : Color.primary.opacity(0.12),
                                                lineWidth: lifting ? 2 : 1))
                    .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
                    .contentShape(.dragPreview, shape)
                    .draggable(beginDrag(ex.id)) {
                        HStack(spacing: 8) {
                            Text("\(i + 1)").font(.caption.bold()).foregroundStyle(.white)
                                .frame(width: 24, height: 24).background(Circle().fill(Parts.of(ex.name).map(Parts.color) ?? Brand.pink))
                            Text(ex.name).font(.headline)
                            Text("\(ex.sets.count) 组").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .background(Capsule().fill(Color(.systemBackground)))
                    }
                    .dropDestination(for: CardDrag.self) { _, _ in
                        dragging = nil
                        Haptic.success()
                        return true
                    } isTargeted: { on in
                        // 拖到哪张卡上，就马上换到那个位置
                        guard on, let d = dragging, d != ex.id,
                              let from = workout.exercises.firstIndex(where: { $0.id == d }),
                              let to = workout.exercises.firstIndex(where: { $0.id == ex.id }) else { return }
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            workout.exercises.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
                        }
                        Haptic.tap()
                    }
                    .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
            }
        }
    }

    // 开始拖的时候记下是哪张卡（draggable 的内容在按住拖起时才取值）
    private func beginDrag(_ id: UUID) -> CardDrag {
        DispatchQueue.main.async {
            dragging = id; Haptic.tap(.medium)
            // 万一松手的地方没接住，几秒后也把描边去掉，不会一直亮着
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { if dragging == id { withAnimation { dragging = nil } } }
        }
        return CardDrag(id: id)
    }

    private var hline: some View { Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 1) }
    private var vline: some View { Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1) }

    @ViewBuilder private func exerciseBlock(_ i: Int, _ x: Binding<Exercise>, _ hist: [Workout]) -> some View {
        let name = x.wrappedValue.name
        let prev = store.sorted.first { $0.id != workout.id && $0.date <= workout.date && $0.exercises.contains { $0.name == name } }?
            .exercises.first { $0.name == name }
        let t = trend(x.wrappedValue, prev)
        let color = Parts.of(name).map(Parts.color) ?? Brand.pink
        // 这个动作自己最近练过的两次（不管那天练的是什么部位），旧的在左
        let mine = recent(name)
        VStack(spacing: 0) {
            // 动作名
            HStack(spacing: 8) {
                Text("\(i + 1)").font(.caption.bold()).foregroundStyle(.white)
                    .frame(width: 22, height: 22).background(Circle().fill(color))
                if inputMode == 1, let ink = x.wrappedValue.inkName {
                    InkView(id: ink, height: 26).frame(maxWidth: .infinity, alignment: .leading)   // 手写的动作名原样显示
                } else {
                    TextField("动作名", text: x.name).font(.subheadline.bold())
                }
                if let lib = ExerciseLib.find(name) {
                    Button { infoFor = lib } label: { Image(systemName: "info.circle").foregroundStyle(.secondary) }
                        .buttonStyle(.plain)
                }
                if t == .up || t == .down {
                    Image(systemName: t == .up ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                        .foregroundStyle(trendColor(t)).transition(.scale.combined(with: .opacity))
                }
                if !x.wrappedValue.isCardio {
                    Button { plateFor = name } label: {
                        Label("挂片", systemImage: store.plateCfg[name] != nil ? "circle.grid.2x1.fill" : "circle.grid.2x1")
                            .font(.caption.bold()).labelStyle(.titleAndIcon)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .foregroundStyle(store.plateCfg[name] != nil ? Color(.systemBackground) : Color.secondary)
                            .background(Capsule().fill(store.plateCfg[name] != nil ? Color.primary : Color(.tertiarySystemFill)))
                    }
                    .buttonStyle(.plain)
                }
                Button(role: .destructive) {
                    withAnimation(.snappy) { workout.exercises.removeAll { $0.id == x.wrappedValue.id } }
                } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .animation(.spring, value: t == .up)
            if !x.wrappedValue.isCardio, let pw = mine.last {
                // 本子的表头：组 | 上次几号 | 今天
                HStack(spacing: 0) {
                    Text("组").frame(width: labelW)
                    Text("上次 \(slashDate(pw.date))").frame(width: histW + 10)
                    Text("今天 · 重量 × 次数").frame(maxWidth: .infinity)
                }
                .font(.caption2.bold()).foregroundStyle(Paper.pencil)
                .frame(height: 22)
                .padding(.leading, 6)
                .overlay(alignment: .bottom) { Rectangle().fill(Paper.rule).frame(height: 1) }
                .overlay(alignment: .leading) { Rectangle().fill(Paper.margin).frame(width: 1.5).padding(.leading, labelW + 6) }
            }
            if x.wrappedValue.isCardio {
                HStack {
                    Text("时长").font(.caption).foregroundStyle(Paper.pencil)
                    Spacer()
                    TextField("0", text: Binding(get: { x.wrappedValue.sets.first?.min ?? "" }, set: { v in
                        if x.wrappedValue.sets.isEmpty { x.wrappedValue.sets = [SetRow()] }
                        x.wrappedValue.sets[0].min = v.filter { "0123456789.".contains($0) }
                    }))
                    .keyboardType(.decimalPad).multilineTextAlignment(.center).frame(width: 70)
                    .font(Paper.hand(24)).foregroundStyle(Paper.ink)
                    .overlay(alignment: .bottom) { Rectangle().fill(Paper.ink.opacity(0.3)).frame(height: 1.5) }
                    Text("分钟").font(.caption).foregroundStyle(Paper.pencil)
                }
                .padding(.horizontal, 12).padding(.bottom, 10)
            } else {
                let lastSets = mine.last?.exercises.first { $0.name == name }?.sets
                ForEach(Array(x.wrappedValue.sets.enumerated()), id: \.element.id) { si, s in
                    let ps: SetRow? = lastSets.flatMap { si < $0.count ? $0[si] : nil }
                    setLine(x, si, s, ps, prev, t, name)
                        .id(s.id)
                    .contextMenu {
                        Button("删掉这一组", role: .destructive) { withAnimation { x.wrappedValue.sets.removeAll { $0.id == s.id } } }
                    }
                }
                Button {
                    withAnimation(.snappy) { x.wrappedValue.sets.append(x.wrappedValue.sets.last.map { SetRow(w: $0.w, r: $0.r, p: $0.p) } ?? SetRow()) }
                    Haptic.tap()
                } label: {
                    Label("加一组", systemImage: "plus").font(.caption.bold()).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // 按 id 找，删掉某一行时不会越界
    private func exBinding(_ id: UUID) -> Binding<Exercise> {
        Binding(get: { workout.exercises.first { $0.id == id } ?? Exercise(name: "") },
                set: { v in if let k = workout.exercises.firstIndex(where: { $0.id == id }) { workout.exercises[k] = v } })
    }
    private func setBinding(_ x: Binding<Exercise>, _ id: UUID, _ k: WritableKeyPath<SetRow, String>) -> Binding<String> {
        Binding(get: { x.wrappedValue.sets.first { $0.id == id }?[keyPath: k] ?? "" },
                set: { v in
                    // 只收数字和小数点，别的东西（比如拖进来的文字）一律不要
                    let n = v.filter { "0123456789.".contains($0) }
                    if let i = x.wrappedValue.sets.firstIndex(where: { $0.id == id }) { x.wrappedValue.sets[i][keyPath: k] = n } })
    }

    // 挂片：每根挂杆一行  上 − 2 +，不用打字
    private func plateSteppers(_ x: Binding<Exercise>, _ s: SetRow, _ cfg: PlateCfg, _ t: Trend) -> some View {
        let p = s.p ?? Array(repeating: 0, count: cfg.pegs)
        return VStack(spacing: 3) {
            ForEach(0..<cfg.pegs, id: \.self) { k in
                HStack(spacing: 4) {
                    Text(cfg.labels[k]).font(.caption2).foregroundStyle(.secondary).frame(width: 16)
                    Button { bump(x, s.id, k, -1, cfg) } label: { Image(systemName: "minus.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(Color(.systemGray3))
                    Text("\(k < p.count ? p[k] : 0)").font(.system(size: 16, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(trendColor(t)).frame(minWidth: 18)
                        .contentTransition(.numericText()).animation(.snappy, value: k < p.count ? p[k] : 0)
                    Button { bump(x, s.id, k, 1, cfg) } label: { Image(systemName: "plus.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(Color.primary)
                }
                .font(.system(size: 18))
            }
            if s.p != nil { Text("\(fmtNum(cfg.total(p)))kg").font(.system(size: 9)).foregroundStyle(.secondary) }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
    }

    private func bump(_ x: Binding<Exercise>, _ id: UUID, _ k: Int, _ d: Int, _ cfg: PlateCfg) {
        guard let i = x.wrappedValue.sets.firstIndex(where: { $0.id == id }) else { return }
        var p = x.wrappedValue.sets[i].p ?? []
        if p.count < cfg.pegs { p += Array(repeating: 0, count: cfg.pegs - p.count) }
        p[k] = max(0, p[k] + d)
        x.wrappedValue.sets[i].p = p
        x.wrappedValue.sets[i].w = fmtNum(cfg.total(p))
        Haptic.tap()
    }

    private func prevHint(_ prev: Exercise?, _ i: Int, _ k: KeyPath<SetRow, String>, _ fallback: String) -> String {
        guard let p = prev, !p.sets.isEmpty else { return fallback }
        let v = p.sets[min(i, p.sets.count - 1)][keyPath: k]
        return v.isEmpty ? fallback : v
    }

    // 这个动作最近练过的两个不同日期（同一天重复的记录只算一次），旧的在左
    private func recent(_ name: String) -> [Workout] {
        var seen = Set<String>(), out: [Workout] = []
        for w in store.sorted where w.id != workout.id && w.date <= workout.date && w.exercises.contains(where: { $0.name == name }) {
            if seen.insert(w.date).inserted { out.append(w) }
            if out.count == 2 { break }
        }
        return out.reversed()
    }

    // 重量和次数分别跟上次同一组比：多了绿，少了红，一样黑
    private func cmp(_ cur: String, _ prev: Exercise?, _ i: Int, _ k: KeyPath<SetRow, String>) -> Trend {
        guard let a = Double(cur), let p = prev, !p.sets.isEmpty, let b = Double(p.sets[min(i, p.sets.count - 1)][keyPath: k]) else { return .none }
        return a > b ? .up : a < b ? .down : .same
    }

    private func cellField(_ hint: String, _ text: Binding<String>, _ cell: WriteCell, ink: String?) -> some View {
        let unit = hint == "kg" || hint == "次"
        let on = writing == cell
        return Group {
            if inputMode == 2 {
                // 用系统数字键盘
                TextField("", text: text)
                    .keyboardType(cell.weight ? .decimalPad : .numberPad).multilineTextAlignment(.center)
                    .font(Paper.hand(24)).monospacedDigit().foregroundStyle(Paper.ink)
                    .overlay {
                        if text.wrappedValue.isEmpty {
                            Text(hint).font(unit ? .system(size: 13, weight: .medium) : Paper.hand(22))
                                .foregroundStyle(Paper.pencil.opacity(unit ? 0.6 : 0.55)).allowsHitTesting(false)
                        }
                    }
                    .frame(minHeight: 38)
                    .overlay(alignment: .bottom) { Rectangle().fill(Paper.ink.opacity(text.wrappedValue.isEmpty ? 0.15 : 0.3)).frame(height: 1.5).padding(.horizontal, 6) }
            } else {
                // 不弹键盘：点一下格子，底下出手写板
                Button {
                    hideKeyboard(); Haptic.tap()
                    withAnimation(.snappy) { addingByHand = false; writing = cell }
                } label: {
                    ZStack {
                        if inputMode == 1, let ink, !text.wrappedValue.isEmpty {
                            InkView(id: ink, height: 32).id("\(ink)-\(inkTick)")    // 原样笔迹
                        } else if text.wrappedValue.isEmpty {
                            Text(hint)
                                .font(unit ? .system(size: 13, weight: .medium) : Paper.hand(22))
                                .foregroundStyle(Paper.pencil.opacity(unit ? 0.6 : 0.55))
                        } else {
                            Text(text.wrappedValue).font(Paper.hand(24)).monospacedDigit().foregroundStyle(Paper.ink)
                                .lineLimit(1).minimumScaleFactor(0.6)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(on ? Paper.ink.opacity(0.08) : .clear))
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Paper.ink.opacity(on ? 0.8 : (text.wrappedValue.isEmpty ? 0.15 : 0.3))).frame(height: on ? 2 : 1.5).padding(.horizontal, 6)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // 全部手写：把这一格的笔迹存起来（数字照样存着，统计照常算）
    private func saveInk(_ c: WriteCell, _ d: PKDrawing) {
        guard let i = workout.exercises.firstIndex(where: { $0.id == c.ex }),
              let k = workout.exercises[i].sets.firstIndex(where: { $0.id == c.set }) else { return }
        let old = c.weight ? workout.exercises[i].sets[k].inkW : workout.exercises[i].sets[k].inkR
        let id = old ?? UUID().uuidString
        InkStore.save(d, id: id)
        if c.weight { workout.exercises[i].sets[k].inkW = id } else { workout.exercises[i].sets[k].inkR = id }
        inkTick += 1   // 同一格重写时让笔迹图刷新
    }
    private func addByHand() {
        let n = newName.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        add(n)
        if let d = nameInk, let i = workout.exercises.lastIndex(where: { $0.name == n }) {
            let id = UUID().uuidString
            InkStore.save(d, id: id)
            workout.exercises[i].inkName = id
        }
        newName = ""; nameInk = nil
        withAnimation(.snappy) { addingByHand = false }
    }

    private func cellBinding(_ c: WriteCell) -> Binding<String> {
        Binding(get: {
            guard let x = workout.exercises.first(where: { $0.id == c.ex }), let s = x.sets.first(where: { $0.id == c.set }) else { return "" }
            return c.weight ? s.w : s.r
        }, set: { v in
            guard let i = workout.exercises.firstIndex(where: { $0.id == c.ex }),
                  let k = workout.exercises[i].sets.firstIndex(where: { $0.id == c.set }) else { return }
            if c.weight { workout.exercises[i].sets[k].w = v } else { workout.exercises[i].sets[k].r = v }
            if v.isEmpty { if c.weight { workout.exercises[i].sets[k].inkW = nil } else { workout.exercises[i].sets[k].inkR = nil } }
        })
    }
    private func cellTitle(_ c: WriteCell) -> String {
        guard let x = workout.exercises.first(where: { $0.id == c.ex }) else { return "" }
        let n = (x.sets.firstIndex { $0.id == c.set } ?? 0) + 1
        return "\(x.name) · 第\(n)组 · " + (c.weight ? "重量 kg" : "次数")
    }
    // 重量写完跳到次数；次数写完跳到下一组的重量（挂片的动作跳过重量）；最后一格写完收起
    private func nextCell(_ c: WriteCell) {
        guard let xi = workout.exercises.firstIndex(where: { $0.id == c.ex }),
              let si = workout.exercises[xi].sets.firstIndex(where: { $0.id == c.set }) else { writing = nil; return }
        let x = workout.exercises[xi]
        let plate = store.plateCfg[x.name] != nil
        var next: WriteCell? = nil
        if c.weight { next = WriteCell(ex: c.ex, set: c.set, weight: false) }
        else if si + 1 < x.sets.count { next = WriteCell(ex: c.ex, set: x.sets[si + 1].id, weight: !plate) }
        else {
            for y in workout.exercises[(xi + 1)...] where !y.isCardio {
                if let s = y.sets.first { next = WriteCell(ex: y.id, set: s.id, weight: store.plateCfg[y.name] == nil); break }
            }
        }
        withAnimation(.snappy) { writing = next }
    }

    // 本子里的一行：组号 | 上次（铅笔灰）| 今天（钢笔蓝手写）| 小章
    private func setLine(_ x: Binding<Exercise>, _ si: Int, _ s: SetRow, _ ps: SetRow?, _ prev: Exercise?, _ t: Trend, _ name: String) -> some View {
        let d = setDelta(s, ps)
        let isPR = (Double(s.w) ?? 0) > 0 && allBest(name).map { (Double(s.w) ?? 0) > $0 } == true
        return HStack(spacing: 0) {
                    Text("\(si + 1)").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(Paper.pencil).frame(width: labelW)
                    // 上次：铅笔灰
                    Text(ps.map(setLabel) ?? "—")
                        .font(.system(size: 15, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(Paper.pencil)
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .frame(width: histW + 10)
                    // 今天：钢笔蓝手写
                    HStack(spacing: 2) {
                        if let cfg = store.plateCfg[name] {
                            plateSteppers(x, s, cfg, t)
                        } else {
                            cellField(prevHint(prev, si, \.w, "kg"), setBinding(x, s.id, \.w), WriteCell(ex: x.wrappedValue.id, set: s.id, weight: true), ink: s.inkW)
                        }
                        Text("×").font(Paper.hand(18)).foregroundStyle(Paper.ink.opacity(0.6))
                        cellField(prevHint(prev, si, \.r, "次"), setBinding(x, s.id, \.r), WriteCell(ex: x.wrappedValue.id, set: s.id, weight: false), ink: s.inkR)
                            .frame(maxWidth: store.plateCfg[name] != nil ? 50 : .infinity)
                    }
                    .frame(maxWidth: .infinity)
                    // 写完自动盖个小章：+2.5kg / 持平 / 新纪录
                    Group {
                        if let d { DeltaTag(text: d.0, t: d.1, pr: isPR && ps != nil).transition(.scale.combined(with: .opacity)) }
                    }
                    .frame(width: 62, alignment: .trailing)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: d?.0)
                }
                .padding(.leading, 6).padding(.trailing, 8)
                .frame(minHeight: 48)
                .overlay(alignment: .bottom) { Rectangle().fill(Paper.rule).frame(height: 1) }
                .overlay(alignment: .leading) { Rectangle().fill(Paper.margin).frame(width: 1.5).padding(.leading, labelW + 6) }
    }

    // 这个动作以前（今天以前）最重的一次，用来判断新纪录
    private func allBest(_ name: String) -> Double? {
        store.workouts.filter { $0.id != workout.id && $0.date <= workout.date }
            .compactMap { $0.exercises.first { $0.name == name } }.map(\.best).filter { $0 > 0 }.max()
    }

    // 加动作 + 照着上次练
    private var addCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if inputMode == 1 {
                Button {
                    hideKeyboard(); writing = nil
                    withAnimation(.snappy) { addingByHand = true }
                } label: {
                    Label("手写加动作", systemImage: "pencil.and.scribble").font(.subheadline.bold())
                        .foregroundStyle(Paper.ink).frame(maxWidth: .infinity, minHeight: 40)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Paper.ink.opacity(0.06)))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Paper.ink.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                }
                .buttonStyle(.plain)
            }
            HStack {
                TextField("加动作，比如 卧推", text: $newName).onSubmit { add(newName); newName = "" }
                Button { add(newName); newName = "" } label: { Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(Paper.ink) }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            let suggest = suggestions
            if !suggest.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(suggest, id: \.self) { n in
                            Button { add(n); newName = "" } label: {
                                HStack(spacing: 6) {
                                    Circle().fill(Parts.of(n).map(Parts.color) ?? .gray).frame(width: 7, height: 7)
                                    Text(n).font(.footnote.weight(.medium)).foregroundStyle(Color.primary)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(Capsule().fill(Paper.ink.opacity(0.06)))
                            }
                            .buttonStyle(PressScale())
                        }
                    }
                }
            }
            ForEach(workout.parts.filter { $0 != "有氧" }, id: \.self) { p in
                if let last = store.lastSession(p, before: workout.date, skip: workout.id) {
                    let todo = last.exercises(of: p).filter { x in !workout.exercises.contains { $0.name == x.name } }
                    if !todo.isEmpty {
                        Button {
                            for x in todo { add(x.name, sets: x.sets.count) }
                        } label: {
                            // 不再用整块部位色，统一成本子里的墨蓝描边，部位色只留一个小圆点
                            HStack(spacing: 8) {
                                Circle().fill(Parts.color(p)).frame(width: 8, height: 8)
                                Text("照着上次练\(p)").font(.subheadline.bold())
                                Text("\(slashDate(last.date)) · \(todo.count) 个动作").font(.caption).foregroundStyle(Paper.pencil)
                                Spacer()
                                Image(systemName: "arrow.uturn.backward").font(.footnote.bold())
                            }
                            .foregroundStyle(Paper.ink)
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Paper.ink.opacity(0.06)))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Paper.ink.opacity(0.18)))
                        }
                        .buttonStyle(PressScale())
                    }
                }
            }
        }
        .paperCard()
    }

    // 备注
    private var noteCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("备注").font(.system(size: 17, weight: .heavy))
                Spacer()
                Text("今天感觉").font(.caption.bold()).foregroundStyle(Paper.pencil)
            }
            .foregroundStyle(Paper.ink)
            .padding(.horizontal, 14).padding(.top, 12)
            VStack(alignment: .leading, spacing: 10) {
                Picker("感受", selection: Binding(get: { workout.mood ?? -1 }, set: { workout.mood = $0 < 0 ? nil : $0 })) {
                    Text("不记").tag(-1)
                    ForEach(Parts.moods.indices, id: \.self) { i in Text(Parts.moods[i]).tag(i) }
                }
                .pickerStyle(.segmented)
                TextField("今天状态、哪里不舒服……", text: $workout.note, axis: .vertical).lineLimit(3...6)
                    .background(alignment: .top) {
                        VStack(spacing: 22) { ForEach(0..<3, id: \.self) { _ in Rectangle().fill(Paper.rule).frame(height: 1) } }
                            .padding(.top, 21)
                    }
            }
            .padding(12)
        }
        .background(Paper.bg)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
    }

    private func save() {
        for i in workout.exercises.indices {
            workout.exercises[i].name = workout.exercises[i].name.trimmingCharacters(in: .whitespaces)
        }
        workout.exercises.removeAll { $0.name.isEmpty }
        // 动作里认出来的部位也补进去
        for x in workout.exercises { if let p = Parts.of(x.name), !workout.parts.contains(p) { workout.parts.append(p) } }
        workout.parts = Parts.all.filter { workout.parts.contains($0) }
        store.upsert(workout)
        EntryDraft.clear()
        Haptic.success()
        dismiss()
    }

    private func add(_ name: String, sets: Int = 1) {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        let cardio = Parts.of(n) == "有氧"
        withAnimation {
            workout.exercises.append(Exercise(name: n, sets: (0..<(cardio ? 1 : max(1, sets))).map { _ in SetRow() }))
        }
        Haptic.tap()
    }

    private var suggestions: [String] {
        let have = Set(workout.exercises.map(\.name))
        let q = newName.trimmingCharacters(in: .whitespaces)
        var pool = store.allExerciseNames
        for p in (workout.parts.isEmpty ? Parts.all : workout.parts) { pool += Parts.library[p] ?? [] }
        var seen = Set<String>()
        pool = pool.filter { seen.insert($0).inserted && !have.contains($0) }
        if !q.isEmpty { return Array(pool.filter { $0.contains(q) }.prefix(12)) }
        if !workout.parts.isEmpty { pool = pool.filter { n in workout.parts.contains(Parts.of(n) ?? "") } }
        return Array(pool.prefix(12))
    }
}

func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

// 挂片设置：几根挂杆、每片多重、器械本身多重
struct PlateSettings: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let name: String
    @State private var on = false
    @State private var cfg = PlateCfg()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("用挂片记（不用打重量）", isOn: $on.animation())
                } footer: { Text("像 Prime 这类挂片器械：记录时点 + − 加减片数，训练本里显示成 2/1×8，自动算总重量来比进步。") }
                if on {
                    Section("器械") {
                        Stepper("挂杆：\(cfg.pegs) 根（\(cfg.labels.joined(separator: "、"))）", value: $cfg.pegs, in: 1...3)
                        Picker("每片重量", selection: $cfg.kg) {
                            ForEach([20.0, 15, 10, 5, 2.5], id: \.self) { Text("\(fmtNum($0)) kg").tag($0) }
                        }
                        Stepper("器械自重：\(fmtNum(cfg.base)) kg", value: $cfg.base, in: 0...200, step: 2.5)
                    }
                }
            }
            .navigationTitle(name).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { store.plateCfg[name] = on ? cfg : nil; dismiss() }.bold()
                }
            }
            .onAppear { if let c = store.plateCfg[name] { cfg = c; on = true } }
        }
    }
}

struct StrID: Identifiable { let id: String }
