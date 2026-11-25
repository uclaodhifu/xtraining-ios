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
    switch t { case .up: return .green; case .down: return .red; default: return .primary }
}
func setLabel(_ s: SetRow) -> String {
    s.w.isEmpty ? (s.r.isEmpty ? "—" : "\(s.r)次") : (s.r.isEmpty ? s.w : "\(s.w)×\(s.r)")
}

// 训练日志表：横着是每次训练的日期，竖着是动作，格子里是 重量×次数
// 比上次进步绿色↑，退步红色↓，持平黑色
struct TrainingLogTable: View {
    @EnvironmentObject var store: Store
    let part: String
    var maxRows = 10
    var onOpen: (Workout) -> Void = { _ in }

    private var cols: [Workout] {
        store.workouts.filter { $0.parts.contains(part) && !$0.exercises(of: part).isEmpty }.sorted { $0.date < $1.date }
    }
    private var names: [String] {
        var seen = Set<String>(), out: [String] = []
        for w in cols.reversed() { for x in w.exercises(of: part) where seen.insert(x.name).inserted { out.append(x.name) } }
        return out
    }

    var body: some View {
        let cols = self.cols
        let all = names
        let rows = Array(all.prefix(maxRows))
        let lineH: CGFloat = 15
        let heights: [CGFloat] = rows.map { n in
            let m = cols.map { w in w.exercises(of: part).first { $0.name == n }?.sets.count ?? 0 }.max() ?? 1
            return CGFloat(max(1, m)) * lineH + 14
        }
        let nameW: CGFloat = 80, colW: CGFloat = 72, headH: CGFloat = 32
        let line = Color.primary.opacity(0.1)
        return VStack(alignment: .leading, spacing: 8) {
            if cols.isEmpty {
                Text("还没练过\(part)。记一次训练，这里就会出现表格。").font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 24)
            } else {
                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("动作").font(.caption.bold()).foregroundStyle(.secondary)
                            .frame(width: nameW, height: headH, alignment: .leading)
                        ForEach(rows.indices, id: \.self) { i in
                            HStack(alignment: .top, spacing: 4) {
                                Text("\(i + 1)").font(.caption2.bold()).foregroundStyle(Parts.color(part))
                                Text(rows[i]).font(.caption.bold()).lineLimit(2).minimumScaleFactor(0.7)
                            }
                            .padding(.top, 6)
                            .frame(width: nameW, height: heights[i], alignment: .topLeading)
                            .overlay(alignment: .top) { Rectangle().fill(line).frame(height: 1) }
                        }
                    }
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 0) {
                                ForEach(Array(cols.enumerated()), id: \.element.id) { ci, w in
                                    VStack(spacing: 0) {
                                        VStack(spacing: 0) {
                                            Text(slashDate(w.date)).font(.caption.bold()).monospacedDigit()
                                            Text(weekdayCN(w.date)).font(.system(size: 9)).foregroundStyle(.secondary)
                                        }
                                        .foregroundStyle(w.date == Day.today ? Parts.color(part) : Color.primary)
                                        .frame(width: colW, height: headH)
                                        ForEach(rows.indices, id: \.self) { i in
                                            cell(rows[i], cols, ci, lineH)
                                                .frame(width: colW, height: heights[i])
                                                .overlay(alignment: .top) { Rectangle().fill(line).frame(height: 1) }
                                        }
                                    }
                                    .overlay(alignment: .leading) { Rectangle().fill(line).frame(width: 1) }
                                    .contentShape(Rectangle())
                                    .onTapGesture { onOpen(w) }
                                    .id(w.id)
                                }
                            }
                        }
                        .onAppear { if let last = cols.last { proxy.scrollTo(last.id, anchor: .trailing) } }
                        .onChange(of: cols.count) { _, _ in if let last = cols.last { withAnimation { proxy.scrollTo(last.id, anchor: .trailing) } } }
                    }
                }
                HStack(spacing: 12) {
                    legend("arrow.up", .green, "进步")
                    legend("arrow.down", .red, "退步")
                    legend("equal", .primary, "持平")
                    Spacer()
                    if all.count > rows.count { Text("最近 \(rows.count) 个动作").font(.caption2).foregroundStyle(.secondary) }
                }
                .font(.caption2)
            }
        }
    }

    private func legend(_ icon: String, _ c: Color, _ t: String) -> some View {
        HStack(spacing: 2) { Image(systemName: icon).foregroundStyle(c); Text(t).foregroundStyle(.secondary) }
    }

    @ViewBuilder private func cell(_ name: String, _ cols: [Workout], _ ci: Int, _ lineH: CGFloat) -> some View {
        if let x = cols[ci].exercises(of: part).first(where: { $0.name == name }) {
            let prev = cols[..<ci].reversed().lazy.compactMap { $0.exercises(of: self.part).first { $0.name == name } }.first
            let t = trend(x, prev)
            VStack(spacing: 0) {
                ForEach(x.sets) { s in
                    Text(setLabel(s))
                        .font(.system(size: 11, weight: t == .none || t == .same ? .regular : .semibold, design: .rounded))
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                        .frame(height: lineH)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(trendColor(t))
            .overlay(alignment: .topTrailing) {
                if t == .up || t == .down {
                    Image(systemName: t == .up ? "arrow.up" : "arrow.down").font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(trendColor(t)).padding(3)
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
            }
            Picker("部位", selection: Binding(get: { p }, set: { v in withAnimation(.snappy) { part = v } })) {
                ForEach(Parts.strength, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)
            TrainingLogTable(part: p, onOpen: onOpen)
                .id(p)
                .transition(.opacity)
        }
        .card()
    }
}
