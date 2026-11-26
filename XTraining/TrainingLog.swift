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

// 训练日志表：横着是每次训练的日期，竖着是动作，格子里是 重量×次数
// 比上次进步绿色↑，退步红色↓，持平黑色
struct TrainingLogTable: View {
    @EnvironmentObject var store: Store
    let part: String
    var maxRows = 5
    @State private var showAll = false
    var onOpen: (Workout) -> Void = { _ in }
    var onExpand: (() -> Void)? = nil

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
        let rows = showAll ? all : Array(all.prefix(maxRows))
        let inked = cols.contains { w in w.exercises(of: part).contains { $0.sets.contains { $0.inkW != nil || $0.inkR != nil } } }
        let lineH: CGFloat = inked ? 26 : 15   // 有手写的：笔迹下面还要写认出来的数字
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
                    if let onExpand {
                        Button { onExpand() } label: {
                            Label(all.count > maxRows ? "展开全部 \(all.count) 个" : "展开横屏看", systemImage: "arrow.up.left.and.arrow.down.right")
                        }
                        .font(.caption.bold()).tint(Brand.pink)
                    } else if all.count > maxRows {
                        Button(showAll ? "收起" : "查看全部 \(all.count) 个") { withAnimation(.snappy) { showAll.toggle() } }
                            .font(.caption.bold()).tint(Brand.pink)
                    }
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
                    SetInkLabel(s: s, h: lineH - 2, font: .system(size: 11, weight: t == .none || t == .same ? .regular : .semibold, design: .rounded), num: true)   // 手写的组显示原样笔迹 + 小字数字
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
                .id(p)
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
                MonthLogTable(part: part, month: month) { w in editing = w }
                    .id(part + month)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .card()
            }
            .padding(.horizontal, 16).padding(.bottom, 8)
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
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
                }
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
