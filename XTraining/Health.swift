import SwiftUI
import HealthKit

// 每天的运动（从 Apple 健康读）
struct DayAct {
    var minutes = 0.0
    var kcal = 0.0
    var steps = 0.0
    var count = 0
    var types: [String] = []
}

@MainActor
final class Health: ObservableObject {
    static let shared = Health()
    let hk = HKHealthStore()
    @Published var connected = UserDefaults.standard.bool(forKey: "xt.health")
    @Published var days: [String: DayAct] = [:]
    @Published var loading = false
    var available: Bool { HKHealthStore.isHealthDataAvailable() }

    func connect() async -> Bool {
        guard available else { return false }
        let read: Set<HKObjectType> = [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned), HKQuantityType(.stepCount),
                                       HKQuantityType(.heartRate), HKQuantityType(.restingHeartRate)]
        // 在 iPhone 上开始训练读耳机心率时，练完要把这次训练存进 Apple 健康
        let share: Set<HKSampleType> = [HKObjectType.workoutType(), HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]
        do {
            try await hk.requestAuthorization(toShare: share, read: read)
            connected = true
            UserDefaults.standard.set(true, forKey: "xt.health")
            UserDefaults.standard.set(true, forKey: "xt.health2")
            return true
        } catch { return false }
    }

    // 心率需要的权限：没问过就问一次（已经问过不会再弹）
    func ensureHeart() async -> Bool {
        guard available else { return false }
        let share: Set<HKSampleType> = [HKObjectType.workoutType(), HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]
        let read: Set<HKObjectType> = [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned), HKQuantityType(.stepCount),
                                       HKQuantityType(.heartRate), HKQuantityType(.restingHeartRate)]
        if let st = try? await hk.statusForAuthorizationRequest(toShare: share, read: read), st == .unnecessary {
            if !connected { connected = true; UserDefaults.standard.set(true, forKey: "xt.health") }
            return true
        }
        return await connect()
    }

    func load(month: Date) async {
        guard connected, available else { days = [:]; return }
        loading = true
        defer { loading = false }
        days = await fetch(month: month)
    }

    // 读某个月的数据，不改动页面上正在显示的月份（月份对比用）
    func fetch(month: Date) async -> [String: DayAct] {
        guard connected, available else { return [:] }
        let cal = Calendar.current
        guard let start = cal.date(from: cal.dateComponents([.year, .month], from: month)),
              let end = cal.date(byAdding: .month, value: 1, to: start) else { return [:] }
        var out: [String: DayAct] = [:]
        let pred = HKQuery.predicateForSamples(withStart: start, end: end)
        let wq = HKSampleQueryDescriptor(predicates: [.workout(pred)], sortDescriptors: [SortDescriptor(\.startDate)])
        if let ws = try? await wq.result(for: hk) {
            for w in ws {
                let k = Day.str(w.startDate)
                var a = out[k] ?? DayAct()
                a.minutes += w.duration / 60
                a.kcal += w.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                a.types.append(Health.name(w.workoutActivityType))
                a.count += 1
                out[k] = a
            }
        }
        let sq = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(.stepCount), predicate: pred),
            options: .cumulativeSum, anchorDate: start, intervalComponents: DateComponents(day: 1))
        if let coll = try? await sq.result(for: hk) {
            coll.enumerateStatistics(from: start, to: end) { s, _ in
                let n = s.sumQuantity()?.doubleValue(for: .count()) ?? 0
                if n > 0 { out[Day.str(s.startDate), default: DayAct()].steps = n }
            }
        }
        return out
    }

    // 某段时间里 Apple 健康的心率（手表、耳机、手环 App 写进去的都算）
    func heart(_ a: Date, _ b: Date) async -> [HRPoint] {
        guard connected, available else { return [] }
        let q = HKSampleQueryDescriptor(predicates: [.quantitySample(type: HKQuantityType(.heartRate), predicate: HKQuery.predicateForSamples(withStart: a, end: b))],
                                        sortDescriptors: [SortDescriptor(\.startDate)])
        let unit = HKUnit.count().unitDivided(by: .minute())
        let ss = (try? await q.result(for: hk)) ?? []
        return ss.map { HRPoint(t: $0.startDate.timeIntervalSince1970, v: Int($0.quantity.doubleValue(for: unit).rounded())) }
    }

    // 最近的心率是哪些设备测的：手表 / 耳机 / 手环
    func heartSources() async -> Set<String> {
        guard connected, available else { return [] }
        let q = HKSampleQueryDescriptor(predicates: [.quantitySample(type: HKQuantityType(.heartRate), predicate: HKQuery.predicateForSamples(withStart: Date().addingTimeInterval(-30 * 86400), end: nil))],
                                        sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)], limit: 400)
        var out: Set<String> = []
        for s in (try? await q.result(for: hk)) ?? [] {
            let dev = (s.device?.name ?? "") + " " + (s.device?.model ?? "")
            if dev.contains("AirPods") || dev.contains("Beats") { out.insert("耳机") }
            else if s.sourceRevision.productType?.contains("Watch") == true || dev.contains("Watch") { out.insert("手表") }
            else if s.sourceRevision.source.bundleIdentifier.hasPrefix("com.apple") == false { out.insert("手环") }
        }
        return out
    }

    // 每天的静息心率
    func resting(days: Int) async -> [(String, Double)] {
        guard connected, available else { return [] }
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date().addingTimeInterval(-Double(days) * 86400))
        let sq = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(.restingHeartRate), predicate: HKQuery.predicateForSamples(withStart: start, end: nil)),
            options: .discreteAverage, anchorDate: start, intervalComponents: DateComponents(day: 1))
        var out: [(String, Double)] = []
        if let coll = try? await sq.result(for: hk) {
            coll.enumerateStatistics(from: start, to: Date()) { s, _ in
                if let v = s.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) { out.append((Day.str(s.startDate), v)) }
            }
        }
        return out
    }

    // 某段时间里 Apple 健康记的运动（起止时间）
    func workoutSpans(_ a: Date, _ b: Date) async -> [(Date, Date, String)] {
        guard connected, available else { return [] }
        let wq = HKSampleQueryDescriptor(predicates: [.workout(HKQuery.predicateForSamples(withStart: a, end: b))], sortDescriptors: [SortDescriptor(\.startDate)])
        return ((try? await wq.result(for: hk)) ?? []).map { ($0.startDate, $0.endDate, Health.name($0.workoutActivityType)) }
    }

    static func name(_ t: HKWorkoutActivityType) -> String {
        switch t {
        case .traditionalStrengthTraining, .functionalStrengthTraining: return "力量训练"
        case .mixedCardio: return "混合有氧"
        case .highIntensityIntervalTraining: return "HIIT"
        case .walking: return "走路"
        case .running: return "跑步"
        case .cycling: return "骑行"
        case .yoga: return "瑜伽"
        case .swimming: return "游泳"
        case .elliptical: return "椭圆机"
        case .rowing: return "划船"
        case .stairClimbing, .stairs: return "爬楼"
        case .coreTraining: return "核心训练"
        case .flexibility: return "拉伸"
        case .hiking: return "徒步"
        case .jumpRope: return "跳绳"
        case .dance, .socialDance, .cardioDance: return "跳舞"
        case .basketball: return "篮球"
        case .badminton: return "羽毛球"
        default: return "运动"
        }
    }
}

