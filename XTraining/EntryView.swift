import SwiftUI

// 记录一次训练（新建或修改）
struct EntryView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var workout: Workout
    @State private var newName = ""
    @State private var confirmDelete = false

    init(workout: Workout) { _workout = State(initialValue: workout) }

    private var isNew: Bool { !store.workouts.contains { $0.id == workout.id } }
    private var dateBinding: Binding<Date> {
        Binding(get: { Day.date(workout.date) }, set: { workout.date = Day.str($0) })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("日期", selection: dateBinding, in: ...Date(), displayedComponents: .date)
                    TextField("标题（可不填，默认用部位名）", text: $workout.title)
                }
                Section("练了哪些部位") {
                    PartChips(parts: Parts.all, selected: $workout.parts)
                        .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                }
                lastSessions
                ForEach($workout.exercises) { $x in
                    ExerciseSection(x: $x, last: store.lastSet(x.name)) {
                        withAnimation { workout.exercises.removeAll { $0.id == x.id } }
                    }
                }
                addSection
                Section("感受") {
                    Picker("感受", selection: Binding(get: { workout.mood ?? -1 }, set: { workout.mood = $0 < 0 ? nil : $0 })) {
                        Text("不记").tag(-1)
                        ForEach(Parts.moods.indices, id: \.self) { i in Text(Parts.moods[i]).tag(i) }
                    }
                    .pickerStyle(.segmented)
                    TextField("备注，比如今天状态、哪里不舒服", text: $workout.note, axis: .vertical).lineLimit(2...5)
                }
                if !isNew {
                    Section {
                        Button("删除这次训练", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isNew ? "记录训练" : "修改训练")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.bold()
                        .disabled(workout.exercises.isEmpty && workout.parts.isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成") { hideKeyboard() } }
            }
            .confirmationDialog("确定删除？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("删除", role: .destructive) { store.delete(workout); dismiss() }
            }
        }
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
            workout.exercises.append(Exercise(name: n, sets: Array(repeating: SetRow(), count: cardio ? 1 : max(1, sets))))
        }
        Haptic.tap()
    }

    // 上次练这个部位的情况，可以一键照着练
    @ViewBuilder private var lastSessions: some View {
        ForEach(workout.parts.filter { $0 != "有氧" }, id: \.self) { p in
            if let last = store.lastSession(p, before: workout.date, skip: workout.id) {
                Section {
                    ForEach(last.exercises(of: p)) { x in
                        Button { add(x.name, sets: x.sets.count) } label: {
                            HStack(alignment: .firstTextBaseline) {
                                Text(x.name).foregroundStyle(.primary)
                                Spacer()
                                Text(setsText(x)).font(.caption.bold()).foregroundStyle(Parts.color(p)).lineLimit(1)
                            }
                        }
                    }
                    Button {
                        for x in last.exercises(of: p) where !workout.exercises.contains(where: { $0.name == x.name }) { add(x.name, sets: x.sets.count) }
                    } label: { Label("照着上次练", systemImage: "arrow.uturn.backward.circle.fill") }
                } header: {
                    HStack {
                        Circle().fill(Parts.color(p)).frame(width: 8, height: 8)
                        Text("上次练\(p) · \(Day.label(last.date)) · \(Day.ago(last.date))")
                    }
                }
            }
        }
    }

    private var addSection: some View {
        Section("加动作") {
            HStack {
                TextField("动作名，比如 卧推", text: $newName).onSubmit { add(newName); newName = "" }
                Button { add(newName); newName = "" } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            let suggest = suggestions
            if !suggest.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(suggest, id: \.self) { n in
                            Button(n) { add(n); newName = "" }
                                .font(.footnote).buttonStyle(.bordered).buttonBorderShape(.capsule)
                                .tint(Parts.of(n).map(Parts.color) ?? .gray)
                        }
                    }
                }
            }
        }
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

// 一个动作：每组重量 × 次数（有氧记分钟）
struct ExerciseSection: View {
    @Binding var x: Exercise
    let last: SetRow?
    let onDelete: () -> Void

    var body: some View {
        Section {
            if x.isCardio {
                HStack {
                    Text("时长")
                    Spacer()
                    TextField("0", text: cardioBinding).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
                    Text("分钟").foregroundStyle(.secondary)
                }
            } else {
                ForEach($x.sets) { $s in
                    HStack(spacing: 10) {
                        Text("第\((x.sets.firstIndex { $0.id == s.id } ?? 0) + 1)组").font(.subheadline).foregroundStyle(.secondary).frame(width: 52, alignment: .leading)
                        TextField(last?.w.isEmpty == false ? last!.w : "重量", text: $s.w)
                            .keyboardType(.decimalPad).multilineTextAlignment(.center)
                            .padding(.vertical, 6).background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                        Text("kg ×").font(.caption).foregroundStyle(.secondary)
                        TextField(last?.r.isEmpty == false ? last!.r : "次数", text: $s.r)
                            .keyboardType(.numberPad).multilineTextAlignment(.center)
                            .padding(.vertical, 6).background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .onDelete { x.sets.remove(atOffsets: $0) }
                Button {
                    // 新的一组照抄上一组
                    withAnimation { x.sets.append(x.sets.last.map { SetRow(w: $0.w, r: $0.r) } ?? SetRow()) }
                    Haptic.tap()
                } label: { Label("加一组", systemImage: "plus") }
            }
        } header: {
            HStack {
                Circle().fill(Parts.of(x.name).map(Parts.color) ?? .gray).frame(width: 8, height: 8)
                TextField("动作名", text: $x.name).font(.subheadline.bold()).textCase(nil).foregroundStyle(.primary)
                Spacer()
                if let l = last, !x.isCardio, !l.w.isEmpty || !l.r.isEmpty {
                    Text("上次 \(l.w.isEmpty ? "0" : l.w)×\(l.r.isEmpty ? "0" : l.r)").font(.caption2).textCase(nil)
                }
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }.font(.caption)
            }
        }
    }

    private var cardioBinding: Binding<String> {
        Binding(get: { x.sets.first?.min ?? "" }, set: { v in
            if x.sets.isEmpty { x.sets = [SetRow()] }
            x.sets[0].min = v
        })
    }
}

func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}
