import SwiftUI
import UniformTypeIdentifiers

// 拖动动作卡片用的专用类型：只有卡片能接住，不会被输入框当成文字粘进去（以前会出现一串乱码）
extension UTType { static let xtCard = UTType(exportedAs: "com.kaigreen.xtraining.card") }

struct CardDrag: Codable, Transferable {
    var id: UUID
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .xtCard)
    }
}

// 开始训练的草稿：没点保存就退出也不会丢，下次点“开始训练”接着记（只留当天的）
enum EntryDraft {
    private static let key = "xt.entryDraft"
    // 同时写进文件（原子写入，闪退也不丢）和 UserDefaults
    private static var url: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("entryDraft.json")
    }
    static func save(_ w: Workout) {
        guard let d = try? JSONEncoder().encode(w) else { return }
        UserDefaults.standard.set(d, forKey: key)
        if let u = url {
            try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? d.write(to: u, options: .atomic)
        }
    }
    static func load() -> Workout? {
        let fromFile = url.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode(Workout.self, from: $0) }
        let fromUD = UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(Workout.self, from: $0) }
        // 两份都有就用内容多的那份
        let all = [fromFile, fromUD].compactMap { $0 }
        guard let w = all.max(by: { $0.exercises.flatMap(\.sets).count < $1.exercises.flatMap(\.sets).count }) else { return nil }
        if w.date != Day.today { clear(); return nil }
        return w
    }
    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
        if let u = url { try? FileManager.default.removeItem(at: u) }
    }
}

// 以前拖动卡片时粘进来的乱码（一长串带横杠的编号），读出来时清掉
func dropJunk(_ s: String) -> String {
    s.count >= 20 && s.contains("-") ? "" : s
}
