import SwiftUI

// MARK: - 部位、颜色、常用动作（和网页版一样）

enum Parts {
    static let all = ["胸", "肩", "背", "腿", "手臂", "有氧"]
    static let strength = ["胸", "肩", "背", "腿", "手臂"]
    static let library: [String: [String]] = [
        "胸": ["卧推", "上斜卧推", "哑铃卧推", "蝴蝶机夹胸", "双杠臂屈伸"],
        "肩": ["推举", "哑铃推举", "侧平举", "面拉", "反向飞鸟"],
        "背": ["引体向上", "高位下拉", "杠铃划船", "坐姿划船", "硬拉"],
        "腿": ["深蹲", "腿举", "罗马尼亚硬拉", "臀推", "腿弯举", "腿屈伸"],
        "手臂": ["二头弯举", "锤式弯举", "三头下压", "窄距卧推", "过头臂屈伸"],
        "有氧": ["跑步", "快走", "单车", "椭圆机", "划船机", "跳绳", "爬楼机", "游泳"],
    ]
    static func color(_ p: String) -> Color {
        switch p {
        // 更沉稳的深色：白字压得住，彼此又一眼能分开
        case "胸": return Color(hex: 0xe8590c)   // 焦橙
        case "肩": return Color(hex: 0x3b5bdb)   // 靛蓝
        case "背": return Color(hex: 0x0c8599)   // 深青
        case "腿": return Color(hex: 0x2b8a3e)   // 森林绿
        case "手臂": return Color(hex: 0x7048e8) // 紫罗兰
        case "有氧": return Color(hex: 0xd6336c) // 树莓红
        default: return .gray
        }
    }
    // 按名字猜部位（常用动作表 + 关键词）
    static func of(_ name: String) -> String? {
        for p in all where library[p]?.contains(name) == true { return p }
        let words: [(String, [String])] = [
            ("有氧", ["跑", "单车", "骑行", "椭圆", "爬坡", "爬楼", "游泳", "跳绳", "划船机", "有氧", "快走"]),
            ("手臂", ["弯举", "二头", "三头", "臂屈伸", "下压", "手臂", "锤式"]),
            ("肩", ["反向飞鸟", "后束", "肩", "推举", "侧平举", "前平举", "面拉", "耸肩"]),
            ("胸", ["胸", "卧推", "夹胸", "飞鸟", "俯卧撑", "双杠", "蝴蝶机", "平推"]),
            ("背", ["背", "引体", "下拉", "划船", "硬拉", "山羊挺身", "直臂", "T杠", "大剪刀"]),
            ("腿", ["腿", "蹲", "臀", "箭步", "弓步", "提踵"]),
        ]
        for (p, ws) in words where ws.contains(where: { name.contains($0) }) { return p }
        return nil
    }
    static let moods = ["很累", "一般", "还行", "不错", "爆发"]
}

// 跟着当前配色主题走
enum Brand {
    static var pink: Color { Skin.current.accent }
    static var gradient: LinearGradient { Skin.current.swatch }
    static var ink: Color { Skin.current.ink }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }
}

// MARK: - 日期

enum Day {
    static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    static func str(_ d: Date = Date()) -> String { fmt.string(from: d) }
    static func date(_ s: String) -> Date { fmt.date(from: s) ?? Date() }
    static var today: String { str() }
    static func add(_ s: String, _ n: Int) -> String {
        str(Calendar.current.date(byAdding: .day, value: n, to: date(s)) ?? Date())
    }
    static func between(_ a: String, _ b: String) -> Int {
        Calendar.current.dateComponents([.day], from: date(a), to: date(b)).day ?? 0
    }
    static func label(_ s: String) -> String {
        let p = s.split(separator: "-")
        guard p.count == 3, let m = Int(p[1]), let d = Int(p[2]) else { return s }
        return "\(m)月\(d)日"
    }
    static func ago(_ s: String) -> String {
        let n = between(s, today)
        return n == 0 ? "今天" : n == 1 ? "昨天" : "\(n)天前"
    }
}

// MARK: - 数据（字段名和网页版导出的备份一致，能直接导入）

// 网页版有时把数字存成字符串、有时存成数字，这里都接受
private func flex<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ k: K) -> String {
    if let s = try? c.decode(String.self, forKey: k) { return s }
    if let d = try? c.decode(Double.self, forKey: k) { return d == d.rounded() ? String(Int(d)) : String(d) }
    return ""
}

struct SetRow: Codable, Identifiable, Hashable {
    var id = UUID()
    var w = ""
    var r = ""
    var min = ""
    var p: [Int]? = nil   // 挂片：每根挂杆挂几片，比如 [2, 1] = 上 2 片、下 1 片
    var inkW: String? = nil   // 全部手写模式：重量/次数的笔迹文件编号（InkStore）
    var inkR: String? = nil
    enum CodingKeys: String, CodingKey { case w, r, min, p, inkW, inkR }
    init(w: String = "", r: String = "", min: String = "", p: [Int]? = nil) { self.w = w; self.r = r; self.min = min; self.p = p }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        w = dropJunk(flex(c, .w)); r = dropJunk(flex(c, .r)); min = dropJunk(flex(c, .min))
        p = try? c.decode([Int].self, forKey: .p)
        inkW = try? c.decode(String.self, forKey: .inkW)
        inkR = try? c.decode(String.self, forKey: .inkR)
    }
    func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: CodingKeys.self)
        try c.encode(w, forKey: .w); try c.encode(r, forKey: .r)
        if !min.isEmpty { try c.encode(min, forKey: .min) }
        if let p { try c.encode(p, forKey: .p) }
        if let inkW { try c.encode(inkW, forKey: .inkW) }
        if let inkR { try c.encode(inkR, forKey: .inkR) }
    }
    var platesText: String? { p.map { $0.map(String.init).joined(separator: "/") } }
    var weight: Double { Double(w) ?? 0 }
    var reps: Double { Double(r) ?? 0 }
}

