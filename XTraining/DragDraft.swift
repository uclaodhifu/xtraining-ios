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
    static func save(_ w: Workout) {
        if let d = try? JSONEncoder().encode(w) { UserDefaults.standard.set(d, forKey: key) }
    }
    static func load() -> Workout? {
        guard let d = UserDefaults.standard.data(forKey: key),
              let w = try? JSONDecoder().decode(Workout.self, from: d) else { return nil }
        if w.date != Day.today { clear(); return nil }
        return w
    }
    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}

// 以前拖动卡片时粘进来的乱码（一长串带横杠的编号），读出来时清掉
func dropJunk(_ s: String) -> String {
    s.count >= 20 && s.contains("-") ? "" : s
}
