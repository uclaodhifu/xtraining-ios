import SwiftUI

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

    init(workout: Workout) { _workout = State(initialValue: workout) }

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
            ScrollView {
                VStack(spacing: 14) {
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
            .safeAreaInset(edge: .bottom) { RestBar(exercise: workout.exercises.last?.name ?? "") }
            .background(Color(.systemGroupedBackground))
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
        .card()
    }

    // 训练本表格
    private var notebook: some View {
        let hist = history
        let paper = Color(.secondarySystemGroupedBackground)
        return VStack(spacing: 0) {
            // 黑色标题栏
            Text(workout.title.isEmpty ? (workout.parts.isEmpty ? "分 化" : workout.parts.joined(separator: " · ")) : workout.title)
                .font(.headline).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 10)
                .background(Color(hex: 0x1c1c1e))
            // 日期行
            HStack(spacing: 0) {
                Text("日期").font(.caption.bold()).frame(width: labelW)
                ForEach(hist) { w in
                    Text(slashDate(w.date)).font(.caption.bold()).monospacedDigit().foregroundStyle(.secondary)
                        .frame(width: histW)
                        .overlay(alignment: .leading) { vline }
                }
                Text("今天 \(slashDate(workout.date))").font(.caption.bold()).foregroundStyle(workout.parts.first.map(Parts.color) ?? Color.primary)
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .leading) { vline }
            }
            .frame(height: 34)
            .padding(.leading, 6)
            hline
            if workout.exercises.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "square.and.pencil").font(.title).foregroundStyle(Brand.gradient)
                    Text("在下面加动作，或者点「照着上次练」").font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 28)
            }
            ForEach(Array(workout.exercises.enumerated()), id: \.element.id) { i, ex in
                exerciseBlock(i, exBinding(ex.id), hist)
                    .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
                hline
            }
        }
        .background(paper)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
        .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
    }

    private var hline: some View { Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 1) }
    private var vline: some View { Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1) }

    @ViewBuilder private func exerciseBlock(_ i: Int, _ x: Binding<Exercise>, _ hist: [Workout]) -> some View {
        let name = x.wrappedValue.name
        let prev = store.sorted.first { $0.id != workout.id && $0.date <= workout.date && $0.exercises.contains { $0.name == name } }?
            .exercises.first { $0.name == name }
        let t = trend(x.wrappedValue, prev)
        let color = Parts.of(name).map(Parts.color) ?? Brand.pink
        VStack(spacing: 0) {
            // 动作名
            HStack(spacing: 8) {
                Text("\(i + 1)").font(.caption.bold()).foregroundStyle(.white)
                    .frame(width: 22, height: 22).background(Circle().fill(color))
                TextField("动作名", text: x.name).font(.subheadline.bold())
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
            if x.wrappedValue.isCardio {
                HStack {
                    Text("时长").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    TextField("0", text: Binding(get: { x.wrappedValue.sets.first?.min ?? "" }, set: { v in
                        if x.wrappedValue.sets.isEmpty { x.wrappedValue.sets = [SetRow()] }
                        x.wrappedValue.sets[0].min = v
                    }))
                    .keyboardType(.decimalPad).multilineTextAlignment(.center).frame(width: 70)
                    .padding(.vertical, 6).background(RoundedRectangle(cornerRadius: 8).fill(Color(.tertiarySystemFill)))
                    Text("分钟").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12).padding(.bottom, 10)
            } else {
                ForEach(Array(x.wrappedValue.sets.enumerated()), id: \.element.id) { si, s in
                    HStack(spacing: 0) {
                        Text("组\(si + 1)").font(.caption.bold()).foregroundStyle(.secondary).frame(width: labelW)
                        ForEach(hist) { w in
                            let hs = w.exercises.first { $0.name == name }?.sets
                            Text(hs.flatMap { si < $0.count ? setLabel($0[si]) : nil } ?? "")
                                .font(.system(size: 16, weight: .semibold, design: .rounded)).monospacedDigit()
                                .foregroundStyle(Color.primary.opacity(0.8))
                                .lineLimit(1).minimumScaleFactor(0.6)
                                .frame(width: histW, height: 46)
                                .overlay(alignment: .leading) { vline }
                        }
                        HStack(spacing: 4) {
                            if let cfg = store.plateCfg[name] {
                                plateSteppers(x, s, cfg, t)
                            } else {
                                cellField(prevHint(prev, si, \.w, "kg"), setBinding(x, s.id, \.w), .decimalPad, t)
                            }
                            Text("×").font(.caption).foregroundStyle(.secondary)
                            cellField(prevHint(prev, si, \.r, "次"), setBinding(x, s.id, \.r), .numberPad, t)
                                .frame(maxWidth: store.plateCfg[name] != nil ? 56 : .infinity)
                        }
                        .padding(.horizontal, 6)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .overlay(alignment: .leading) { vline }
                    }
                    .padding(.leading, 6)
                    .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1) }
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
                set: { v in if let i = x.wrappedValue.sets.firstIndex(where: { $0.id == id }) { x.wrappedValue.sets[i][keyPath: k] = v } })
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

    private func cellField(_ hint: String, _ text: Binding<String>, _ kb: UIKeyboardType, _ t: Trend) -> some View {
        // 没填时显示上次的数字（亮一点的灰），填了按进步/退步变色，字号大，一眼能读
        TextField(text: text, prompt: Text(hint).foregroundStyle(Color.primary.opacity(0.42))) { EmptyView() }
            .keyboardType(kb).multilineTextAlignment(.center)
            .font(.system(size: 22, weight: .bold, design: .rounded)).monospacedDigit()
            .foregroundStyle(trendColor(t))
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(.tertiarySystemFill)))
    }

    // 加动作 + 照着上次练
    private var addCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("加动作，比如 卧推", text: $newName).onSubmit { add(newName); newName = "" }
                Button { add(newName); newName = "" } label: { Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(Color.primary) }
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
                                .background(Capsule().fill(Color(.tertiarySystemFill)))
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
                            HStack {
                                Image(systemName: "arrow.uturn.backward.circle.fill")
                                Text("照着上次练\(p)（\(slashDate(last.date))，\(todo.count) 个动作）")
                                Spacer()
                            }
                            .font(.subheadline.bold()).foregroundStyle(.white)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Parts.color(p)))
                        }
                        .buttonStyle(PressScale())
                    }
                }
            }
        }
        .card()
    }

    // 备注
    private var noteCard: some View {
        VStack(spacing: 0) {
            Text("备 注").font(.headline).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 8).background(Color(hex: 0x1c1c1e))
            VStack(alignment: .leading, spacing: 10) {
                Picker("感受", selection: Binding(get: { workout.mood ?? -1 }, set: { workout.mood = $0 < 0 ? nil : $0 })) {
                    Text("不记").tag(-1)
                    ForEach(Parts.moods.indices, id: \.self) { i in Text(Parts.moods[i]).tag(i) }
                }
                .pickerStyle(.segmented)
                TextField("今天状态、哪里不舒服……", text: $workout.note, axis: .vertical).lineLimit(3...6)
                    .background(alignment: .top) {
                        VStack(spacing: 22) { ForEach(0..<3, id: \.self) { _ in Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1) } }
                            .padding(.top, 21)
                    }
            }
            .padding(12)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
