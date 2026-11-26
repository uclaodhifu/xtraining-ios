import SwiftUI
import Combine

// iCloud 同步：训练、体重、饮食、设置存一份到 iCloud（同一个 Apple ID 的 iPhone / iPad 之间自动同步）
// 用的是 iCloud 键值存储，数据压缩后放一个格子里；体态照片、头像、手写笔迹只留在本机
@MainActor
final class CloudSync: ObservableObject {
    static let shared = CloudSync()
    @Published var lastSync: Date? = nil
    @Published var note = ""
    var on: Bool {
        get { UserDefaults.standard.object(forKey: "xt.icloud") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "xt.icloud"); objectWillChange.send(); if newValue { pull(); push() } }
    }

    private let kv = NSUbiquitousKeyValueStore.default
    private let ud = UserDefaults.standard
    private weak var store: Store?
    private var bag: AnyCancellable?
    private var lastHash = 0

    private struct Blob: Codable {
        var t: Double
        var workouts: [Workout]
        var weights: [WeightRow]
        var food: [String: [String: Meal]]
        var restDays: [String]
        var doneDays: [String]
        var cycle: Cycle
        var liftCharts: [String: [String]]
        var follow: [String]
        var nickname: String
        var plateCfg: [String: PlateCfg]
        var deleted: [String]
    }

    // 删掉的训练记个编号，免得别的设备又同步回来
    private var deleted: Set<String> {
        get { Set(ud.stringArray(forKey: "xt.deletedIDs") ?? []) }
        set { ud.set(Array(newValue), forKey: "xt.deletedIDs") }
    }
    func noteDelete(_ ids: [String]) { deleted.formUnion(ids) }
    func forgive(_ ids: [String]) { deleted.subtract(ids) }

    func start(_ s: Store) {
        guard store == nil else { return }
        store = s
        if let t = ud.object(forKey: "xt.syncAt") as? Double { lastSync = Date(timeIntervalSince1970: t) }
        NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: kv, queue: .main) { _ in
            Task { @MainActor in CloudSync.shared.pull() }
        }
        kv.synchronize()
        pull()
        // 本机改了，停 2 秒再传上去
        bag = s.objectWillChange.debounce(for: .seconds(2), scheduler: RunLoop.main).sink { _ in
            Task { @MainActor in CloudSync.shared.push() }
        }
    }

    private func blob(_ s: Store, t: Double) -> Blob {
        Blob(t: t, workouts: s.workouts, weights: s.weights, food: s.food, restDays: s.restDays, doneDays: s.doneDays,
             cycle: s.cycle, liftCharts: s.liftCharts, follow: s.follow, nickname: s.nickname, plateCfg: s.plateCfg,
             deleted: Array(deleted).sorted())
    }
    private func hash(_ b: Blob) -> Int {
        var c = b; c.t = 0
        let enc = JSONEncoder(); enc.outputFormatting = .sortedKeys
        return (try? enc.encode(c))?.hashValue ?? 0
    }

    func push() {
        guard on, let s = store else { return }
        let t = Date().timeIntervalSince1970
        let b = blob(s, t: t)
        let h = hash(b)
        guard h != lastHash else { return }
        guard let raw = try? JSONEncoder().encode(b), let z = try? (raw as NSData).compressed(using: .zlib) as Data else { return }
        guard z.count < 1_000_000 else { note = "数据太多，iCloud 放不下了，先用导出备份"; return }
        kv.set(z, forKey: "xt.sync")
        kv.set(t, forKey: "xt.syncT")
        kv.synchronize()
        lastHash = h
        ud.set(t, forKey: "xt.syncLocalT")
        mark()
    }

    func pull() {
        guard on, let s = store, let z = kv.data(forKey: "xt.sync"),
              let raw = try? (z as NSData).decompressed(using: .zlib) as Data,
              let r = try? JSONDecoder().decode(Blob.self, from: raw) else { return }
        let localT = ud.double(forKey: "xt.syncLocalT")
        guard r.t > localT else { return }
        // 训练按编号合并（两边新加的都留下），删掉的去掉；其他按新的那份
        let gone = deleted.union(r.deleted)
        deleted = gone
        var byID = Dictionary(s.workouts.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for w in r.workouts { byID[w.id] = w }
        let merged = byID.values.filter { !gone.contains($0.id) }
        if Set(merged.map(\.self)) != Set(s.workouts) { s.workouts = merged.sorted { $0.date != $1.date ? $0.date < $1.date : $0.createdAt < $1.createdAt } }
        if r.weights != s.weights { s.weights = r.weights }
        if r.food != s.food { s.food = r.food }
        if r.restDays != s.restDays { s.restDays = r.restDays }
        if r.doneDays != s.doneDays { s.doneDays = r.doneDays }
        if r.liftCharts != s.liftCharts { s.liftCharts = r.liftCharts }
        if r.follow != s.follow { s.follow = r.follow }
        if !r.nickname.isEmpty && r.nickname != s.nickname { s.nickname = r.nickname }
        if r.plateCfg != s.plateCfg { s.plateCfg = r.plateCfg }
        if let a = try? JSONEncoder().encode(r.cycle), let b = try? JSONEncoder().encode(s.cycle), a != b { s.cycle = r.cycle }
        lastHash = hash(r)
        ud.set(r.t, forKey: "xt.syncLocalT")
        mark()
    }

    func syncNow() { kv.synchronize(); pull(); lastHash = 0; push(); mark() }

    private func mark() {
        lastSync = Date(); note = ""
        ud.set(lastSync!.timeIntervalSince1970, forKey: "xt.syncAt")
    }
}

struct CloudSection: View {
    @ObservedObject private var sync = CloudSync.shared
    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { sync.on }, set: { sync.on = $0 })) {
                Label("iCloud 同步", systemImage: "icloud")
            }
            if sync.on {
                HStack {
                    Text(sync.lastSync.map { "上次同步 " + $0.formatted(date: .abbreviated, time: .shortened) } ?? "还没同步过")
                        .font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                    Button("立即同步") { Haptic.tap(); sync.syncNow() }.font(.footnote.bold())
                }
                if !sync.note.isEmpty { Text(sync.note).font(.footnote).foregroundStyle(.orange) }
            }
        } footer: {
            Text("训练、体重、饮食和设置会同步到登录同一个 Apple ID 的 iPhone、iPad。体态照片、头像和手写笔迹只留在这台手机上。要在 iPhone 设置里打开 iCloud。")
        }
    }
}
