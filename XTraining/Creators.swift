import SwiftUI

// 我关注的健身博主：粘贴抖音主页分享链接，点一下跳到抖音看
struct Creator: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var note: String = ""
    var link: String
}

@MainActor
final class CreatorStore: ObservableObject {
    static let shared = CreatorStore()
    @Published var list: [Creator] {
        didSet { if let d = try? JSONEncoder().encode(list) { UserDefaults.standard.set(d, forKey: "xt.creators") } }
    }
    private init() {
        list = UserDefaults.standard.data(forKey: "xt.creators").flatMap { try? JSONDecoder().decode([Creator].self, from: $0) } ?? []
    }

    // 从抖音分享文字里取出链接和名字（名字在【】里时）
    static func parse(_ text: String) -> (link: String?, name: String?) {
        func first(_ p: String) -> String? {
            guard let r = try? NSRegularExpression(pattern: p),
                  let m = r.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let g = Range(m.range(at: m.numberOfRanges > 1 ? 1 : 0), in: text) else { return nil }
            return String(text[g])
        }
        let link = first(#"https?://[A-Za-z0-9./?=&_%#:-]+"#)
        var name = first(#"【([^】]+)】"#)
        if let n = name { name = n.replacingOccurrences(of: "的作品", with: "").replacingOccurrences(of: "的主页", with: "") }
        return (link, name)
    }
}

struct CreatorsView: View {
    @ObservedObject private var cs = CreatorStore.shared
    @Environment(\.openURL) private var openURL
    @State private var editing: Creator?
    @State private var adding = false

    var body: some View {
        List {
            if cs.list.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "person.2.fill").font(.system(size: 36)).foregroundStyle(.secondary)
                    Text("还没有博主").font(.headline)
                    Text("在抖音打开博主主页 → 右上角“…” → 复制链接，回来点右上角＋粘贴。")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 30)
                .listRowBackground(Color.clear)
            }
            ForEach(cs.list) { c in
                HStack(spacing: 12) {
                    Text(String(c.name.prefix(1)))
                        .font(.headline).foregroundStyle(.white)
                        .frame(width: 42, height: 42).background(Brand.gradient, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.name).font(.body.bold())
                        if !c.note.isEmpty { Text(c.note).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    }
                    Spacer()
                    Button {
                        if let u = URL(string: c.link) { Haptic.tap(); openURL(u) }
                    } label: {
                        Label("抖音看", systemImage: "play.rectangle.fill").font(.footnote.bold())
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Color.black, in: Capsule()).foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
                .contentShape(Rectangle())
                .onTapGesture { editing = c }
            }
            .onDelete { cs.list.remove(atOffsets: $0) }
            .onMove { cs.list.move(fromOffsets: $0, toOffset: $1) }
        }
        .navigationTitle("健身博主")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button { adding = true } label: { Image(systemName: "plus") } }
            if !cs.list.isEmpty { ToolbarItem(placement: .topBarTrailing) { EditButton() } }
        }
        .sheet(isPresented: $adding) { CreatorEditor(c: nil) }
        .sheet(item: $editing) { CreatorEditor(c: $0) }
    }
}

struct CreatorEditor: View {
    @ObservedObject private var cs = CreatorStore.shared
    @Environment(\.dismiss) private var dismiss
    let c: Creator?
    @State private var name = ""
    @State private var note = ""
    @State private var link = ""
    @State private var raw = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("粘贴抖音分享的整段文字", text: $raw, axis: .vertical).lineLimit(2...5)
                        .onChange(of: raw) { _, t in apply(t) }
                    Button { if let t = UIPasteboard.general.string { raw = t } } label: {
                        Label("从剪贴板粘贴", systemImage: "doc.on.clipboard")
                    }
                } footer: { Text("会自动取出里面的链接。") }
                Section {
                    TextField("名字", text: $name)
                    TextField("备注，比如：练背、备赛", text: $note)
                    TextField("主页链接", text: $link).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .font(.footnote)
                }
            }
            .navigationTitle(c == nil ? "添加博主" : "编辑博主")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        let n = name.trimmingCharacters(in: .whitespaces)
                        if var old = c, let i = cs.list.firstIndex(where: { $0.id == old.id }) {
                            old.name = n; old.note = note; old.link = link; cs.list[i] = old
                        } else {
                            cs.list.append(Creator(name: n, note: note, link: link))
                        }
                        Haptic.success(); dismiss()
                    }
                    .bold()
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || URL(string: link)?.scheme == nil)
                }
            }
            .onAppear {
                if let c { name = c.name; note = c.note; link = c.link }
                else if let t = UIPasteboard.general.string, t.contains("douyin.com") { raw = t }
            }
        }
    }

    private func apply(_ t: String) {
        let p = CreatorStore.parse(t)
        if let l = p.link { link = l }
        if let n = p.name, name.isEmpty { name = n }
    }
}
