import SwiftUI
import UserNotifications

// MARK: 比赛
struct Podium: Codable, Hashable { var d: String; var t: [String] }

struct Race: Codable, Identifiable, Hashable {
    let id: String
    var date: String?
    var end: String?
    var name: String
    var en: String?
    var city: String?
    var country: String?
    var org: String
    var level: String
    var divs: String?
    var desc: String?
    var dy: String?
    var url: String?
    var region: String?
    var time: String?
    var est: Bool?
    var tz: Double?
    var lt: String?
    var res: [Podium]?      // 已结束比赛的各组前三名
    var resNote: String?

    var isWorld: Bool { region == "world" }
    // 开赛时刻：国内按北京时间；国外按当地时间 + 时区
    var startAt: Date? {
        guard let d = date else { return nil }
        let p = d.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        var c = DateComponents(); c.year = p[0]; c.month = p[1]; c.day = p[2]
        var cal = Calendar(identifier: .gregorian)
        if let lt, let tz {
            let hm = lt.split(separator: ":").compactMap { Int($0) }
            c.hour = hm.first ?? 10; c.minute = hm.count > 1 ? hm[1] : 0
            cal.timeZone = TimeZone(secondsFromGMT: Int(tz * 3600)) ?? .gmt
        } else {
            let hm = (time ?? "09:00").split(separator: ":").compactMap { Int($0) }
            c.hour = hm.first ?? 9; c.minute = hm.count > 1 ? hm[1] : 0
            cal.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        }
        return cal.date(from: c)
    }
    var hasTime: Bool { time != nil || lt != nil }
    var timeText: String {
        guard let t = startAt else { return "日期待公布" }
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN")
        f.timeZone = TimeZone(identifier: "Asia/Shanghai"); f.dateFormat = "M/d HH:mm"
        var s = "北京 " + f.string(from: t)
        if let lt { s += " · 当地 \(lt)" }
        if est == true { s += " 预计" }
        return s
    }
    var poster: (Color, Color, String) {
        if isWorld, let c = country, let l = Race.land[c] { return l }
        return Race.posters[org] ?? (Color(hex: 0x2c2c2e), Color(hex: 0xc41e3a), "PRO")
    }
    static let posters: [String: (Color, Color, String)] = [
        "寰际": (Color(hex: 0xff9f0a), Color(hex: 0xd70015), "HUANJI"),
        "环球": (Color(hex: 0x0a84ff), Color(hex: 0x30d0ff), "GLOBAL"),
        "MEGA": (Color(hex: 0xbf5af2), Color(hex: 0xff2d92), "MEGA"),
        "奥赛": (Color(hex: 0x1c1c1e), Color(hex: 0xa2845e), "OLYMPIA"),
        "阿诺德": (Color(hex: 0x8e0000), Color(hex: 0xff6b00), "ARNOLD"),
        "IFBB": (Color(hex: 0x2c2c2e), Color(hex: 0xc41e3a), "IFBB PRO"),
    ]
    // 按国家配色（只用颜色，不用官方图片）
    static let land: [String: (Color, Color, String)] = [
        "美国": (Color(hex: 0x0a3161), Color(hex: 0xb31942), "USA"), "科威特": (Color(hex: 0x007a3d), Color(hex: 0xce1126), "KUWAIT"),
        "罗马尼亚": (Color(hex: 0x002b7f), Color(hex: 0xfcd116), "ROMANIA"), "巴西": (Color(hex: 0x009c3b), Color(hex: 0xffdf00), "BRASIL"),
        "西班牙": (Color(hex: 0xaa151b), Color(hex: 0xf1bf00), "ESPAÑA"), "葡萄牙": (Color(hex: 0x006600), Color(hex: 0xff0000), "PORTUGAL"),
        "印度": (Color(hex: 0xff9933), Color(hex: 0x138808), "INDIA"), "阿根廷": (Color(hex: 0x74acdf), Color(hex: 0x3a6ea5), "ARGENTINA"),
        "南非": (Color(hex: 0x007749), Color(hex: 0xffb81c), "SOUTH AFRICA"), "奥地利": (Color(hex: 0xc8102e), Color(hex: 0x7a0019), "AUSTRIA"),
        "新西兰": (Color(hex: 0x00247d), Color(hex: 0xcc142b), "NEW ZEALAND"), "沙特阿拉伯": (Color(hex: 0x006c35), Color(hex: 0x0b3d1f), "SAUDI"),
        "泰国": (Color(hex: 0x2d2a4a), Color(hex: 0xa51931), "THAILAND"), "中国台湾": (Color(hex: 0x0a84ff), Color(hex: 0x5e5ce6), "TAIWAN"),
    ]
    // 比赛清单：优先用联网拉到的最新版，拉不到就用上次缓存，再不行用 App 自带的
    static var all: [Race] { RaceFeed.shared.list }
    // 还没结束的比赛，按日期排
    static func upcoming(_ region: String? = nil) -> [Race] {
        all.filter { e in (e.date == nil || (e.end ?? e.date!) >= Day.today) && (region == nil || (e.region ?? "cn") == region) }
            .sorted { ($0.date ?? "9") < ($1.date ?? "9") }
    }
    var isPast: Bool { guard let d = date else { return false }; return (end ?? d) < Day.today }
    // 已经比完的，最近的排前面
    static func past() -> [Race] {
        all.filter(\.isPast).sorted { ($0.date ?? "") > ($1.date ?? "") }
    }
}

