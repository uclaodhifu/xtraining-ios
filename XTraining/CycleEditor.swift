import SwiftUI

// 周期计划：几天一圈，每天练什么
struct CycleEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var c = Cycle()
    @State private var days: [CycleDay] = []
    @State private var today = 0

    static let presets: [(String, [[String]])] = [
        ("推拉腿", [["胸", "肩", "手臂"], ["背", "手臂"], ["腿"], []]),
        ("五分化", [["胸"], ["背"], ["腿"], ["肩"], ["手臂"], [], []]),
        ("上下肢", [["胸", "背", "肩"], ["腿"], [], ["胸", "背", "手臂"], ["腿"], []]),
        ("三分化", [["胸", "手臂"], ["背", "肩"], ["腿"], []]),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("开启周期计划", isOn: $c.on)
                } footer: { Text("开了以后，首页会按今天是第几天自动选好部位。") }
                Section("套用模板") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(Self.presets, id: \.0) { name, steps in
                                Button(name) { withAnimation { days = steps.map { CycleDay(parts: $0) }; c.on = true; today = 0 } }
                                    .buttonStyle(.bordered).buttonBorderShape(.capsule)
                            }
                        }
                    }
                }
                ForEach($days) { $d in
                    let i = days.firstIndex { $0.id == d.id } ?? 0
                    Section {
                        PartChips(parts: Parts.all, selected: $d.parts)
                        Toggle("今天是这一天", isOn: Binding(get: { today == i }, set: { if $0 { today = i } }))
                    } header: {
                        HStack {
                            Text("第 \(i + 1) 天 · \(Cycle.name(d.parts))")
                            Spacer()
                            if days.count > 1 {
                                Button { remove(d.id) } label: { Image(systemName: "minus.circle") }
                            }
                        }
                    }
                }
                Section {
                    Button { withAnimation { days.append(CycleDay(parts: [])) } } label: { Label("加一天", systemImage: "plus") }
                } footer: { Text("不选部位就是休息日。") }
            }
            .navigationTitle("周期计划").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        c.steps = days.map { $0.parts }
                        c.start = Cycle.startFor(today)
                        store.cycle = c
                        Haptic.success(); dismiss()
                    }.bold()
                }
            }
            .onAppear {
                c = store.cycle
                days = store.cycle.steps.map { CycleDay(parts: $0) }
                today = store.cycle.start.isEmpty ? 0 : store.cycle.index()
            }
        }
    }

    private func remove(_ id: UUID) {
        withAnimation {
            days.removeAll { $0.id == id }
            today = min(today, days.count - 1)
        }
    }
}

struct CycleDay: Identifiable {
    let id = UUID()
    var parts: [String]
}
