import SwiftUI
import WebKit

// 首页顶部：YouTube 健身博主最新视频，竖版海报轮播。
// 数据来自 YouTube 公开的频道 RSS（不需要 API 密钥）；播放用官方嵌入播放器；缩略图原样显示不裁剪。

struct YTChannel: Codable, Identifiable, Hashable {
    var handle: String          // 不带 @
    var cid: String = ""        // UC 开头的频道 ID，空时用 handle 解析
    var name: String = ""
    var id: String { handle.lowercased() }
}

struct YTVideo: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var channel: String
    var date: Date
    var thumb: URL? { URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg") }
    var watch: URL? { URL(string: "https://www.youtube.com/watch?v=\(id)") }
}

@MainActor
final class YTFeed: ObservableObject {
    static let shared = YTFeed()
    static let defaults: [YTChannel] = [
        YTChannel(handle: "JeffNippard", cid: "UC68TLK0mAEzUyHx5x5k-S1Q", name: "Jeff Nippard"),
        YTChannel(handle: "ChrisBumstead", name: "Chris Bumstead"),
        YTChannel(handle: "athleanx", cid: "UCe0TLA0EsQbE-MjuHXevj2A", name: "ATHLEAN-X"),
        YTChannel(handle: "JeremyEthier", name: "Jeremy Ethier"),
        YTChannel(handle: "RenaissancePeriodization", name: "Renaissance Periodization"),
    ]

    @Published var channels: [YTChannel] { didSet { save(channels, "xt.ytChannels") } }
    @Published var videos: [YTVideo] { didSet { save(videos, "xt.ytCache") } }
    @Published var loading = false
    @Published var failed = false
    private var last: Date = .distantPast

    private init() {
        channels = Self.load("xt.ytChannels") ?? Self.defaults
        videos = Self.load("xt.ytCache") ?? []
    }

    func refresh(force: Bool = false) async {
        guard !loading, force || Date().timeIntervalSince(last) > 600 else { return }
        loading = true; defer { loading = false }
        var all: [YTVideo] = []
        let snap = channels
        var chs = snap
        await withTaskGroup(of: (Int, YTChannel, [YTVideo]).self) { g in
            for (i, c) in snap.enumerated() {
                g.addTask { await Self.fetch(c).map { (i, $0.0, $0.1) } ?? (i, c, []) }
            }
            for await (i, c, vs) in g {
                if i < chs.count { chs[i] = c }
                all += vs.prefix(2)               // 每个频道取最新 2 条
            }
        }
        if chs != channels { channels = chs }
        if all.isEmpty { failed = videos.isEmpty; return }
        failed = false; last = Date()
        videos = Array(all.sorted { $0.date > $1.date }.prefix(10))
    }

    func add(_ raw: String) async -> Bool {
        var h = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = h.range(of: "@") { h = String(h[r.upperBound...]) }
        h = h.components(separatedBy: CharacterSet(charactersIn: "/?& ")).first ?? h
        guard !h.isEmpty, !channels.contains(where: { $0.id == h.lowercased() }) else { return false }
        guard let r = await Self.fetch(YTChannel(handle: h)), !r.1.isEmpty else { return false }
        channels.append(r.0)
        await refresh(force: true)
        return true
    }

    func remove(_ c: YTChannel) {
        channels.removeAll { $0.id == c.id }
        videos.removeAll { $0.channel == c.name }
    }

    // MARK: 网络

    nonisolated static func fetch(_ c: YTChannel) async -> (YTChannel, [YTVideo])? {
        var c = c
        if !c.cid.isEmpty, let (name, vs) = await rss(c.cid), !vs.isEmpty {
            if c.name.isEmpty { c.name = name }
            return (c, vs)
        }
        guard let id = await resolve(c.handle), let (name, vs) = await rss(id) else { return nil }
        c.cid = id
        if !name.isEmpty { c.name = name }
        return (c, vs)
    }

    nonisolated static func request(_ url: URL) -> URLRequest {
        var r = URLRequest(url: url, timeoutInterval: 12)
        r.setValue("SOCS=CAI; CONSENT=YES+1", forHTTPHeaderField: "Cookie")
        r.setValue("en", forHTTPHeaderField: "Accept-Language")
        return r
    }

    // @handle → UC 频道 ID（读频道主页里的 canonical 链接）
    nonisolated static func resolve(_ handle: String) async -> String? {
        guard let u = URL(string: "https://www.youtube.com/@\(handle)"),
              let (d, _) = try? await URLSession.shared.data(for: request(u)),
              let html = String(data: d, encoding: .utf8) else { return nil }
        for p in [#"channel/(UC[A-Za-z0-9_-]{22})"#, #""externalId":"(UC[A-Za-z0-9_-]{22})""#, #""channelId":"(UC[A-Za-z0-9_-]{22})""#] {
            if let r = try? NSRegularExpression(pattern: p),
               let m = r.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let g = Range(m.range(at: 1), in: html) { return String(html[g]) }
        }
        return nil
    }

