import SwiftUI
import JavaScriptCore

// 从 iPhone 备忘录粘贴训练记录：解析（NotesParser.js）+ 动作名自动纠错 + 预览后导入
enum NotesParser {
    struct Fix: Hashable { let from: String; let to: String }
    struct Result { var workouts: [Workout]; var weights: [(String, Double)]; var fixes: [Fix] }

    static func parse(_ text: String, known: [String]) -> Result? {
        guard let ctx = JSContext() else { return nil }
        ctx.evaluateScript(notesParserJS)
        guard let out = ctx.objectForKeyedSubscript("xtParse")?.call(withArguments: [text])?.toString(),
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
        var fixes: [Fix] = []
        let set = Set(known)
        for i in ws.indices {
            for j in ws[i].exercises.indices {
                let n = ws[i].exercises[j].name
                let c = correct(n, known: known, set: set)
                if c != n {
                    ws[i].exercises[j].name = c
                    if !fixes.contains(Fix(from: n, to: c)) { fixes.append(Fix(from: n, to: c)) }
                    if let p = Parts.of(c), !ws[i].parts.contains(p) { ws[i].parts.append(p) }
                }
            }
        }
        return Result(workouts: ws.filter { !$0.exercises.isEmpty || !$0.note.isEmpty }, weights: weights, fixes: fixes)
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
        // 跟已知动作只差一个字：认为是打错了
        guard n.count >= 3 else { return n }
        let close = known.filter { abs($0.count - n.count) <= 1 && dist(Array($0), Array(n)) == 1 }
        return close.count == 1 ? close[0] : n
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
                        Button("识别") { hideKeyboard(); result = NotesParser.parse(text, known: known) }
                            .bold().disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } footer: {
                    Text("支持：11月20日 胸+肩 / 卧推 60kg 8 8 6 / 卧推 60×8 65×6 / 深蹲 100×5×5 / 侧平举 8kg 3组×15 / 跑步 30分钟 / 体重 90.5。打错的动作名会自动改正。")
                }

                if let r = result {
                    if !r.fixes.isEmpty {
                        Section("自动纠错 \(r.fixes.count) 处") {
                            ForEach(r.fixes, id: \.self) { f in
                                HStack {
                                    Text(f.from).strikethrough().foregroundStyle(.secondary)
                                    Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                                    Text(f.to).bold().foregroundStyle(Color(hex: 0xe8590c))
                                }
                            }
                        }
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

    private func doImport() {
        guard let r = result else { return }
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
