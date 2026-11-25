import SwiftUI

let mealKeys = ["早餐", "午餐", "晚餐", "加餐"]
let mealIcons = ["早餐": "sunrise.fill", "午餐": "sun.max.fill", "晚餐": "moon.stars.fill", "加餐": "carrot.fill"]

// 今日饮食
struct FoodCard: View {
    @EnvironmentObject var store: Store
    @State private var editing: String? = nil

    var body: some View {
        let day = store.food[Day.today] ?? [:]
        let total = day.values.reduce(0) { $0 + (Int($1.kcal) ?? 0) }
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("今日饮食").font(.title3.bold())
                Spacer()
                if total > 0 { Text("\(total) 千卡").font(.subheadline.bold()).foregroundStyle(Brand.pink) }
            }
            ForEach(mealKeys, id: \.self) { k in
                Button { editing = k } label: {
                    HStack(spacing: 10) {
                        Image(systemName: mealIcons[k] ?? "fork.knife").frame(width: 24).foregroundStyle(Brand.gradient)
                        Text(k).font(.subheadline.bold())
                        if let m = day[k] {
                            Text(m.t).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                            Spacer()
                            if let c = Int(m.kcal), c > 0 { Text("\(c)").font(.caption).foregroundStyle(.secondary) }
                        } else {
                            Text("还没记").font(.subheadline).foregroundStyle(.tertiary)
                            Spacer()
                            Image(systemName: "plus").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .card()
        .sheet(item: Binding(get: { editing.map(MealID.init) }, set: { editing = $0?.id })) { m in
            MealEditor(meal: m.id).presentationDetents([.medium, .large])
        }
    }
}

struct MealID: Identifiable { let id: String }

struct MealEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let meal: String
    @State private var text = ""
    @State private var kcal = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("吃了什么，比如 鸡胸肉 + 米饭", text: $text, axis: .vertical).lineLimit(2...4)
                    HStack {
                        TextField("千卡（可不填）", text: $kcal).keyboardType(.numberPad)
                        Text("千卡").foregroundStyle(.secondary)
                    }
                }
                if let lm = store.lastMeal(meal) {
                    let d = lm.0
                    let m = lm.1
                    Section("上次\(meal) · \(Day.label(d))") {
                        Button {
                            text = m.t; kcal = m.kcal; Haptic.tap()
                        } label: {
                            HStack {
                                Text(m.t).foregroundStyle(.primary)
                                Spacer()
                                Text("照抄").bold()
                            }
                        }
                    }
                }
                if store.food[Day.today]?[meal] != nil {
                    Section { Button("清空这一餐", role: .destructive) { store.setMeal(meal, Meal()); dismiss() } }
                }
            }
            .navigationTitle(meal).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { store.setMeal(meal, Meal(t: text, kcal: kcal)); Haptic.success(); dismiss() }.bold()
                }
            }
            .onAppear {
                let m = store.food[Day.today]?[meal]
                text = m?.t ?? ""; kcal = m?.kcal ?? ""
            }
        }
    }
}
