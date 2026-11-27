import SwiftUI
import CoreLocation
import MapKit
import PhotosUI

// MARK: - 健身房打卡地球：数据
// 服务器和问题记录共用（xt-bugs，香港机房）。只上传选中的健身房 + 昵称 + 部位，不传个人坐标。

// 训练里记的“本次训练地点”
struct GymRef: Codable, Hashable {
    var id: String = ""        // 服务器上的编号；空 = 还没在服务器建（网不好时先记着，之后补传）
    var name: String
    var city: String = ""
    var lat: Double
    var lon: Double
}

struct GymPerson: Codable, Hashable {
    var uid: String
    var nick: String
    var parts: [String]
    var t: Double
}

struct GymPending: Codable, Hashable { var url: String; var uid: String }

struct GymInfo: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var city: String
    var lat: Double
    var lon: Double
    var by: String
    var uid: String
    var total: Int
    var checkins: Int
    var week: Int
    var month: Int
    var top: [String]
    var cover: String?
    var photos: [String]
    var pending: [GymPending]
    var recent: [GymPerson]
    var ref: GymRef { GymRef(id: id, name: name, city: city, lat: lat, lon: lon) }
    func count(_ range: Int) -> Int { range == 0 ? week : range == 1 ? month : total }
}

struct GymWorld: Codable {
    var t: Double
    var weekPeople: Int
    var weekGyms: Int
    var monthPeople: Int
    var monthGyms: Int
    var allPeople: Int
    var gyms: [GymInfo]
}

enum GymAPI {
    static let base = "https://xt-bugs.vercel.app/api/"
    private static func req(_ path: String, method: String = "GET", json: Any? = nil, body: Data? = nil, type: String? = nil, timeout: Double = 15) -> URLRequest {
        var r = URLRequest(url: URL(string: base + path)!, timeoutInterval: timeout)
        r.httpMethod = method
        r.setValue("xtraining", forHTTPHeaderField: "X-App")
        if let json { r.httpBody = try? JSONSerialization.data(withJSONObject: json); r.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let body { r.httpBody = body; r.setValue(type ?? "application/octet-stream", forHTTPHeaderField: "Content-Type") }
        return r
    }
    private static func call(_ r: URLRequest) async -> [String: Any]? {
        guard let (d, resp) = try? await URLSession.shared.data(for: r), (resp as? HTTPURLResponse)?.statusCode == 200,
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], j["ok"] as? Bool == true else { return nil }
        return j
    }
    static func world() async -> (GymWorld, Data)? {
        guard let (d, resp) = try? await URLSession.shared.data(for: req("gyms", timeout: 20)), (resp as? HTTPURLResponse)?.statusCode == 200,
              let w = try? JSONDecoder().decode(GymWorld.self, from: d) else { return nil }
        return (w, d)
    }
    static func create(_ g: GymRef, by: String, uid: String) async -> String? {
        await call(req("gyms", method: "POST", json: ["name": g.name, "city": g.city, "lat": g.lat, "lon": g.lon, "by": by, "uid": uid]))?["id"] as? String
    }
    static func checkin(gym: String, uid: String, nick: String, parts: [String]) async -> Bool {
        await call(req("checkin", method: "POST", json: ["gym": gym, "uid": uid, "nick": nick, "parts": parts])) != nil
    }
    static func photo(gym: String, uid: String, jpg: Data) async -> Bool {
        await call(req("photo?gym=\(gym)&uid=\(uid)", method: "POST", body: jpg, type: "image/jpeg", timeout: 40)) != nil
    }
}