// MARK: 比赛清单联网更新
final class RaceFeed: ObservableObject {
    static let shared = RaceFeed()
    static let url = URL(string: "https://xtraining-events.vercel.app/events.json")!
    private static let cacheKey = "xt.eventsCache"
    @Published private(set) var list: [Race]
    @Published private(set) var updated: String = ""
    private struct Feed: Codable { var updated: String?; var events: [Race] }

    private init() {
        if let d = UserDefaults.standard.data(forKey: Self.cacheKey),
           let f = try? JSONDecoder().decode(Feed.self, from: d), !f.events.isEmpty {
            list = f.events; updated = f.updated ?? ""
        } else {
            list = (try? JSONDecoder().decode([Race].self, from: Data(eventsJSON.utf8))) ?? []
        }
    }

    // 拉最新清单；追了的比赛改了时间就重新排提醒，取消了的比赛就撤掉提醒
    func refresh(follow: [String]) async {
        var req = URLRequest(url: Self.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let f = try? JSONDecoder().decode(Feed.self, from: data), !f.events.isEmpty else { return }
        UserDefaults.standard.set(data, forKey: Self.cacheKey)
        let old = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let new = Dictionary(f.events.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for id in follow {
            switch (old[id], new[id]) {
            case let (o?, n?) where o.startAt != n.startAt || o.hasTime != n.hasTime || o.name != n.name:
                Reminders.cancel(o); Reminders.schedule(n)
            case let (o?, nil):
                Reminders.cancel(o)
            case let (_, n?):
                Reminders.schedule(n)   // 没变也重排一次，新加的提醒（比如前一天）能补上
            default: break
            }
        }
        await MainActor.run { self.list = f.events; self.updated = f.updated ?? "" }
    }
}

// MARK: 提醒（前一天 + 开赛前 30 分钟 + 开赛时）
enum Reminders {
    static func schedule(_ e: Race, confirm: Bool = false) {
        guard let t = e.startAt else { return }
        let c = UNUserNotificationCenter.current()
        c.requestAuthorization(options: [.alert, .sound, .badge]) { ok, _ in
            guard ok else { return }
            var items: [(String, Date, String)] = e.hasTime
                ? [("0", t.addingTimeInterval(-1800), "30 分钟后开赛"), ("1", t, "开赛了")]
                : [("1", t, "今天比赛")]
            // 前一天晚上 8 点再提醒一次
            if let eve = Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: t.addingTimeInterval(-86400)) {
                items.insert(("d", eve, "明天比赛"), at: 0)
            }
            let future = items.filter { $0.1 > Date() }
            for (k, when, body) in future {
                let n = UNMutableNotificationContent()
                n.title = e.name; n.body = "\(body) · \(e.city ?? "")"; n.sound = .default
                let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: when)
                c.add(UNNotificationRequest(identifier: "race-\(e.id)-\(k)", content: n,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
            }
            // 点“追赛”时马上来一条确认通知，告诉你会在什么时候提醒
            if confirm, !future.isEmpty {
                let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = "M月d日 HH:mm"
                let n = UNMutableNotificationContent()
                n.title = "已追：\(e.name)"
                n.body = "会在 " + future.map { f.string(from: $0.1) }.joined(separator: "、") + " 提醒你"
                n.sound = .default
                c.add(UNNotificationRequest(identifier: "race-\(e.id)-ok", content: n,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)))
            }
        }
    }
    static func cancel(_ e: Race) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["race-\(e.id)-d", "race-\(e.id)-0", "race-\(e.id)-1"])
    }
}