    nonisolated static func rss(_ id: String) async -> (String, [YTVideo])? {
        guard let u = URL(string: "https://www.youtube.com/feeds/videos.xml?channel_id=\(id)"),
              let (d, resp) = try? await URLSession.shared.data(for: request(u)),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let p = RSSParser(); let x = XMLParser(data: d); x.delegate = p
        guard x.parse() else { return nil }
        return (p.channel, p.items)
    }

    private func save<T: Encodable>(_ v: T, _ k: String) {
        if let d = try? JSONEncoder().encode(v) { UserDefaults.standard.set(d, forKey: k) }
    }
    private static func load<T: Decodable>(_ k: String) -> T? {
        UserDefaults.standard.data(forKey: k).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }
}

final class RSSParser: NSObject, XMLParserDelegate {
    var channel = ""
    var items: [YTVideo] = []
    private var inEntry = false, inAuthor = false
    private var text = "", vid = "", title = "", author = "", pub = "", link = ""
    private let iso = ISO8601DateFormatter()

    func parser(_ p: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName q: String?, attributes a: [String: String] = [:]) {
        text = ""
        switch e {
        case "entry": inEntry = true; vid = ""; title = ""; author = ""; pub = ""; link = ""
        case "author": inAuthor = true
        case "link" where inEntry: link = a["href"] ?? ""
        default: break
        }
    }
    func parser(_ p: XMLParser, foundCharacters s: String) { text += s }
    func parser(_ p: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName q: String?) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch e {
        case "yt:videoId": vid = t
        case "title": if inEntry { title = t }
        case "name": if inAuthor { if inEntry { author = t } else { channel = t } }
        case "published": if inEntry { pub = t }
        case "author": inAuthor = false
        case "entry":
            inEntry = false
            // 跳过 Shorts（竖屏短视频）
            if !vid.isEmpty, !link.contains("/shorts/"), !title.lowercased().contains("#shorts") {
                items.append(YTVideo(id: vid, title: title, channel: author.isEmpty ? channel : author,
                                     date: iso.date(from: pub) ?? .distantPast))
            }
        default: break
        }
    }
}

// MARK: 海报轮播

struct YTCarousel: View {
    @ObservedObject private var feed = YTFeed.shared
    @Environment(\.scenePhase) private var phase
    @State private var page = 0
    @State private var playing: YTVideo?
    @State private var manage = false

