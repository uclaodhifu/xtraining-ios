import SwiftUI
import Charts

// 体重记录
struct WeightView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var kg = ""
    @State private var day = Date()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DatePicker("日期", selection: $day, in: ...Date(), displayedComponents: .date)
                    HStack {
                        TextField("体重", text: $kg).keyboardType(.decimalPad)
                        Text("kg").foregroundStyle(.secondary)
                        Button("记下") {
                            if let v = Double(kg.replacingOccurrences(of: ",", with: ".")), v > 0 {
                                store.logWeight(v, on: Day.str(day)); kg = ""; Haptic.success(); hideKeyboard()
                            }
                        }
                        .bold().disabled(Double(kg) == nil)
                    }
                }
                if store.weights.count > 1 {
                    Section("最近变化") {
                        let rows = Array(store.weights.suffix(60))
                        let lo = (rows.map { $0.kg }.min() ?? 0) - 1
                        let hi = (rows.map { $0.kg }.max() ?? 0) + 1
                        Chart(rows) { r in
                            LineMark(x: .value("日期", Day.date(r.date)), y: .value("kg", r.kg))
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(Brand.gradient)
                            PointMark(x: .value("日期", Day.date(r.date)), y: .value("kg", r.kg))
                                .foregroundStyle(Brand.pink).symbolSize(20)
                        }
                        .chartYScale(domain: lo...hi)
                        .frame(height: 180)
                        .padding(.vertical, 8)
                    }
                }
                Section("记录") {
                    if store.weights.isEmpty { Text("还没有记录").foregroundStyle(.secondary) }
                    ForEach(Array(store.weights.reversed())) { r in
                        HStack {
                            Text(Day.label(r.date))
                            Spacer()
                            Text("\(fmtNum(r.kg)) kg").monospacedDigit().bold()
                        }
                    }
                    .onDelete { idx in
                        let rev = Array(store.weights.reversed())
                        let ids = Set(idx.map { rev[$0].date })
                        store.weights.removeAll { ids.contains($0.date) }
                    }
                }
            }
            .navigationTitle("体重").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}
