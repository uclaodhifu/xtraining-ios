import SwiftUI
import JavaScriptCore

// 从 iPhone 备忘录粘贴训练记录：解析（NotesParser.js）+ 动作名自动纠错 + 预览后导入
enum NotesParser {
    struct Fix: Hashable { let from: String; let to: String }
    struct Result { var workouts: [Workout]; var weights: [(String, Double)]; var fixes: [Fix]; var orig: [UUID: String] = [:] }

    static func parse(_ text: String, known: [String], year: Int = 0, unit: Int = 0) -> Result? {
        guard let ctx = JSContext() else { return nil }
        ctx.evaluateScript(notesParserJS)
        guard let out = ctx.objectForKeyedSubscript("xtParse")?.call(withArguments: [text, year, unit, WU.lb])?.toString(),
              let data = out.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let entries = obj["entries"] as? [Any] ?? []
        var ws: [Workout] = entries.compactMap {
            guard let d = try? JSONSerialization.data(withJSONObject: $0) else { return nil }
            return try? JSONDecoder().decode(Workout.self, from: d)
        }
        let weights: [(String, Double)] = (obj["weights"] as? [[String: Any]] ?? []).compactMap {
            guard let d = $0["date"] as? String, let k = ($0["kg"] as? Double) ?? Double("\($0["kg"] ?? "")"), k > 20, k < 300 else { return nil }
            return (d, k)
        }
        // 体重写成动作的，交给体重记录
        ws = ws.map { w in var w = w; w.exercises.removeAll { ["体重", "称重", "晨重"].contains($0.name) }; return w }
        var fixes: [Fix] = [], orig: [UUID: String] = [:]
        let set = Set(known)
        for i in ws.indices {
            for j in ws[i].exercises.indices {
                let n = ws[i].exercises[j].name
                let c = correct(n, known: known, set: set)
                if c != n {
                    ws[i].exercises[j].name = c
                    orig[ws[i].exercises[j].id] = n
                    if !fixes.contains(Fix(from: n, to: c)) { fixes.append(Fix(from: n, to: c)) }
                    if let p = Parts.of(c), !ws[i].parts.contains(p) { ws[i].parts.append(p) }
                }
            }
        }
        return Result(workouts: ws.filter { !$0.exercises.isEmpty || !$0.note.isEmpty }, weights: weights, fixes: fixes, orig: orig)
    }

    // 常见错别字（拼音输入法打错的）
    private static let typos: [(String, String)] = [
        ("握推", "卧推"), ("沃推", "卧推"), ("窝推", "卧推"), ("玲", "铃"), ("据", "举"), ("巨", "举"),
        ("啦", "拉"), ("象上", "向上"), ("凶", "胸"), ("夹凶", "夹胸"), ("湾举", "弯举"), ("弯局", "弯举"),
        ("深顿", "深蹲"), ("深吨", "深蹲"), ("瑞马尼亚", "罗马尼亚"), ("应拉", "硬拉"), ("硬啦", "硬拉"),
        ("坐资", "坐姿"), ("坐子", "坐姿"), ("飞乌", "飞鸟"), ("提重", "提踵"), ("提肿", "提踵"),
        ("臂曲伸", "臂屈伸"), ("腿曲伸", "腿屈伸"), ("屈申", "屈伸"), ("划般", "划船"), ("滑船", "划船"),
    ]

    static func correct(_ name: String, known: [String], set: Set<String>) -> String {
        var n = name.trimmingCharacters(in: .whitespaces)
        if set.contains(n) { return n }
        for (a, b) in typos where n.contains(a) { n = n.replacingOccurrences(of: a, with: b) }
        if set.contains(n) { return n }
        // 跟已知动作只差一个字、而且读音一样（拼音输入法选错字）才改。
        // 读音不一样的不改：上斜/下斜、哑铃/杠铃、坐姿/站姿 这类是不同动作
        guard n.count >= 3 else { return n }
        let py = pinyin(n)
        let close = known.filter { $0.count == n.count && dist(Array($0), Array(n)) == 1 && pinyin($0) == py }
        return close.count == 1 ? close[0] : n
    }

    private static var pyCache: [String: String] = [:]
    static func pinyin(_ s: String) -> String {
        if let p = pyCache[s] { return p }
        let p = (s.applyingTransform(.toLatin, reverse: false) ?? s)
            .applyingTransform(.stripDiacritics, reverse: false)?.replacingOccurrences(of: " ", with: "").lowercased() ?? s
        pyCache[s] = p
        return p
    }

    private static func dist(_ a: [Character], _ b: [Character]) -> Int {
        var prev = Array(0...b.count)
        for i in 1...max(a.count, 1) where !a.isEmpty {
            var cur = [i] + Array(repeating: 0, count: b.count)
            for j in 1...max(b.count, 1) where !b.isEmpty {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            prev = cur
        }
        return prev[b.count]
    }
}

struct NotesImportView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var result: NotesParser.Result?
    @State private var done = ""
    @State private var year = 0   // 0 = 自动（按今天往前推）
    @State private var unit = 0   // 没写单位的重量：0 自动 1 公斤 2 磅
    @State private var kept = Set<NotesParser.Fix>()   // 点掉的纠错：保留原来的名字
    private var thisYear: Int { Calendar.current.component(.year, from: Date()) }