// MARK: 赛事页：国内 / 全球职业赛 / 我追的，左右滑动切换
struct RacesView: View {
    @State private var tab = 0
    private let tabs = ["国内", "全球", "我追的", "已结束"]
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                CreatorStrip()
                Picker("", selection: $tab.animation(.snappy)) {
                    ForEach(tabs.indices, id: \.self) { Text(tabs[$0]).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16).padding(.bottom, 8)
                TabView(selection: $tab) {
                    RaceList(region: "cn").tag(0)
                    RaceList(region: "world").tag(1)
                    RaceList(onlyFollowed: true).tag(2)
                    RaceList(past: true).tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("赛事")
        }
    }
}

struct RaceList: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var feed = RaceFeed.shared
    var region: String? = nil
    var onlyFollowed = false
    var past = false
    @State private var open: String? = nil

    private var list: [Race] {
        if past { return Race.past() }
        return Race.upcoming(onlyFollowed ? nil : region).filter { !onlyFollowed || store.follow.contains($0.id) }
    }

    var body: some View {
        let items = list
        let dates = uniqueDates(items)
        ScrollViewReader { proxy in
            ScrollView {
                if items.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "trophy").font(.system(size: 40)).foregroundStyle(Brand.gradient)
                            .symbolEffect(.bounce, value: onlyFollowed)
                        Text(onlyFollowed ? "还没追比赛" : past ? "还没有结束的比赛" : "最近没有比赛").font(.headline)
                        if onlyFollowed {
                            Text("在“国内”或“全球职业赛”里点「追赛」，比赛前一天、开赛前 30 分钟都会提醒你").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 60).padding(.horizontal, 30)
                } else {
                    // 顶部一排比赛日期，点了跳过去
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(dates, id: \.self) { d in
                                Button { withAnimation { proxy.scrollTo(d, anchor: .top) } } label: {
                                    VStack(spacing: 2) {
                                        Text(weekday(d)).font(.caption2).foregroundStyle(.secondary)
                                        Text(md(d)).font(.subheadline.bold())
                                    }
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.bottom, 6)
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(groups(items), id: \.0) { k, rs in
                            HStack {
                                Text(head(k)).font(.headline)
                                Spacer()
                                Text(left(k)).font(.caption.bold()).foregroundStyle(Brand.pink)
                            }
                            .padding(.top, 8)
                            .id(k)
                            ForEach(rs) { e in
                                RaceCard(e: e, open: open == e.id) {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { open = open == e.id ? nil : e.id }
                                }
                                .scrollTransition { c, phase in
                                    c.opacity(phase.isIdentity ? 1 : 0.5).scaleEffect(phase.isIdentity ? 1 : 0.94)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(maxWidth: 720).frame(maxWidth: .infinity)
                    if !feed.updated.isEmpty {
                        Text("赛程更新于 \(feed.updated) · 下拉刷新").font(.caption2).foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity).padding(.top, 14)
                    }
                    Color.clear.frame(height: 30)
                }
            }
            .refreshable { await feed.refresh(follow: store.follow) }
            .task { await feed.refresh(follow: store.follow) }
        }
    }

    private func uniqueDates(_ items: [Race]) -> [String] {
        var seen = Set<String>(), out: [String] = []
        for e in items { if let d = e.date, seen.insert(d).inserted { out.append(d) } }
        return out
    }
    private func groups(_ items: [Race]) -> [(String, [Race])] {
        var out: [(String, [Race])] = []
        for e in items {
            let k = e.date ?? "tbd"
            if let i = out.firstIndex(where: { $0.0 == k }) { out[i].1.append(e) } else { out.append((k, [e])) }
        }
        return out
    }
    private func weekday(_ d: String) -> String {
        ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][Calendar.current.component(.weekday, from: Day.date(d)) - 1]
    }
    private func md(_ d: String) -> String {
        let p = d.split(separator: "-"); return p.count == 3 ? "\(Int(p[1]) ?? 0)/\(Int(p[2]) ?? 0)" : d
    }
    private func head(_ k: String) -> String {
        if k == "tbd" { return "日期待公布" }
        let n = Day.between(Day.today, k)
        return (n == 0 ? "今天 · " : n == 1 ? "明天 · " : "") + "\(weekday(k)) \(md(k))"
    }
    private func left(_ k: String) -> String {
        if k == "tbd" { return "" }
        let n = Day.between(Day.today, k)
        if past { return "\(-n) 天前" }
        return n <= 0 ? "进行中" : "还有 \(n) 天"
    }
}

struct RaceCard: View {
    @EnvironmentObject var store: Store
    @Environment(\.openURL) private var openURL
    let e: Race
    let open: Bool
    let onTap: () -> Void
    @State private var denied = false

