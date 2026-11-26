import SwiftUI

// 训练日志全屏（横屏）：按月排，1 号到月底每天一列
// 连续超过 3 天没练这个部位，就合成一列，比如“10–13”
struct MonthLogTable: View {
    @EnvironmentObject var store: Store
    let part: String
    let month: String            // "2026-11"
    var onOpen: (Workout) -> Void = { _ in }
    @State private var hx: CGFloat = 0     // 日期列左右滑了多少
    @AppStorage("xt.logOrder") private var orderData = Data()   // 每个部位自己拖好的动作顺序
    @State private var draggingRow: String? = nil

    private var order: [String: [String]] {
        get { (try? JSONDecoder().decode([String: [String]].self, from: orderData)) ?? [:] }
    }
    private func saveOrder(_ rows: [String]) {
        var o = order; o[part] = rows
        if let d = try? JSONEncoder().encode(o) { orderData = d }
    }
    // 按拖好的顺序排，没排过的动作（新练的）跟在后面
    private func ordered(_ rows: [String]) -> [String] {
        let saved = order[part] ?? []
        return rows.enumerated().sorted { a, b in
            let ia = saved.firstIndex(of: a.element) ?? Int.max, ib = saved.firstIndex(of: b.element) ?? Int.max
            return ia != ib ? ia < ib : a.offset < b.offset
        }.map(\.element)
    }

    enum Col: Identifiable {
        case day(String, Workout?)
        case gap(String, String)
        var id: String {
            switch self { case .day(let d, _): return d; case .gap(let a, let b): return a + "~" + b }
        }
    }

    // 这个部位练过的所有训练（全部历史，用来算“跟上次比”）
    private var history: [Workout] {
        store.workouts.filter { !$0.exercises(of: part).isEmpty }.sorted { $0.date < $1.date }
    }

    private var days: [String] {
        let first = month + "-01"
        let n = Calendar.current.range(of: .day, in: .month, for: Day.date(first))?.count ?? 30
        return (0..<n).map { Day.add(first, $0) }
    }

    private func columns(_ hist: [Workout]) -> [Col] {
        var byDay: [String: Workout] = [:]
        for w in hist where w.date.hasPrefix(month) && byDay[w.date] == nil { byDay[w.date] = w }
        var out: [Col] = [], run: [String] = []
        func flush() {
            if run.count > 3 { out.append(.gap(run.first!, run.last!)) } else { out += run.map { .day($0, nil) } }
            run = []
        }
        for d in days {
            if let w = byDay[d] { flush(); out.append(.day(d, w)) } else { run.append(d) }
        }
        flush()
        return out
    }

