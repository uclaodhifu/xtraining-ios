import SwiftUI

// 所有数据存在本机（UserDefaults），改了就自动保存
@MainActor
final class Store: ObservableObject {
    @Published var workouts: [Workout] = [] { didSet { rev &+= 1; save(workouts, "workouts") } }
    private(set) var rev = 0     // 训练记录改一次加 1，表格用它强制刷新
    @Published var weights: [WeightRow] = [] { didSet { save(weights, "weights") } }
    @Published var food: [String: [String: Meal]] = [:] { didSet { save(food, "food") } }
    @Published var restDays: [String] = [] { didSet { save(restDays, "restDays") } }
    @Published var doneDays: [String] = [] { didSet { save(doneDays, "doneDays") } }
    @Published var cycle = Cycle() { didSet { save(cycle, "cycle") } }
    @Published var liftCharts: [String: [String]] = [:] { didSet { save(liftCharts, "liftCharts") } }
    @Published var follow: [String] = [] { didSet { save(follow, "follow") } }
    @Published var avatar: Data? = nil { didSet { ud.set(avatar, forKey: "xt.avatar") } }
    @Published var nickname: String = "" { didSet { ud.set(nickname, forKey: "xt.nickname") } }
    @Published var plateCfg: [String: PlateCfg] = [:] { didSet { save(plateCfg, "plateCfg") } }
    @Published var hero: [HeroItem] = HeroItem.defaults { didSet { save(hero, "hero") } }

    private let ud = UserDefaults.standard

    init() {
        workouts = load("workouts") ?? []
        weights = load("weights") ?? []
        food = load("food") ?? [:]
        restDays = load("restDays") ?? []
        doneDays = load("doneDays") ?? []
        cycle = load("cycle") ?? Cycle()
        liftCharts = load("liftCharts") ?? [:]
        follow = load("follow") ?? []
        avatar = ud.data(forKey: "xt.avatar")
        nickname = ud.string(forKey: "xt.nickname") ?? ""
        plateCfg = load("plateCfg") ?? [:]
        hero = load("hero") ?? HeroItem.defaults
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
        var w = w; w.editedAt = Date().timeIntervalSince1970
        if let i = workouts.firstIndex(where: { $0.id == w.id }) { workouts[i] = w } else { workouts.append(w) }
    }
    func delete(_ w: Workout) { CloudSync.shared.noteDelete([w.id]); workouts.removeAll { $0.id == w.id } }
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

    // MARK: 追赛
    func toggleFollow(_ e: Race) {
        if follow.contains(e.id) { follow.removeAll { $0 == e.id }; Reminders.cancel(e) }
        else { follow.append(e.id); Reminders.schedule(e, confirm: true) }
    }

    // MARK: 从网页版备份导入
    // 宽松读取：整个备份 / 只有训练数组 都行；某一条读不了就跳过，不让整份失败
    func importBackup(_ raw: Data) throws -> (Int, Int) {
        var data = raw
        // 去掉 UTF-8 BOM 和前后的空白
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { data = data.dropFirst(3) }
        guard let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let start = text.firstIndex(where: { $0 == "{" || $0 == "[" }) else { throw ImportError.notJSON }
        let json = try JSONSerialization.jsonObject(with: Data(text[start...].utf8))
        var entries: [Any] = [], weightsRaw: [Any] = []
        if let arr = json as? [Any] { entries = arr }
        else if let obj = json as? [String: Any] {
            entries = obj["entries"] as? [Any] ?? []
            weightsRaw = obj["weights"] as? [Any] ?? []
        }
        guard !entries.isEmpty || !weightsRaw.isEmpty else { throw ImportError.empty }
        // 备份里带的手写笔迹先放回去（本机已有的不覆盖）
        if let obj = json as? [String: Any], let ink = obj["ink"] as? [String: String] {
            for (id, b64) in ink { if let d = Data(base64Encoded: b64) { InkStore.restore(id, d) } }
        }
        let dec = JSONDecoder()
        func one<T: Decodable>(_ x: Any, _ t: T.Type) -> T? {
            guard JSONSerialization.isValidJSONObject(x), let d = try? JSONSerialization.data(withJSONObject: x) else { return nil }
            return try? dec.decode(T.self, from: d)
        }
        let have = Set(workouts.map(\.id))
        var fresh: [Workout] = []
        for e in entries {
            guard var w = one(e, Workout.self) else { continue }
            // 备忘录导入的“体重”动作搬到体重记录
            for x in w.exercises where ["体重", "称重", "晨重"].contains(x.name.replacingOccurrences(of: " ", with: "")) {
                if let v = x.sets.compactMap({ Double($0.w) ?? Double($0.r) }).first, v > 20, v < 300 { logWeight(v, on: w.date) }
            }
            w.exercises.removeAll { ["体重", "称重", "晨重"].contains($0.name.replacingOccurrences(of: " ", with: "")) }
            if !have.contains(w.id) && !fresh.contains(where: { $0.id == w.id }) { fresh.append(w) }
        }
        CloudSync.shared.forgive(fresh.map(\.id))   // 以前清掉又导回来的，别被 iCloud 当成已删除再删一次
        workouts.append(contentsOf: fresh)
        var nw = 0
        for x in weightsRaw { if let r = one(x, WeightRow.self), r.kg > 0 { logWeight(r.kg, on: r.date); nw += 1 } }
        return (fresh.count, nw)
    }
    func exportBackup() -> Data {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        // 用到的手写笔迹一起打包进去
        var ink: [String: String] = [:]
        for w in workouts { for x in w.exercises {
            for id in [x.inkName] + x.sets.flatMap({ [$0.inkW, $0.inkR] }) {
                if let id, ink[id] == nil, let d = InkStore.raw(id) { ink[id] = d.base64EncodedString() }
            }
        } }
        return (try? enc.encode(Backup(entries: workouts, weights: weights, ink: ink.isEmpty ? nil : ink))) ?? Data()
    }
}

enum ImportError: LocalizedError {
    case notJSON, empty
    var errorDescription: String? {
        switch self {
        case .notJSON: return "这不是备份文件（里面没有 JSON 内容）"
        case .empty: return "备份里没有找到训练或体重记录"
        }
    }
}