    private var known: [String] {
        var seen = Set<String>(), out: [String] = []
        let pool = ExerciseLib.all.map(\.name) + Parts.library.values.flatMap { $0 } + store.allExerciseNames
        for n in pool where seen.insert(n).inserted { out.append(n) }
        return out
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("把备忘录里的训练记录整段粘进来", text: $text, axis: .vertical).lineLimit(6...14)
                        .font(.callout)
                    HStack {
                        Button { if let t = UIPasteboard.general.string { text = t } } label: {
                            Label("粘贴", systemImage: "doc.on.clipboard")
                        }
                        Spacer()
                        Button("识别") { hideKeyboard(); reparse() }
                            .bold().disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    // 备忘录里常只写“11月20日”，这里选是哪一年
                    Picker("年份", selection: $year) {
                        Text("自动").tag(0)
                        ForEach((2015...thisYear).reversed(), id: \.self) { y in Text(verbatim: "\(y)年").tag(y) }
                    }
                    .onChange(of: year) { _, _ in if result != nil { reparse() } }
                    // 有人用磅记：写了 lb/磅 的自动换成公斤；没写单位的按这里选的算
                    Picker("单位", selection: $unit) {
                        Text("自动").tag(0); Text("公斤 kg").tag(1); Text("磅 lb").tag(2)
                    }
                    .onChange(of: unit) { _, _ in if result != nil { reparse() } }
                } footer: {
                    Text("单位：写了 lb、磅 或 kg、公斤 的都会自动换算成你在「我」里设的单位（现在是 \(WU.lb ? "磅" : "公斤")，135磅 = 61.2kg）；没写单位的数字按这里选的算，「自动」就看整段里写磅多还是写公斤多。\n年份：只写了月日的记录按选的年份导入；选「自动」就按今天往前推（比今天晚的日期算去年）。写了年份的（如 2024年3月5日）照写的来。\n支持：11月20日 胸+肩 / 卧推 60kg 8 8 6 / 卧推 60×8 65×6 / 深蹲 100×5×5 / 侧平举 8kg 3组×15 / 跑步 30分钟 / 体重 90.5。读音一样的错别字会自动改正（如 握推 → 卧推），改错了点一下那行就不改。")
                }

                if let r = result {
                    if !r.fixes.isEmpty {
                        Section {
                            ForEach(r.fixes, id: \.self) { f in
                                let keep = kept.contains(f)
                                Button {
                                    Haptic.tap()
                                    if keep { kept.remove(f) } else { kept.insert(f) }
                                } label: {
                                    HStack {
                                        Text(f.from).strikethrough(!keep).foregroundStyle(keep ? Color.primary : .secondary).bold(keep)
                                        Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                                        Text(f.to).strikethrough(keep).bold(!keep).foregroundStyle(keep ? Color.secondary : Color(hex: 0xe8590c))
                                        Spacer()
                                        Text(keep ? "不改" : "改").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        } header: { Text("自动纠错 \(r.fixes.count) 处") } footer: { Text("点一下就保留原来的名字") }
                    }
                    Section("识别到 \(r.workouts.count) 次训练" + (r.weights.isEmpty ? "" : "、\(r.weights.count) 条体重")) {
                        if r.workouts.isEmpty { Text("没认出训练记录，检查一下格式").foregroundStyle(.secondary) }
                        ForEach(r.workouts) { w in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(slashDate(w.date)).font(.subheadline.bold())
                                    Text(w.displayTitle).font(.subheadline).foregroundStyle(.secondary)
                                    Spacer()
                                    if store.workouts.contains(where: { $0.id == w.id }) {
                                        Text("已导入过").font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                ForEach(w.exercises) { x in
                                    Text("\(x.name)  " + (x.isCardio ? "\(x.sets.first?.min ?? "")分钟" : x.sets.map(setLabel).joined(separator: "  ")))
                                        .font(.caption).lineLimit(2)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                if !done.isEmpty { Section { Text(done).foregroundStyle(.green) } }
            }
            .navigationTitle("从备忘录导入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("导入") { doImport() }.bold()
                        .disabled((result?.workouts.isEmpty ?? true) && (result?.weights.isEmpty ?? true))
                }
            }
        }
    }

    private func reparse() { result = NotesParser.parse(text, known: known, year: year, unit: unit) }

    private func doImport() {
        guard var r = result else { return }
        // 点掉的纠错改回原来的名字
        for i in r.workouts.indices { for j in r.workouts[i].exercises.indices {
            let x = r.workouts[i].exercises[j]
            if let o = r.orig[x.id], kept.contains(NotesParser.Fix(from: o, to: x.name)) { r.workouts[i].exercises[j].name = o }
        } }
        kept = []
        let entries = r.workouts.compactMap { w -> Any? in
            guard let d = try? JSONEncoder().encode(w) else { return nil }
            return try? JSONSerialization.jsonObject(with: d)
        }
        let payload: [String: Any] = ["entries": entries, "weights": r.weights.map { ["date": $0.0, "kg": $0.1] }]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        do {
            let (n, wn) = try store.importBackup(data)
            Haptic.success()
            done = "导入好了：新加 \(n) 次训练、\(wn) 条体重"
            result = nil; text = ""
        } catch {
            done = "导入失败：\(error.localizedDescription)"
        }
    }
}
