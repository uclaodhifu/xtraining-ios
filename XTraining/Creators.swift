import SwiftUI
import PhotosUI
import Vision

// 我关注的健身博主：粘贴抖音主页分享链接，点一下跳到抖音看
struct Creator: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var note: String = ""
    var link: String
    var avatar: Data? = nil     // 从用户自己的关注列表截图里裁的头像，只存本机
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

// 推荐关注：手工整理的知名健身博主，只存名字和方向，点开按名字在抖音搜索（不内置任何人的照片）
struct RecCreator: Hashable { let name: String; let tag: String }
let recommendedCreators: [RecCreator] = [
    RecCreator(name: "刘畊宏", tag: "跟练 · 燃脂"),
    RecCreator(name: "周六野Zoey", tag: "女生塑形 · 体态"),
    RecCreator(name: "凯圣王", tag: "健身科普 · 增肌"),
    RecCreator(name: "仰望尾迹云", tag: "训练科普 · 增肌"),
    RecCreator(name: "吕小军", tag: "举重 · 力量"),
    RecCreator(name: "钱吉成", tag: "健美 · 备赛"),
]

struct CreatorsView: View {
    @ObservedObject private var cs = CreatorStore.shared
    @Environment(\.openURL) private var openURL
    @State private var editing: Creator?
    @State private var adding = false
    @State private var importing = false

    var body: some View {
        List {
            if cs.list.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "person.2.fill").font(.system(size: 36)).foregroundStyle(.secondary)
                    Text("还没有博主").font(.headline)
                    Text("在抖音打开博主主页 → 右上角“…” → 复制链接，回来点右上角＋粘贴。也可以＋ → 批量导入，截关注列表的图自动识别。")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 30)
                .listRowBackground(Color.clear)
            }
            ForEach(cs.list) { c in
                HStack(spacing: 12) {
                    CreatorAvatar(c: c, size: 42)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.name).font(.body.bold())
                        if !c.note.isEmpty { Text(c.note).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    }
                    Spacer()
                    Button {
                        Haptic.tap(); open(c.link)
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
            let recs = recommendedCreators.filter { r in !cs.list.contains { $0.name == r.name } }
            if !recs.isEmpty {
                Section {
                    ForEach(recs, id: \.self) { r in
                        HStack(spacing: 12) {
                            CreatorAvatar(c: Creator(name: r.name, link: r.name), size: 42)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.name).font(.body.bold())
                                Text(r.tag).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { Haptic.tap(); open(r.name) } label: {
                                Image(systemName: "play.rectangle.fill").font(.subheadline)
                                    .frame(width: 34, height: 34).background(Color.primary.opacity(0.08), in: Circle())
                            }
                            .buttonStyle(.plain)
                            Button {
                                Haptic.tap(.medium)
                                withAnimation { cs.list.append(Creator(name: r.name, note: r.tag, link: r.name)) }
                            } label: {
                                Text("＋ 关注").font(.footnote.bold()).padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(Brand.gradient, in: Capsule()).foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: { Text("推荐关注") } footer: {
                    Text("点 ▶ 会在抖音按名字搜索，确认是本人再关注。")
                }
            }
        }
        .navigationTitle("健身博主")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { adding = true } label: { Label("添加一个", systemImage: "plus") }
                    Button { importing = true } label: { Label("批量导入", systemImage: "square.and.arrow.down.on.square") }
                } label: { Image(systemName: "plus") }
            }
            if !cs.list.isEmpty { ToolbarItem(placement: .topBarTrailing) { EditButton() } }
        }
        .sheet(isPresented: $adding) { CreatorEditor(c: nil) }
        .sheet(isPresented: $importing) { CreatorImportView() }
        .sheet(item: $editing) { CreatorEditor(c: $0) }
    }

    private func open(_ s: String) { openCreator(s, openURL) }
}