struct Exercise: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var sets: [SetRow]
    var inkName: String? = nil   // 全部手写模式：动作名的笔迹
    enum CodingKeys: String, CodingKey { case name, sets, inkName }
    init(name: String, sets: [SetRow] = [SetRow()]) { self.name = name; self.sets = sets }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        sets = (try? c.decode([SetRow].self, forKey: .sets)) ?? []
        inkName = try? c.decode(String.self, forKey: .inkName)
    }
    func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name); try c.encode(sets, forKey: .sets)
        if let inkName { try c.encode(inkName, forKey: .inkName) }
    }
    var isCardio: Bool { Parts.of(name) == "有氧" }
    var best: Double { sets.map(\.weight).max() ?? 0 }
}

struct Workout: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var date: String = Day.today
    var parts: [String] = []
    var title = ""
    var exercises: [Exercise] = []
    var note = ""
    var mood: Int? = nil
    var createdAt: Double = Date().timeIntervalSince1970 * 1000
    var editedAt: Double = 0     // 最后一次保存的时间（秒），iCloud 合并时用
    enum CodingKeys: String, CodingKey { case id, date, parts, title, exercises, note, mood, createdAt, editedAt }
    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = flex(c, .id); if id.isEmpty { id = UUID().uuidString }
        date = (try? c.decode(String.self, forKey: .date)) ?? Day.today
        parts = (try? c.decode([String].self, forKey: .parts)) ?? []
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        exercises = (try? c.decode([Exercise].self, forKey: .exercises)) ?? []
        note = (try? c.decode(String.self, forKey: .note)) ?? ""
        mood = try? c.decode(Int.self, forKey: .mood)
        createdAt = (try? c.decode(Double.self, forKey: .createdAt)) ?? 0
        editedAt = (try? c.decode(Double.self, forKey: .editedAt)) ?? 0
    }
    // 有氧不算组数
    var setCount: Int { exercises.filter { !$0.isCardio }.reduce(0) { $0 + $1.sets.count } }
    var cardioMin: Double { exercises.filter(\.isCardio).flatMap(\.sets).reduce(0) { $0 + (Double($1.min) ?? 0) } }
    var displayTitle: String { !title.isEmpty ? title : parts.isEmpty ? "力量训练" : parts.joined(separator: " + ") }
    var volume: Double { exercises.flatMap(\.sets).reduce(0) { $0 + $1.weight * $1.reps } }
    // 某个部位的动作（动作名认不出部位时算到这次训练的第一个部位）
    func exercises(of part: String) -> [Exercise] {
        exercises.filter { (Parts.of($0.name) ?? parts.first ?? "") == part }
    }
}

struct WeightRow: Codable, Hashable, Identifiable {
    var date: String
    var kg: Double
    var id: String { date }
    enum CodingKeys: String, CodingKey { case date, kg }
    init(date: String, kg: Double) { self.date = date; self.kg = kg }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        date = (try? c.decode(String.self, forKey: .date)) ?? Day.today
        kg = Double(flex(c, .kg)) ?? 0
    }
}

struct Meal: Codable, Hashable {
    var t = ""
    var kcal = ""
}

struct Cycle: Codable, Hashable {
    var on = false
    var steps: [[String]] = [["胸"], ["背"], ["腿"], [], ["肩", "手臂"], []]
    var start = ""
    // 今天是这一圈的第几天（从 0 数）
    func index(on day: String = Day.today) -> Int {
        let n = steps.count
        guard n > 0 else { return 0 }
        let k = Day.between(start.isEmpty ? day : start, day) % n
        return (k + n) % n
    }
    static func startFor(_ i: Int) -> String { Day.add(Day.today, -i) }
    static func name(_ s: [String]) -> String { s.isEmpty ? "休息" : s.joined(separator: "+") }
}

// 网页版“导出备份”的文件格式
struct Backup: Codable {
    var entries: [Workout]?
    var weights: [WeightRow]?
}

// 挂片器械的设置（按动作名存）：几根挂杆、每片多重、器械本身多重
struct PlateCfg: Codable, Hashable {
    var pegs = 2
    var kg = 20.0
    var base = 0.0
    func total(_ p: [Int]) -> Double { base + Double(p.reduce(0, +)) * kg }
    var labels: [String] {
        switch pegs {
        case 1: return ["片"]
        case 2: return ["上", "下"]
        case 3: return ["上", "中", "下"]
        default: return (1...pegs).map { "\($0)" }
        }
    }
}