// 「我」页面的运动记录：本月统计 + 日历
struct ActivityCard: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var health = Health.shared
    @State private var month = Date()
    @State private var denied = false
    @State private var picking = false
    @State private var comparing = false

    private let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.firstWeekday = 2; return c }()

    private var monthDays: [String] {
        guard let start = cal.date(from: cal.dateComponents([.year, .month], from: month)),
              let range = cal.range(of: .day, in: .month, for: start) else { return [] }
        return range.compactMap { cal.date(byAdding: .day, value: $0 - 1, to: start).map { Day.str($0) } }
    }
    private var lead: Int {
        guard let first = monthDays.first else { return 0 }
        return (cal.component(.weekday, from: Day.date(first)) + 5) % 7
    }

    var body: some View {
        let days = monthDays
        // 先按日期分好组：以前每个日历格子都把全部训练筛一遍，记录多了「我」页滑动会掉帧
        let byDay = Dictionary(grouping: store.workouts, by: \.date)
        let stats = summary(days, byDay)
        VStack(spacing: 14) {
            HStack {
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Button { picking = true } label: {
                    HStack(spacing: 4) {
                        Label(title, systemImage: "figure.run").font(.headline)
                        Image(systemName: "chevron.down").font(.caption2.bold()).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button { shift(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(Day.str(month).prefix(7) >= Day.today.prefix(7))
            }
            .buttonStyle(.plain)
            HStack {
                big("\(stats.days)", "天", "运动天数")
                big("\(stats.count)", "次", "运动次数")
                big("\(Int(stats.minutes))", "分钟", "运动时长")
            }
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(Int(stats.kcal))").font(.system(size: 34, weight: .heavy, design: .rounded))
                            .contentTransition(.numericText()).animation(.snappy, value: Int(stats.kcal))
                        Text("kcal").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text("消耗卡路里").font(.caption).foregroundStyle(.secondary)
                }
                Text("≈").font(.title2.bold()).foregroundStyle(Brand.pink).padding(.horizontal, 6)
                VStack(spacing: 4) {
                    // 一块炸鸡大约 250 千卡
                    let pieces = Int((stats.kcal / 250).rounded())
                    HStack(spacing: 2) {
                        ForEach(0..<5, id: \.self) { i in
                            Text("🍗").font(.title3).opacity(Double(i) < Double(pieces) / 8 ? 1 : 0.25)
                        }
                    }
                    Text("热量约 \(pieces) 块炸鸡").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            if !health.connected {
                Button {
                    Task { denied = !(await health.connect()); await health.load(month: month) }
                } label: {
                    Label("连接 Apple 健康", systemImage: "heart.fill")
                        .font(.subheadline.bold()).frame(maxWidth: .infinity, minHeight: 40)
                        .foregroundStyle(.white).background(Capsule().fill(Color.red.gradient))
                }
                .buttonStyle(.plain)
                Text(denied ? "没能连接。去「设置 → 健康 → 数据访问与设备 → X Training」打开权限。" : "连接后，会自动读取 Apple 健康里的运动、卡路里、步数和心率。没连接时只显示 App 里记的力量训练。")
                    .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            // 日历
            VStack(spacing: 6) {
                HStack(spacing: 0) {
                    ForEach(["周一", "周二", "周三", "周四", "周五", "周六", "周日"], id: \.self) { Text($0).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity) }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7), spacing: 8) {
                    ForEach(0..<lead, id: \.self) { _ in Color.clear.frame(height: 1) }
                    ForEach(days, id: \.self) { d in dayCell(d, byDay) }
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
            Button { comparing = true } label: {
                Label("月份对比", systemImage: "arrow.left.arrow.right").font(.subheadline.bold())
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .background(Capsule().fill(Color(.tertiarySystemFill)))
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $picking) {
            MonthPicker(month: String(Day.str(month).prefix(7))) { m in
                withAnimation(.snappy) { month = Day.date(m + "-01") }
            }
            .presentationDetents([.height(320)])
        }
        .sheet(isPresented: $comparing) { MonthCompare(a: String(Day.str(month).prefix(7))) }
        .task(id: Day.str(month).prefix(7) + (health.connected ? "1" : "0")) { await health.load(month: month) }
    }

    private var title: String {
        let p = Day.str(month).split(separator: "-")
        return p.count == 3 ? "\(p[0])年\(Int(p[1]) ?? 0)月 运动记录" : "运动记录"
    }
    private func shift(_ n: Int) {
        if let m = cal.date(byAdding: .month, value: n, to: month) { withAnimation(.snappy) { month = m } }
    }
    private func big(_ v: String, _ unit: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(v).font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundStyle(Brand.gradient)
                    .contentTransition(.numericText()).animation(.snappy, value: v)
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func summary(_ days: [String], _ byDay: [String: [Workout]]) -> (days: Int, count: Int, minutes: Double, kcal: Double) {
        var d = 0, c = 0, m = 0.0, k = 0.0
        for day in days {
            let h = health.days[day]
            let app = byDay[day] ?? []
            let hc = h?.count ?? 0
            if hc > 0 || !app.isEmpty { d += 1 }
            c += hc > 0 ? hc : app.count
            m += h?.minutes ?? 0
            k += h?.kcal ?? 0
        }
        return (d, c, m, k)
    }

    @ViewBuilder private func dayCell(_ d: String, _ byDay: [String: [Workout]]) -> some View {
        let h = health.days[d]
        let app = byDay[d] ?? []
        let active = (h?.count ?? 0) > 0 || !app.isEmpty
        let isToday = d == Day.today
        VStack(spacing: 3) {
            HStack(spacing: 1) {
                Text("\(Int(d.suffix(2)) ?? 0)").font(.caption.bold())
                    .foregroundStyle(isToday ? Brand.pink : Color.primary)
                if active { Image(systemName: "flame.fill").font(.system(size: 9)).foregroundStyle(.red) }
            }
            if let h, h.count > 0 {
                chip("\(Int(h.kcal))kcal", .orange)
                chip("\(Int(h.minutes.rounded()))分钟", .blue)
                chip(mainType(h.types), .blue)
            } else if !app.isEmpty {
                chip("\(app.reduce(0) { $0 + $1.setCount })组", .orange)
                chip(Array(Set(app.flatMap(\.parts))).sorted { (Parts.all.firstIndex(of: $0) ?? 9) < (Parts.all.firstIndex(of: $1) ?? 9) }.joined(separator: "+").ifEmpty("训练"), .blue)
                chip("力量训练", .blue)
            } else if let s = h?.steps, s >= 3000 {
                chip("\(Int(s))步", .green)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .top)
    }

    private func mainType(_ ts: [String]) -> String {
        if ts.contains("力量训练") { return "力量训练" }
        var c: [String: Int] = [:]
        for t in ts { c[t, default: 0] += 1 }
        return c.max { $0.value < $1.value }?.key ?? "运动"
    }

    private func chip(_ t: String, _ color: Color) -> some View {
        Text(t).font(.system(size: 9, weight: .medium)).lineLimit(1).minimumScaleFactor(0.6)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5).fill(color.opacity(0.12)))
    }
}

extension String {
    func ifEmpty(_ s: String) -> String { isEmpty ? s : self }
}