// 从截图里读二维码，返回里面的链接（普通二维码；小图会放大再试一次）
func readQR(_ cg: CGImage) -> String? {
    func scan(_ img: CGImage) -> String? {
        let req = VNDetectBarcodesRequest()
        try? VNImageRequestHandler(cgImage: img).perform([req])
        for o in req.results ?? [] {
            if let s = o.payloadStringValue, let r = s.range(of: #"https?://\S+"#, options: .regularExpression) { return String(s[r]) }
        }
        return nil
    }
    if let u = scan(cg) { return u }
    if cg.width < 1500, let big = scaled(cg, 2) { return scan(big) }
    return nil
}

private func scaled(_ cg: CGImage, _ k: CGFloat) -> CGImage? {
    let w = Int(CGFloat(cg.width) * k), h = Int(CGFloat(cg.height) * k)
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.interpolationQuality = .high
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    return ctx.makeImage()
}

// 抖音“主页二维码”卡片是抖音自家的圆形码，系统扫不出来。
// 改成读卡片上的字：@名字、抖音号、简介，并把中间的头像裁下来。
struct DouyinCard { var name: String?; var id: String?; var bio: String?; var avatar: Data? }

func readDouyinCard(_ cg: CGImage) -> DouyinCard? {
    let req = VNRecognizeTextRequest()
    req.recognitionLevel = .accurate
    req.recognitionLanguages = ["zh-Hans", "en-US"]
    req.usesLanguageCorrection = false
    try? VNImageRequestHandler(cgImage: cg).perform([req])
    let obs = (req.results ?? []).compactMap { o -> (String, CGRect)? in
        guard let t = o.topCandidates(1).first?.string else { return nil }
        return (t.trimmingCharacters(in: .whitespaces), o.boundingBox)
    }
    var card = DouyinCard()
    var nameBox: CGRect? = nil, idBox: CGRect? = nil
    for (t, b) in obs {
        if card.id == nil, let r = t.range(of: #"抖音号\s*[:：]?\s*"#, options: .regularExpression) {
            let v = t[r.upperBound...].trimmingCharacters(in: .whitespaces)
            if !v.isEmpty { card.id = v; idBox = b }
        } else if card.name == nil, t.hasPrefix("@") || t.hasPrefix("＠") {
            card.name = String(t.dropFirst()).trimmingCharacters(in: .whitespaces); nameBox = b
        }
    }
    guard card.id != nil || card.name != nil else { return nil }
    // 简介：抖音号正下方最近的一行
    if let ib = idBox {
        let below = obs.filter { $0.1.midY < ib.minY && ib.minY - $0.1.maxY < ib.height * 2.5
                                 && !$0.0.contains("保存") && !$0.0.contains("扫一扫") }
        if let b = below.max(by: { $0.1.midY < $1.1.midY }) {
            card.bio = b.0.trimmingCharacters(in: CharacterSet(charactersIn: "⭐️★☆ "))
        }
    }
    // 头像：在名字上方、圆形码正中间。用“名字到抖音号”的行距做尺子，截图大小不同也能对上。
    if let nb = nameBox {
        let W = CGFloat(cg.width), H = CGFloat(cg.height)
        let gap = (idBox.map { (nb.midY - $0.midY) * H }) ?? (W * 0.078)
        let side = gap * 3.2
        let cx = nb.midX * W, cy = (1 - nb.midY) * H - gap * 5.1
        let rect = CGRect(x: cx - side / 2, y: cy - side / 2, width: side, height: side).integral
        if gap > 0, rect.minX >= 0, rect.minY >= 0, rect.maxX <= W, rect.maxY <= H, let crop = cg.cropping(to: rect) {
            card.avatar = UIImage(cgImage: crop).jpegData(compressionQuality: 0.85)
        }
    }
    return card
}

// 链接就直接打开；填的是抖音号或名字就拉起抖音搜索
func openCreator(_ s: String, _ openURL: OpenURLAction) {
    let t = s.trimmingCharacters(in: .whitespaces)
    if t.hasPrefix("http"), let u = URL(string: t) { openURL(u); return }
    let q = t.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
    // 只跳一次：装了抖音就用 App 搜，没装才开网页
    if let app = URL(string: "snssdk1128://search?keyword=\(q)"), UIApplication.shared.canOpenURL(app) {
        openURL(app)
    } else if let web = URL(string: "https://www.douyin.com/search/\(q)") {
        openURL(web)
    }
}

// 赛事页顶部：前 5 个关注的博主
struct CreatorStrip: View {
    @ObservedObject private var cs = CreatorStore.shared
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 14) {
            if cs.list.isEmpty {
                NavigationLink { CreatorsView() } label: {
                    Label("添加关注的健身博主", systemImage: "person.badge.plus").font(.subheadline.bold())
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
            } else {
                ForEach(cs.list.prefix(5)) { c in
                    Button { Haptic.tap(); openCreator(c.link, openURL) } label: {
                        VStack(spacing: 4) {
                            CreatorAvatar(c: c, size: 50)
                                .overlay(Circle().strokeBorder(Brand.gradient, lineWidth: 2).padding(-3))
                            Text(c.name).font(.caption2).lineLimit(1).frame(width: 56)
                        }
                    }
                    .buttonStyle(PressScale())
                    .foregroundStyle(.primary)
                }
                Spacer(minLength: 0)
                NavigationLink { CreatorsView() } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "ellipsis").font(.headline)
                            .frame(width: 50, height: 50).background(Color.primary.opacity(0.08), in: Circle())
                        Text(cs.list.count > 5 ? "全部\(cs.list.count)" : "管理").font(.caption2)
                    }
                }
                .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
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
    @State private var qrPick: PhotosPickerItem? = nil
    @State private var qrMsg = ""
    @State private var avatar: Data? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("粘贴抖音分享的整段文字", text: $raw, axis: .vertical).lineLimit(2...5)
                        .onChange(of: raw) { _, t in apply(t) }
                    Button { if let t = UIPasteboard.general.string { raw = t } } label: {
                        Label("从剪贴板粘贴", systemImage: "doc.on.clipboard")
                    }
                    PhotosPicker(selection: $qrPick, matching: .images) {
                        Label("识别主页二维码卡片截图", systemImage: "qrcode.viewfinder")
                    }
                    if !qrMsg.isEmpty { Text(qrMsg).font(.footnote).foregroundStyle(.secondary) }
                } footer: { Text("会自动取出里面的链接。有链接点“抖音看”直接进主页；只填抖音号会打开抖音搜索。主页二维码：博主主页右上角“…”里找二维码，截图后点上面识别。") }
                Section {
                    HStack(spacing: 12) {
                        if let a = avatar, let ui = UIImage(data: a) {
                            Image(uiImage: ui).resizable().scaledToFill().frame(width: 44, height: 44).clipShape(Circle())
                        }
                        TextField("名字", text: $name)
                    }
                    TextField("备注，比如：练背、备赛", text: $note)
                    TextField("主页链接（直达主页）或 抖音号（打开搜索）", text: $link).textInputAutocapitalization(.never).autocorrectionDisabled()
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
                            old.name = n; old.note = note; old.link = link; if let avatar { old.avatar = avatar }; cs.list[i] = old
                        } else {
                            var new = Creator(name: n, note: note, link: link); new.avatar = avatar; cs.list.append(new)
                        }
                        Haptic.success(); dismiss()
                    }
                    .bold()
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || link.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onChange(of: qrPick) { _, p in
                Task {
                    guard let d = try? await p?.loadTransferable(type: Data.self), let cg = UIImage(data: d)?.cgImage else { return }
                    let found = await Task.detached { readQR(cg) }.value
                    if let u = found { link = u; qrMsg = "识别成功，点“抖音看”会直接进主页" }
                    else if let card = await Task.detached(operation: { readDouyinCard(cg) }).value {
                        if let n = card.name, name.isEmpty || c == nil { name = n }
                        if let i = card.id { link = i }
                        if let b = card.bio, note.isEmpty { note = b }
                        if let a = card.avatar { avatar = a }
                        qrMsg = "识别到：\(card.name ?? "") 抖音号 \(card.id ?? "没读到")" + (card.avatar != nil ? "，头像已取" : "")
                    }
                    else { qrMsg = "没识别到，换一张清楚点的截图试试" }
                    qrPick = nil
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

struct CreatorAvatar: View {
    let c: Creator
    var size: CGFloat = 42
    var body: some View {
        if let d = c.avatar, let ui = UIImage(data: d) {
            Image(uiImage: ui).resizable().scaledToFill().frame(width: size, height: size).clipShape(Circle())
        } else {
            Text(String(c.name.prefix(1))).font(.headline).foregroundStyle(.white)
                .frame(width: size, height: size).background(Brand.gradient, in: Circle())
        }
    }
}