    var body: some View {
        let hist = history
        let cols = columns(hist)
        let inMonth = hist.filter { $0.date.hasPrefix(month) }
        var seen = Set<String>(), rows: [String] = []
        for w in inMonth.reversed() { for x in w.exercises(of: part) where seen.insert(x.name).inserted { rows.append(x.name) } }
        rows = ordered(rows)
        let lineH: CGFloat = 22
        let heights: [CGFloat] = rows.map { n in
            let m = inMonth.map { w in w.exercises(of: part).first { $0.name == n }?.sets.count ?? 0 }.max() ?? 1
            return CGFloat(max(1, m)) * lineH + 14 + 14
        }
        let nameW: CGFloat = 96, headH: CGFloat = 36
        let line = Color.primary.opacity(0.1)
        return VStack(alignment: .leading, spacing: 8) {
            if rows.isEmpty {
                Text("这个月还没练\(part)").font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 30)
            }
            // 冻结表头：日期行放在上下滚动区外面，永远停在顶上；左右滑时跟着日期一起走
            HStack(spacing: 0) {
                Text("动作").font(.caption.bold()).foregroundStyle(.secondary)
                    .frame(width: nameW, height: headH, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground))
                    .zIndex(1)
                HStack(spacing: 0) {
                    ForEach(cols) { c in header(c, headH: headH, line: line) }
                }
                .offset(x: hx)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
            }
            .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.18)).frame(height: 1) }
            ScrollView(.vertical, showsIndicators: true) {
                HStack(alignment: .top, spacing: 0) {
                    // 动作列：左右滑时不动
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(rows.indices, id: \.self) { i in
                            HStack(alignment: .top, spacing: 4) {
                                Text("\(i + 1)").font(.caption2.bold()).foregroundStyle(Parts.color(part))
                                Text(rows[i]).font(.caption.bold()).lineLimit(2).minimumScaleFactor(0.7)
                            }
                            .padding(.top, 6)
                            .frame(width: nameW, height: heights[i], alignment: .topLeading)
                            .background(draggingRow == rows[i] ? Parts.color(part).opacity(0.12) : .clear)
                            .overlay(alignment: .top) { Rectangle().fill(line).frame(height: 1) }
                            .contentShape(Rectangle())
                            // 按住动作名拖动，换上下顺序（每个部位单独记住）
                            .draggable(beginRowDrag(rows[i])) {
                                Text(rows[i]).font(.subheadline.bold())
                                    .padding(.horizontal, 14).padding(.vertical, 8)
                                    .background(Capsule().fill(Color(.systemBackground)))
                            }
                            .dropDestination(for: CardDrag.self) { _, _ in
                                draggingRow = nil; Haptic.success(); return true
                            } isTargeted: { on in
                                guard on, let d = draggingRow, d != rows[i],
                                      let from = rows.firstIndex(of: d), let to = rows.firstIndex(of: rows[i]) else { return }
                                var r = rows
                                r.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { saveOrder(r) }
                                Haptic.tap()
                            }
                        }
                    }
                    .background(Color(.secondarySystemGroupedBackground))
                    .overlay(alignment: .trailing) { Rectangle().fill(Color.primary.opacity(0.18)).frame(width: 1) }
                    .shadow(color: .black.opacity(hx < -1 ? 0.12 : 0), radius: 4, x: 3)
                    .zIndex(1)
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: true) {
                            HStack(alignment: .top, spacing: 0) {
                                ForEach(cols) { c in
                                    column(c, rows: rows, heights: heights, hist: hist, lineH: lineH, headH: headH, line: line)
                                        .id(c.id)
                                }
                            }
                            .background(GeometryReader { g in
                                Color.clear.preference(key: MLHOffset.self, value: g.frame(in: .named("mlh")).minX)
                            })
                        }
                        .coordinateSpace(name: "mlh")
                        .onPreferenceChange(MLHOffset.self) { hx = $0 }
                        .modifier(HScrollWatch(hx: $hx))
                        .onAppear {
                            if month == String(Day.today.prefix(7)) { proxy.scrollTo(Day.today, anchor: .trailing) }
                        }
                    }
                }
            }
            HStack(spacing: 12) {
                Label("按住动作名可拖动排序", systemImage: "hand.draw").foregroundStyle(.secondary)
                legend("进步", Tone.fill(.up))
                legend("退步", Tone.fill(.down))
                legend("持平", Tone.fill(.same))
                legend("新纪录", Tone.gold.opacity(0.3))
                Text("斜纹 = 没练").foregroundStyle(.secondary)
            }
            .font(.caption2)
        }
    }

    private func legend(_ t: String, _ c: Color) -> some View {
        HStack(spacing: 4) { RoundedRectangle(cornerRadius: 3).fill(c).frame(width: 12, height: 12); Text(t) }
    }

    private func beginRowDrag(_ name: String) -> CardDrag {
        DispatchQueue.main.async { draggingRow = name; Haptic.tap(.medium) }
        return CardDrag(id: UUID())
    }

    @ViewBuilder
    private func header(_ c: Col, headH: CGFloat, line: Color) -> some View {
        switch c {
        case .gap(let a, let b):
            VStack(spacing: 0) {
                Text("\(dayNum(a))–\(dayNum(b))").font(.caption2.bold()).monospacedDigit()
                Text("休\(Day.between(a, b) + 1)天").font(.system(size: 9)).foregroundStyle(.secondary)
            }
            .foregroundStyle(.secondary)
            .frame(width: 46, height: headH)
            .overlay(alignment: .leading) { Rectangle().fill(line).frame(width: 1) }
        case .day(let d, let w):
            VStack(spacing: 0) {
                Text("\(dayNum(d))").font(.caption.bold()).monospacedDigit()
                Text(weekdayCN(d)).font(.system(size: 9)).foregroundStyle(.secondary)
            }
            .foregroundStyle(d == Day.today ? Parts.color(part) : (w == nil ? Color.secondary : Color.primary))
            .frame(width: w == nil ? 34 : 70, height: headH)
            .background(w != nil ? Parts.color(part).opacity(0.12) : Color.primary.opacity(0.05))
            .overlay(alignment: .leading) { Rectangle().fill(line).frame(width: 1) }
        }
    }

    @ViewBuilder
    private func column(_ c: Col, rows: [String], heights: [CGFloat], hist: [Workout], lineH: CGFloat, headH: CGFloat, line: Color) -> some View {
        switch c {
        case .gap(let a, let b):
            VStack(spacing: 0) {
                Stripes().frame(width: 46, height: heights.reduce(0, +))
            }
            .foregroundStyle(.secondary)
            .overlay(alignment: .leading) { Rectangle().fill(line).frame(width: 1) }
        case .day(let d, let w):
            let wide: CGFloat = w == nil ? 34 : 70
            VStack(spacing: 0) {
                ForEach(rows.indices, id: \.self) { i in
                    Group {
                        if let w { cell(rows[i], w, hist, lineH) } else { Stripes() }
                    }
                    .frame(width: wide, height: heights[i])
                    .overlay(alignment: .top) { Rectangle().fill(line).frame(height: 1) }
                }
            }
            .overlay(alignment: .leading) { Rectangle().fill(line).frame(width: 1) }
            .contentShape(Rectangle())
            .onTapGesture { if let w { onOpen(w) } }
        }
    }

    @ViewBuilder private func cell(_ name: String, _ w: Workout, _ hist: [Workout], _ lineH: CGFloat) -> some View {
        if let x = w.exercises(of: part).first(where: { $0.name == name }) {
            let idx = hist.firstIndex { $0.id == w.id } ?? 0
            let older = hist[..<idx].compactMap { $0.exercises(of: self.part).first { $0.name == name } }
            let prev = older.last
            let t = prev == nil ? Trend.up : trend(x, prev)
            let pr = prev != nil && x.best > 0 && x.best > (older.map(\.best).max() ?? 0)
            // 格子底色表示涨跌，下面写差了多少
            VStack(spacing: 0) {
                ForEach(x.sets) { s in
                    SetInkLabel(s: s, h: lineH - 2, font: .system(size: 12, weight: .semibold, design: .rounded))   // 手写的组显示原样笔迹
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                        .frame(height: lineH)
                }
                Text((pr ? "★ 新纪录" : (t == .up ? "↑ " : t == .down ? "↓ " : "= ") + deltaText(x, prev)))
                    .font(.system(size: 9, weight: .heavy, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
                    .frame(height: 14)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(Tone.text(t, pr: pr))
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Tone.fill(t, pr: pr)))
            .overlay { if pr { RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Tone.gold, lineWidth: 1.5) } }
            .padding(3)
        } else {
            Color.clear
        }
    }

    private func dayNum(_ d: String) -> Int { Int(d.suffix(2)) ?? 0 }
}

private struct MLHOffset: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
// iOS 18 起直接读横向滚动位置（比 GeometryReader 稳）
private struct HScrollWatch: ViewModifier {
    @Binding var hx: CGFloat
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { -$0.contentOffset.x - $0.contentInsets.leading } action: { _, v in hx = v }
        } else { content }
    }
}