    // 通知被关掉时提示去设置里打开，不然追了也收不到
    private func checkPermission() {
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            let s = await UNUserNotificationCenter.current().notificationSettings()
            if s.authorizationStatus == .denied { denied = true }
        }
    }

    var body: some View {
        let followed = store.follow.contains(e.id)
        VStack(alignment: .leading, spacing: 10) {
            RacePoster(e: e)
            VStack(alignment: .leading, spacing: 4) {
                Text(e.name).font(.headline).lineLimit(2)
                Text([e.city, e.level].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                if let d = e.divs { Text(d).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                Text(e.timeText).font(.caption2.bold()).foregroundStyle(Brand.pink)
            }
            if open, let d = e.desc {
                Text(d).font(.subheadline).foregroundStyle(.secondary)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if e.isPast { PodiumView(e: e, open: open) }
            HStack(spacing: 8) {
                if !e.isPast {
                Button {
                    store.toggleFollow(e)
                    Haptic.tap(.medium)
                    if !followed { checkPermission() }
                } label: {
                    Label(followed ? "已追" : "追赛", systemImage: followed ? "bell.fill" : "bell")
                        .symbolEffect(.bounce, value: followed)
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .foregroundStyle(followed ? Brand.ink : Color.primary)
                        .background {
                            if followed { Capsule().fill(Brand.gradient) } else { Capsule().fill(Color(.tertiarySystemFill)) }
                        }
                }
                .buttonStyle(.plain)
                }
                if e.isWorld {
                    if let u = e.url, let url = URL(string: u) {
                        Button { openURL(url) } label: {
                            Label("官网", systemImage: "globe").font(.subheadline.bold()).frame(maxWidth: .infinity, minHeight: 36)
                                .foregroundStyle(.white).background(Capsule().fill(Color.blue))
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Button { douyin() } label: {
                        Label("抖音看", systemImage: "play.rectangle.fill").font(.subheadline.bold()).frame(maxWidth: .infinity, minHeight: 36)
                            .foregroundStyle(.white).background(Capsule().fill(Color.black))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .card()
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .alert("通知被关掉了", isPresented: $denied) {
            Button("去设置") { if let u = URL(string: UIApplication.openSettingsURLString) { openURL(u) } }
            Button("先不用", role: .cancel) {}
        } message: { Text("打开 X Training 的通知，追的比赛才能按时提醒你。") }
    }

    private func douyin() {
        let kw = e.dy ?? e.name
        let q = kw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let app = URL(string: "snssdk1128://search?keyword=\(q)"), UIApplication.shared.canOpenURL(app) {
            openURL(app)
        } else if let web = URL(string: "https://www.douyin.com/search/\(q)") {
            openURL(web)
        }
    }
}

// 首页顶部：36 小时内开赛的提醒条
struct RaceAlert: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var feed = RaceFeed.shared
    var body: some View {
        let soon = Race.upcoming().filter { e in
            guard store.follow.contains(e.id), let t = e.startAt else { return false }
            let h = t.timeIntervalSinceNow / 3600
            return h > -6 && h < 36
        }
        if let e = soon.first {
            HStack(spacing: 10) {
                Image(systemName: "bell.badge.fill").foregroundStyle(Brand.gradient)
                    .symbolEffect(.bounce, options: .repeat(3), value: e.id)
                VStack(alignment: .leading, spacing: 2) {
                    Text(e.name).font(.subheadline.bold())
                    Text(e.timeText).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .card()
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}


// 已结束比赛：各组前三名
struct PodiumView: View {
    let e: Race
    let open: Bool
    private let medals = ["🥇", "🥈", "🥉"]
    var body: some View {
        let res = e.res ?? []
        VStack(alignment: .leading, spacing: 8) {
            if res.isEmpty {
                Label(e.resNote ?? "成绩还没公布", systemImage: "hourglass").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(open ? res : Array(res.prefix(2)), id: \.d) { p in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(p.d).font(.caption.bold()).foregroundStyle(Brand.pink)
                        ForEach(Array(p.t.prefix(3).enumerated()), id: \.offset) { i, n in
                            HStack(spacing: 6) {
                                Text(medals[i]).font(.caption)
                                Text(n).font(i == 0 ? .subheadline.bold() : .subheadline).lineLimit(1).minimumScaleFactor(0.7)
                            }
                        }
                    }
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                if !open && res.count > 2 {
                    Text("点开看全部 \(res.count) 个组别").font(.caption2).foregroundStyle(.secondary)
                }
                if let n = e.resNote { Text(n).font(.caption2).foregroundStyle(.secondary) }
            }
        }
    }
}
