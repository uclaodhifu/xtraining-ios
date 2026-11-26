import SwiftUI
import HealthKit

// 进步页最上面的「昨天」：运动几小时、多少组、练了什么部位，下面一条 0–24 点的时间轴标出练的时段
struct YesterdayCard: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var health = Health.shared
    @State private var segs: [(Double, Double)] = []   // 小时（0–24）开始、结束
    @State private var fromHealth = false

    private var day: String { Day.add(Day.today, -1) }
    private let blue = Color(hex: 0x0a84ff)   // 和进步页的蓝色柱状图一样
    private var ws: [Workout] { store.workouts.filter { $0.date == day } }
    private var sets: Int {
        ws.reduce(0) { $0 + $1.exercises.filter { !$0.isCardio }.reduce(0) { $0 + $1.sets.count } }
    }
    private var parts: String {
        let ps = Parts.all.filter { p in ws.contains { $0.parts.contains(p) } }
        return ps.isEmpty ? (store.restDays.contains(day) ? "休息日" : "没练") : ps.joined(separator: "·")
    }
    private var hours: Double { segs.reduce(0) { $0 + max(0, $1.1 - $1.0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("昨天").font(.headline)
                Spacer()
                Text(cnDate(day)).font(.subheadline.bold()).monospacedDigit().foregroundStyle(.secondary)
            }
            Spacer(minLength: 14)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    row(parts, "", small: parts.count > 3)
                    row(String(format: "%.1f", hours), "小时")
                    row("\(sets)", "组")
                }
                Spacer(minLength: 12)
                timeline.frame(maxWidth: 190)
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, minHeight: 150)
        .card()
        .task(id: store.workouts.count) { await load() }
    }

    private func row(_ v: String, _ unit: String, small: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(v).font(.system(size: small ? 24 : 32, weight: .heavy, design: .rounded))
                .foregroundStyle(blue)
                .lineLimit(1).minimumScaleFactor(0.6)
            if !unit.isEmpty { Text(unit).font(.subheadline.bold()).foregroundStyle(.secondary) }
        }
    }

    // 25 个点 = 0 点到 24 点；练过的那几个小时点亮
    private var timeline: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                ForEach(0..<25, id: \.self) { h in
                    let on = segs.contains { Double(h) + 0.5 > $0.0 && Double(h) - 0.5 < $0.1 } && h < 24
                    Circle().fill(on ? blue : Color.primary.opacity(0.18))
                        .frame(width: on ? 7 : 4.5, height: on ? 7 : 4.5)
                        .shadow(color: on ? blue.opacity(0.6) : .clear, radius: 3)
                        .frame(maxWidth: .infinity)
                }
            }
            HStack {
                Text("00:00"); Spacer(); Text("12:00"); Spacer(); Text("24:00")
            }
            .font(.system(size: 10, weight: .semibold)).monospacedDigit().foregroundStyle(.secondary)
            if !segs.isEmpty && !fromHealth {
                Text("按记录时间估算").font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
    }

    private func cnDate(_ d: String) -> String {
        let p = d.split(separator: "-").compactMap { Int($0) }
        return p.count == 3 ? "\(p[0])年\(p[1])月\(p[2])日" : d
    }

    private func load() async {
        let start = Day.date(day)
        if let hs = await health.segments(start), !hs.isEmpty {
            segs = hs; fromHealth = true; return
        }
        // 没连健康：按保存时间往前推，每组约 2.5 分钟（至少 20 分钟）
        fromHealth = false
        segs = ws.compactMap { w -> (Double, Double)? in
            let n = w.exercises.reduce(0) { $0 + ($1.isCardio ? 0 : $1.sets.count) }
            let cardio = w.exercises.filter(\.isCardio).compactMap { Double($0.sets.first?.min ?? "") }.reduce(0, +)
            let mins = max(20, Double(n) * 2.5 + cardio)
            let end = Date(timeIntervalSince1970: w.createdAt / 1000)
            guard Day.str(end) == day else { return nil }
            let e = end.timeIntervalSince(start) / 3600
            return (max(0, e - mins / 60), e)
        }
    }
}

extension Health {
    // 某一天 Apple 健康里的体能训练时段（小时 0–24）
    func segments(_ dayStart: Date) async -> [(Double, Double)]? {
        guard connected, available,
              let end = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
        let pred = HKQuery.predicateForSamples(withStart: dayStart, end: end)
        let q = HKSampleQueryDescriptor(predicates: [.workout(pred)], sortDescriptors: [SortDescriptor(\.startDate)])
        guard let ws = try? await q.result(for: hk) else { return nil }
        return ws.map { w in
            (max(0, w.startDate.timeIntervalSince(dayStart) / 3600), min(24, w.endDate.timeIntervalSince(dayStart) / 3600))
        }
    }
}