@MainActor
final class GymStore: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = GymStore()
    @Published var world: GymWorld? = nil
    @Published var loading = false
    @Published var failed = false
    @Published var location: CLLocation? = nil
    @Published var locDenied = false
    @Published var myUploads: [String: [Data]] = [:]   // 自己刚传、还在审核的照片（本机显示“审核中”）

    private let ud = UserDefaults.standard
    private let lm = CLLocationManager()

    let uid: String = {
        if let s = UserDefaults.standard.string(forKey: "xt.uid") { return s }
        let s = UUID().uuidString.lowercased(); UserDefaults.standard.set(s, forKey: "xt.uid"); return s
    }()
    // 公开到打卡地球（第一次打卡时问，默认打开）
    var isPublic: Bool {
        get { ud.object(forKey: "xt.gymPublic") as? Bool ?? true }
        set { ud.set(newValue, forKey: "xt.gymPublic"); objectWillChange.send() }
    }
    var lastGym: GymRef? {
        get { ud.data(forKey: "xt.lastGym").flatMap { try? JSONDecoder().decode(GymRef.self, from: $0) } }
        set { ud.set(try? JSONEncoder().encode(newValue), forKey: "xt.lastGym"); objectWillChange.send() }
    }
    // 没传上去的打卡，下次打开 App 再传
    private var queue: [[String: String]] {
        get { (ud.array(forKey: "xt.gymQueue") as? [[String: String]]) ?? [] }
        set { ud.set(newValue, forKey: "xt.gymQueue") }
    }
    private var sent: Set<String> {
        get { Set(ud.stringArray(forKey: "xt.gymSent") ?? []) }
        set { ud.set(Array(newValue.suffix(300)), forKey: "xt.gymSent") }
    }
    // 地球按钮上的小红点：我常去的健身房本周来的人比上次看时多了
    var seenCount: Int {
        get { ud.integer(forKey: "xt.gymSeen") }
        set { ud.set(newValue, forKey: "xt.gymSeen"); objectWillChange.send() }
    }
    var myGymWeek: Int { guard let g = lastGym, let w = world else { return 0 }; return w.gyms.first { $0.id == g.id }?.checkins ?? 0 }
    var hasNew: Bool { myGymWeek > seenCount && seenCount > 0 }

    override init() {
        super.init()
        lm.delegate = self
        lm.desiredAccuracy = kCLLocationAccuracyHundredMeters
        if let d = ud.data(forKey: "xt.gymWorld"), let w = try? JSONDecoder().decode(GymWorld.self, from: d) { world = w }
    }

    func refresh() async {
        if loading { return }
        loading = true; defer { loading = false }
        if let (w, d) = await GymAPI.world() {
            world = w; failed = false; ud.set(d, forKey: "xt.gymWorld")
            if seenCount == 0 { seenCount = max(1, myGymWeek) }
        } else { failed = true }
        await flush()
    }

    func gym(_ id: String) -> GymInfo? { world?.gyms.first { $0.id == id } }

    // MARK: 定位（只用来排附近的健身房，不上传）
    func locate() {
        switch lm.authorizationStatus {
        case .notDetermined: lm.requestWhenInUseAuthorization()
        case .denied, .restricted: locDenied = true
        default: lm.requestLocation()
        }
    }
    nonisolated func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        let s = m.authorizationStatus
        Task { @MainActor in
            self.locDenied = s == .denied || s == .restricted
            if s == .authorizedWhenInUse || s == .authorizedAlways { self.lm.requestLocation() }
        }
    }
    nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations l: [CLLocation]) {
        guard let x = l.last else { return }
        Task { @MainActor in self.location = x }
    }
    nonisolated func locationManager(_ m: CLLocationManager, didFailWithError e: Error) {}

    func distance(_ lat: Double, _ lon: Double) -> Double? {
        location.map { $0.distance(from: CLLocation(latitude: lat, longitude: lon)) }
    }
    // 打开训练页时：人在上次那家附近（1.5 公里内）就自动选上
    func suggestion() -> GymRef? {
        guard let g = lastGym, let d = distance(g.lat, g.lon), d < 1500 else { return nil }
        return g
    }

    // MARK: 建健身房 / 打卡 / 传照片
    func ensureID(_ g: GymRef) async -> GymRef? {
        if !g.id.isEmpty { return g }
        guard let id = await GymAPI.create(g, by: Store.nick, uid: uid) else { return nil }
        var r = g; r.id = id; return r
    }

    // 保存训练时调用：公开才传；同一次训练只传一次；传不上就排队
    func checkin(workoutID: String, gym: GymRef, parts: [String], date: String) {
        lastGym = gym
        guard isPublic, date == Day.today else { return }
        let key = workoutID + "|" + gym.name + "|" + parts.joined(separator: ",")
        guard !sent.contains(key) else { return }
        var q = queue.filter { $0["w"] != workoutID }
        q.append(["w": workoutID, "key": key, "id": gym.id, "name": gym.name, "city": gym.city, "lat": "\(gym.lat)", "lon": "\(gym.lon)", "parts": parts.joined(separator: ","), "date": date])
        queue = q
        Task { await flush() }
    }

    private var flushing = false
    func flush() async {
        guard !flushing else { return }
        flushing = true; defer { flushing = false }
        for item in queue {
            // 隔天的就不补了（打卡只算当天）
            guard item["date"] == Day.today else { queue = queue.filter { $0 != item }; continue }
            let ref = GymRef(id: item["id"] ?? "", name: item["name"] ?? "", city: item["city"] ?? "", lat: Double(item["lat"] ?? "") ?? 0, lon: Double(item["lon"] ?? "") ?? 0)
            guard let g = await ensureID(ref) else { return }
            if lastGym?.name == g.name && (lastGym?.id ?? "").isEmpty { lastGym = g }
            let parts = (item["parts"] ?? "").split(separator: ",").map(String.init)
            guard await GymAPI.checkin(gym: g.id, uid: uid, nick: Store.nick, parts: parts) else { return }
            queue = queue.filter { $0 != item }
            sent.insert(item["key"] ?? "")
        }
        if !queue.isEmpty { return }
        // 打完卡刷新一下地球
        if let (w, d) = await GymAPI.world() { world = w; ud.set(d, forKey: "xt.gymWorld") }
    }

    func upload(photo: UIImage, gym: String) async -> Bool {
        guard let jpg = photo.gymJPEG() else { return false }
        let ok = await GymAPI.photo(gym: gym, uid: uid, jpg: jpg)
        if ok { myUploads[gym, default: []].append(jpg) }
        return ok
    }
}

