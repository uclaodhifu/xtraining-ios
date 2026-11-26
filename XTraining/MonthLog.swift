import SwiftUI

// 训练日志全屏（横屏）：按月排，1 号到月底每天一列
// 连续超过 3 天没练这个部位，就合成一列，比如“10–13”
struct MonthLogTable: View {
    @EnvironmentObject var store: Store
    let part: String
    let month: String            // "2026-11"
    var onOpen: (Workout) -> Void = { _ in }
    @State private var hx: CGFloat = 0     // 日期列左右滑了多少
    @State private var pinY: CGFloat = 0   // 表格顶部被滑出屏幕多少（日期行往下补回来）

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
        let lineH: CGFloat = 16
        let heights: [CGFloat] = rows.map { n in
            let m = inMonth.map { w in w.exercises(of: part).first { $0.name == n }?.sets.count ?? 0 }.max() ?? 1
            return CGFloat(max(1, m)) * lineH + 14
        }
        let nameW: CGFloat = 96, headH: CGFloat = 36
        let line = Color.primary.opacity(0.1)
        return VStack(alignment: .leading, spacing: 8) {
            if rows.isEmpty {
                Text("这个月还没练\(part)").font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 30)
            }
            // 冻结表头：左边动作列左右滑时不动；顶上日期行上下滑时一直停在顶上，左右跟着日期走
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(width: nameW, height: headH)
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
                        .onAppear {
                            if month == String(Day.today.prefix(7)) { proxy.scrollTo(Day.today, anchor: .trailing) }
                        }
                    }
                }
                .overlay(alignment: .topLeading) {
                    // 日期行：盖在最上面，上下滑时钉住
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
                    .background(Color(.secondarySystemGroupedBackground))
                    .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.18)).frame(height: 1) }
                    .shadow(color: .black.opacity(pinY > 1 ? 0.12 : 0), radius: 4, y: 3)
                    .offset(y: pinY)
                }
                .background(GeometryReader { g in
                    Color.clear.preference(key: MLVOffset.self, value: g.frame(in: .named("logv")).minY)
                })
                .onPreferenceChange(MLVOffset.self) { v in pinY = min(max(0, -v), heights.reduce(0, +)) }
            }
            HStack(spacing: 12) {
                Label("进步", systemImage: "arrow.up").foregroundStyle(.green)
                Label("退步", systemImage: "arrow.down").foregroundStyle(.red)
                Label("持平", systemImage: "equal")
                Text("灰色列 = 连续多天没练").foregroundStyle(.secondary)
            }
            .font(.caption2)
        }
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
            .background(w != nil ? Parts.color(part).opacity(0.12) : .clear)
            .overlay(alignment: .leading) { Rectangle().fill(line).frame(width: 1) }
        }
    }

    @ViewBuilder
    private func column(_ c: Col, rows: [String], heights: [CGFloat], hist: [Workout], lineH: CGFloat, headH: CGFloat, line: Color) -> some View {
        switch c {
        case .gap(let a, let b):
            let n = Day.between(a, b) + 1
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    Text("\(dayNum(a))–\(dayNum(b))").font(.caption2.bold()).monospacedDigit()
                    Text("休\(n)天").font(.system(size: 9)).foregroundStyle(.secondary)
                }
                .frame(width: 46, height: headH)
                Rectangle().fill(Color.primary.opacity(0.05)).frame(width: 46, height: heights.reduce(0, +))
            }
            .foregroundStyle(.secondary)
            .overlay(alignment: .leading) { Rectangle().fill(line).frame(width: 1) }
        case .day(let d, let w):
            let wide: CGFloat = w == nil ? 34 : 70
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    Text("\(dayNum(d))").font(.caption.bold()).monospacedDigit()
                    Text(weekdayCN(d)).font(.system(size: 9)).foregroundStyle(.secondary)
                }
                .foregroundStyle(d == Day.today ? Parts.color(part) : (w == nil ? Color.secondary : Color.primary))
                .frame(width: wide, height: headH)
                .background(w != nil ? Parts.color(part).opacity(0.12) : .clear)
                ForEach(rows.indices, id: \.self) { i in
                    Group {
                        if let w { cell(rows[i], w, hist, lineH) } else { Color.clear }
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
            let prev = hist[..<idx].reversed().lazy.compactMap { $0.exercises(of: self.part).first { $0.name == name } }.first
            let t = trend(x, prev)
            VStack(spacing: 0) {
                ForEach(x.sets) { s in
                    Text(setLabel(s))
                        .font(.system(size: 12, weight: t == .none || t == .same ? .regular : .semibold, design: .rounded))
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

    private func dayNum(_ d: String) -> Int { Int(d.suffix(2)) ?? 0 }
}

private struct MLHOffset: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
private struct MLVOffset: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
