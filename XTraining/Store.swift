import SwiftUI

// 所有数据存在本机（UserDefaults），改了就自动保存
@MainActor
final class Store: ObservableObject {
    @Published var workouts: [Workout] = [] { didSet { save(workouts, "workouts") } }
    @Published var weights: [WeightRow] = [] { didSet { save(weights, "weights") } }
    @Published var food: [String: [String: Meal]] = [:] { didSet { save(food, "food") } }
    @Published var restDays: [String] = [] { didSet { save(restDays, "restDays") } }
    @Published var doneDays: [String] = [] { didSet { save(doneDays, "doneDays") } }
    @Published var cycle = Cycle() { didSet { save(cycle, "cycle") } }
    @Published var liftCharts: [String: [String]] = [:] { didSet { save(liftCharts, "liftCharts") } }

    private let ud = UserDefaults.standard

    init() {
        workouts = load("workouts") ?? []
        weights = load("weights") ?? []
        food = load("food") ?? [:]
        restDays = load("restDays") ?? []
        doneDays = load("doneDays") ?? []
        cycle = load("cycle") ?? Cycle()
        liftCharts = load("liftCharts") ?? [:]
    }

    private func save<T: Encodable>(_ v: T, _ key: String) {
        if let d = try? JSONEncoder().encode(v) { ud.set(d, forKey: "xt." + key) }
    }
    private func load<T: Decodable>(_ key: String) -> T? {
        guard let d = ud.data(forKey: "xt." + key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: d)
    }

    // MARK: 训练
    var sorted: [Workout] {
        workouts.sorted { $0.date != $1.date ? $0.date > $1.date : $0.createdAt > $1.createdAt }
    }
    func upsert(_ w: Workout) {
        if let i = workouts.firstIndex(where: { $0.id == w.id }) { workouts[i] = w } else { workouts.append(w) }
    }
    func delete(_ w: Workout) { workouts.removeAll { $0.id == w.id } }
    var todays: [Workout] { workouts.filter { $0.date == Day.today } }

    // 每个部位上次是哪天练的
    func lastTrained(_ part: String) -> String? {
        workouts.filter { $0.parts.contains(part) }.map(\.date).max()
    }
    // 某部位最近一次训练（记录页“上次练”用）
    func lastSession(_ part: String, before day: String = Day.today, skip: String? = nil) -> Workout? {
        sorted.first { $0.id != skip && $0.date <= day && $0.parts.contains(part) && !$0.exercises(of: part).isEmpty }
    }
    // 某个动作上次最后一组
    func lastSet(_ name: String) -> SetRow? {
        for w in sorted { if let x = w.exercises.first(where: { $0.name == name }), let s = x.sets.last { return s } }
        return nil
    }
    var allExerciseNames: [String] {
        var seen = Set<String>(), out: [String] = []
        for w in sorted { for x in w.exercises where !x.name.isEmpty && !seen.contains(x.name) { seen.insert(x.name); out.append(x.name) } }
        return out
    }

    var streak: Int {
        let days = Set(workouts.map(\.date))
        var d = Day.today
        if !days.contains(d) { d = Day.add(d, -1) }
        var n = 0
        while days.contains(d) { n += 1; d = Day.add(d, -1) }
        return n
    }
    var weekCount: Int {
        let cal = Calendar(identifier: .iso8601)
        let start = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        let mon = Day.str(start)
        return Set(workouts.filter { $0.date >= mon }.map(\.date)).count
    }
    var sets7: Int { workouts.filter { Day.between($0.date, Day.today) < 7 }.reduce(0) { $0 + $1.setCount } }

    // MARK: 休息 / 完成
    func setRest(_ on: Bool) {
        restDays.removeAll { $0 == Day.today }
        if on { restDays.append(Day.today) }
    }
    func setDone(_ on: Bool) {
        doneDays.removeAll { $0 == Day.today }
        if on { doneDays.append(Day.today) }
    }

    // MARK: 体重
    func logWeight(_ kg: Double, on day: String = Day.today) {
        weights.removeAll { $0.date == day }
        weights.append(WeightRow(date: day, kg: kg))
        weights.sort { $0.date < $1.date }
    }

    // MARK: 饮食
    func setMeal(_ meal: String, _ v: Meal, on day: String = Day.today) {
        var d = food[day] ?? [:]
        let t = v.t.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty && (Int(v.kcal) ?? 0) <= 0 { d[meal] = nil } else { d[meal] = Meal(t: t, kcal: v.kcal) }
        food[day] = d.isEmpty ? nil : d
    }
    func lastMeal(_ meal: String) -> (String, Meal)? {
        food.keys.filter { $0 < Day.today && !(food[$0]?[meal]?.t.isEmpty ?? true) }.max().flatMap { d in food[d]?[meal].map { (d, $0) } }
    }

    // MARK: 从网页版备份导入
    func importBackup(_ data: Data) throws -> Int {
        let b = try JSONDecoder().decode(Backup.self, from: data)
        let have = Set(workouts.map(\.id))
        let fresh = (b.entries ?? []).filter { !have.contains($0.id) }
        workouts.append(contentsOf: fresh)
        for w in b.weights ?? [] where w.kg > 0 { logWeight(w.kg, on: w.date) }
        return fresh.count
    }
    func exportBackup() -> Data {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? enc.encode(Backup(entries: workouts, weights: weights))) ?? Data()
    }
}