extension Store {
    // 打卡用的昵称（没起名就叫“健身人”）
    static var nick: String {
        let n = UserDefaults.standard.string(forKey: "xt.nickname") ?? ""
        return n.trimmingCharacters(in: .whitespaces).isEmpty ? "健身人" : n
    }
}

extension UIImage {
    // 裁成正方形（照片都是圆形显示），缩到 1080px，压成 jpg
    func gymJPEG() -> Data? {
        let s = min(size.width, size.height)
        guard s > 0 else { return nil }
        let crop = CGRect(x: (size.width - s) / 2, y: (size.height - s) / 2, width: s, height: s)
        let side = min(1080, s)
        let f = UIGraphicsImageRendererFormat(); f.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: f).image { _ in
            draw(in: CGRect(x: -crop.minX * side / s, y: -crop.minY * side / s, width: size.width * side / s, height: size.height * side / s))
        }
        return img.jpegData(compressionQuality: 0.78)
    }
}

// MARK: - 圆形健身房头像（没有照片就是渐变 + 哑铃）
struct GymAvatar: View {
    var url: String?
    var seed: String
    var size: CGFloat
    var ring = false
    var local: Data? = nil

    static let palettes: [[Color]] = [
        [Color(hex: 0xff7a00), Color(hex: 0xe03131)], [Color(hex: 0x0a84ff), Color(hex: 0x5e5ce6)],
        [Color(hex: 0x2f9e44), Color(hex: 0x94d82d)], [Color(hex: 0x8134af), Color(hex: 0xdd2a7b)],
        [Color(hex: 0x2b2d42), Color(hex: 0x5c677d)], [Color(hex: 0x12b886), Color(hex: 0x1098ad)],
    ]
    static func palette(_ seed: String) -> [Color] { palettes[abs(seed.unicodeScalars.reduce(7) { ($0 &* 31 &+ Int($1.value)) % 100003 }) % palettes.count] }

    var body: some View {
        let inner = Group {
            if let local, let img = UIImage(data: local) {
                Image(uiImage: img).resizable().scaledToFill()
            } else if let url, let u = URL(string: url) {
                AsyncImage(url: u, transaction: Transaction(animation: .easeOut(duration: 0.2))) { ph in
                    if let img = ph.image { img.resizable().scaledToFill() } else { fallback }
                }
            } else { fallback }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        if ring {
            inner.padding(max(2, size * 0.05))
                .background(Circle().fill(Color(.systemBackground)))
                .padding(max(2, size * 0.05))
                .background(Circle().fill(LinearGradient(colors: [Color(hex: 0xf58529), Color(hex: 0xdd2a7b), Color(hex: 0x8134af)], startPoint: .topLeading, endPoint: .bottomTrailing)))
        } else { inner }
    }
    private var fallback: some View {
        ZStack {
            LinearGradient(colors: Self.palette(seed), startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "dumbbell.fill").font(.system(size: size * 0.38, weight: .bold)).foregroundStyle(.white)
        }
    }
}

// 别人的小头像：昵称第一个字 + 按 id 配色
struct PersonDot: View {
    var nick: String
    var uid: String
    var size: CGFloat = 46
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: GymAvatar.palette(uid), startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(nick.first.map(String.init) ?? "X").font(.system(size: size * 0.4, weight: .heavy)).foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

func fmtDist(_ m: Double) -> String { m < 1000 ? "\(Int(m / 10) * 10) m" : String(format: "%.1f km", m / 1000) }