    var body: some View {
        let list = feed.videos
        VStack(spacing: 10) {
            if list.isEmpty {
                empty
            } else {
                TabView(selection: $page) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, v in
                        YTPoster(video: v) { Haptic.tap(.medium); playing = v }
                            .tag(i).padding(.horizontal, 2)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 470)
                HStack(spacing: 6) {
                    ForEach(list.indices, id: \.self) { i in
                        Capsule().fill(i == page ? Color.primary : Color.primary.opacity(0.25))
                            .frame(width: i == page ? 22 : 7, height: 7)
                    }
                }
                .animation(.snappy, value: page)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button { manage = true } label: {
                Image(systemName: "slider.horizontal.3").font(.footnote.bold()).foregroundStyle(.white)
                    .frame(width: 34, height: 34).background(.ultraThinMaterial, in: Circle())
            }
            .padding(14)
        }
        .sheet(item: $playing) { YTPlayerSheet(video: $0) }
        .sheet(isPresented: $manage) { YTChannelEditor() }
        .task(id: phase) { if phase == .active { await feed.refresh() } }
        .task(id: "\(list.count)-\(playing == nil)") {
            guard !Motion.calm, list.count > 1, playing == nil else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(7))
                if Task.isCancelled { break }
                withAnimation(.easeInOut(duration: 0.6)) { page = (page + 1) % max(list.count, 1) }
            }
        }
        .onChange(of: list.count) { _, n in if page >= n { page = 0 } }
    }

    private var empty: some View {
        VStack(spacing: 14) {
            Image(systemName: "play.rectangle.fill").font(.system(size: 44)).foregroundStyle(.white.opacity(0.85))
            Text(feed.loading ? "正在加载健身视频…" : "连不上 YouTube").font(.title3.bold()).foregroundStyle(.white)
            Text("YouTube 在国内需要网络代理。连上后下拉或点下面重试。")
                .font(.footnote).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center)
            if feed.loading { ProgressView().tint(.white) } else {
                Button("重试") { Task { await feed.refresh(force: true) } }
                    .font(.subheadline.bold()).padding(.horizontal, 22).padding(.vertical, 10)
                    .background(.white, in: Capsule()).foregroundStyle(.black)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity).frame(height: 300)
        .background(LinearGradient(colors: [Color(hex: 0x1c1c1e), Color(hex: 0x2c2c2e)], startPoint: .top, endPoint: .bottom),
                    in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

struct YTPoster: View {
    let video: YTVideo
    var play: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "play.rectangle.fill").foregroundStyle(Color(hex: 0xff3b30))
                Text(video.channel).font(.subheadline.bold()).lineLimit(1)
                Spacer()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 16)

            // 官方缩略图：原样 16:9 显示，不裁剪、不加滤镜
            AsyncImage(url: video.thumb) { ph in
                switch ph {
                case .success(let img): img.resizable().aspectRatio(16 / 9, contentMode: .fit)
                default: Rectangle().fill(.white.opacity(0.08)).aspectRatio(16 / 9, contentMode: .fit)
                        .overlay { ProgressView().tint(.white) }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 14)
            .onTapGesture(perform: play)

            Spacer(minLength: 14)
            VStack(alignment: .leading, spacing: 8) {
                Text(video.title).font(.title2.bold()).foregroundStyle(.white)
                    .lineLimit(3).minimumScaleFactor(0.8)
                Text(ago(video.date)).font(.footnote).foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 20)
            Spacer(minLength: 14)

            HStack(spacing: 10) {
                Button(action: play) {
                    Label("立即播放", systemImage: "play.fill")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(.white, in: Capsule()).foregroundStyle(.black)
                }
                .buttonStyle(PressScale())
                if let u = video.watch {
                    Link(destination: u) {
                        Image(systemName: "arrow.up.right").font(.headline).foregroundStyle(.white)
                            .frame(width: 50, height: 50).background(.white.opacity(0.15), in: Circle())
                    }
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(colors: [Color(hex: 0x111114), Color(hex: 0x23232a)], startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func ago(_ d: Date) -> String {
        let days = Int(Date().timeIntervalSince(d) / 86400)
        switch days {
        case ..<1: return "今天发布"
        case 1: return "昨天发布"
        case ..<30: return "\(days) 天前发布"
        default: return "\(days / 30) 个月前发布"
        }
    }
}

// MARK: 播放（官方嵌入播放器）

struct YTPlayerSheet: View {
    let video: YTVideo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(video.channel).font(.subheadline.bold()).foregroundStyle(.secondary)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.footnote.bold()).frame(width: 32, height: 32)
                        .background(Color.primary.opacity(0.08), in: Circle())
                }
                .foregroundStyle(.primary)
            }
            YTEmbed(id: video.id)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text(video.title).font(.title3.bold())
            Text("视频来自 YouTube，需要网络代理才能播放。播放不了可以去 YouTube 看。")
                .font(.footnote).foregroundStyle(.secondary)
            if let u = video.watch {
                Link(destination: u) {
                    Label("在 YouTube 打开", systemImage: "arrow.up.right.square")
                        .font(.subheadline.bold()).frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                }
                .foregroundStyle(.primary)
            }
            Spacer()
        }
        .padding(20)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

struct YTEmbed: UIViewRepresentable {
    let id: String

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.allowsPictureInPictureMediaPlayback = true
        let w = WKWebView(frame: .zero, configuration: cfg)
        w.isOpaque = false
        w.backgroundColor = .black
        w.scrollView.isScrollEnabled = false
        let html = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <meta name="referrer" content="strict-origin-when-cross-origin">
        <style>html,body{margin:0;height:100%;background:#000}iframe{position:absolute;inset:0;width:100%;height:100%;border:0}</style>
        </head><body>
        <iframe src="https://www.youtube-nocookie.com/embed/\(id)?playsinline=1&autoplay=1&rel=0"
          allow="autoplay; encrypted-media; picture-in-picture; fullscreen" allowfullscreen
          referrerpolicy="strict-origin-when-cross-origin"></iframe>
        </body></html>
        """
        // 需要一个 https 来源，否则嵌入播放器会报 152/153 错误
        w.loadHTMLString(html, baseURL: URL(string: "https://xtraining-events.vercel.app"))
        return w
    }

    func updateUIView(_ w: WKWebView, context: Context) {}
}

// MARK: 管理频道

struct YTChannelEditor: View {
    @ObservedObject private var feed = YTFeed.shared
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var adding = false
    @State private var msg = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("@频道名 或 频道链接", text: $input)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        if adding { ProgressView() } else {
                            Button("添加") {
                                adding = true; msg = ""
                                Task {
                                    let ok = await feed.add(input)
                                    adding = false
                                    msg = ok ? "已添加" : "没找到这个频道，或者现在连不上 YouTube"
                                    if ok { input = "" }
                                }
                            }
                            .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                } footer: {
                    Text(msg.isEmpty ? "在 YouTube 频道页能看到 @ 开头的名字，比如 @JeffNippard。" : msg)
                }
                Section("我关注的频道") {
                    ForEach(feed.channels) { c in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.name.isEmpty ? c.handle : c.name).font(.body.bold())
                            Text("@" + c.handle).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { idx in idx.map { feed.channels[$0] }.forEach(feed.remove) }
                    .onMove { feed.channels.move(fromOffsets: $0, toOffset: $1) }
                }
                Section {
                    Button("恢复默认频道") { feed.channels = YTFeed.defaults; Task { await feed.refresh(force: true) } }
                }
            }
            .navigationTitle("健身视频频道")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss(); Task { await feed.refresh(force: true) } }
                }
            }
        }
    }
}
