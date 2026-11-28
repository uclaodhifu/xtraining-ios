import SwiftUI
import HealthKit
import CoreBluetooth
import UserNotifications

// MARK: - 心率数据（本机存一份：训练时的实时心率 + 每次组间休息的起止时间）

struct HRPoint: Codable, Hashable { var t: Double; var v: Int }            // t = 秒（1970 起）
struct RestMark: Codable, Hashable { var t: Double; var end: Double?; var ex: String }

enum HRLog {
    private static var dir: URL {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("hr", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    private static func file(_ day: String, _ kind: String) -> URL { dir.appendingPathComponent("\(kind)-\(day).json") }
    private static func read<T: Decodable>(_ u: URL) -> [T] {
        guard let d = try? Data(contentsOf: u) else { return [] }
        return (try? JSONDecoder().decode([T].self, from: d)) ?? []
    }
    private static func write<T: Encodable>(_ v: [T], _ u: URL) {
        if let d = try? JSONEncoder().encode(v) { try? d.write(to: u, options: .atomic) }
    }

    // 实时心率先攒在内存里，每 20 秒写一次文件
    private static var buffer: [HRPoint] = []
    private static var lastT: Double = 0
    private static var lastFlush = Date()
    static func add(_ v: Int, at d: Date = Date()) {
        let t = d.timeIntervalSince1970
        guard t - lastT >= 2 else { return }
        lastT = t
        buffer.append(HRPoint(t: t, v: v))
        if Date().timeIntervalSince(lastFlush) > 20 { flush() }
    }
    static func flush() {
        lastFlush = Date()
        guard !buffer.isEmpty else { return }
        let byDay = Dictionary(grouping: buffer) { Day.str(Date(timeIntervalSince1970: $0.t)) }
        buffer = []
        for (day, ps) in byDay {
            let u = file(day, "pts")
            var all: [HRPoint] = read(u)
            all += ps
            write(all, u)
        }
        cleanup()
    }
    static func points(_ day: String) -> [HRPoint] {
        var all: [HRPoint] = read(file(day, "pts"))
        all += buffer.filter { Day.str(Date(timeIntervalSince1970: $0.t)) == day }
        return all.sorted { $0.t < $1.t }
    }

    static func rests(_ day: String) -> [RestMark] { read(file(day, "rest")) }
    static func addRest(_ ex: String, at d: Date) {
        let day = Day.str(d)
        var r = rests(day)
        // 上一次休息没记结束（比如直接开始了新的休息）：按这次开始算结束
        if let i = r.indices.last, r[i].end == nil { r[i].end = d.timeIntervalSince1970 }
        r.append(RestMark(t: d.timeIntervalSince1970, end: nil, ex: ex))
        write(r, file(day, "rest"))
    }
    static func endRest(at d: Date) {
        let day = Day.str(d)
        var r = rests(day)
        guard let i = r.indices.last, r[i].end == nil else { return }
        r[i].end = d.timeIntervalSince1970
        write(r, file(day, "rest"))
    }
    // 有休息记录的日子（最近的在前）
    static func restDays() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.filter { $0.hasPrefix("rest-") }.map { String($0.dropFirst(5).dropLast(5)) }.sorted(by: >)
    }
    private static var cleaned = false
    private static func cleanup() {
        guard !cleaned else { return }
        cleaned = true
        let cut = Day.add(Day.today, -180)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        for n in names {
            let day = String(n.split(separator: "-", maxSplits: 1).last?.dropLast(5) ?? "")
            if day < cut { try? FileManager.default.removeItem(at: dir.appendingPathComponent(n)) }
        }
    }
}

// MARK: - 实时心率：耳机 / 手表（iPhone 上开始训练）、蓝牙手环（心率广播）、Apple 健康

@MainActor
final class HeartLive: ObservableObject {
    static let shared = HeartLive()
    @Published private(set) var bpm: Int?
    @Published private(set) var lastAt: Date?
    @Published private(set) var source = ""
    @Published var bleStatus = "未连接"
    @Published var bleName: String?
    @Published private(set) var sessionOn = false
    @Published private(set) var running = false
    var inEntry = false                                 // 记录页开着

    @AppStorage("xt.hrLine") var line = 115            // 恢复线：心率降到这里就提醒开下一组（自己设）
    @AppStorage("xt.hrAlert") var alertOn = true
    @AppStorage("xt.hrBLE") var bleOn = false
    @AppStorage("xt.hrSession2") var sessionWanted = true   // 默认打开：戴着 AirPods Pro 3 / 手表就直接有心率
    @Published var sessionStatus = "未开始"

    private let ble = HRBLE()
    private var session: AnyObject?                     // iOS 26 的 HRSession
    private var hkQuery: HKAnchoredObjectQuery?
    private var stopTask: Task<Void, Never>?
    private var started: Date?

    static var canSession: Bool { if #available(iOS 26.0, *) { return true } else { return false } }

    // 15 秒内收到的才算实时
    var fresh: Int? {
        guard let b = bpm, let l = lastAt, Date().timeIntervalSince(l) < 15 else { return nil }
        return b
    }

    init() {
        ble.onBPM = { v in MainActor.assumeIsolated { HeartLive.shared.receive(v, from: "手环") } }
        ble.onStatus = { s, name in MainActor.assumeIsolated { HeartLive.shared.bleStatus = s; if let name { HeartLive.shared.bleName = name } } }
    }

    func receive(_ v: Int, from src: String) {
        guard v > 30, v < 230 else { return }
        bpm = v; lastAt = Date(); source = src
        HRLog.add(v)
    }

    // 打开记录页时调用：把打开了的心率来源都连上
    // 每个打开了的来源都确保连上（重复调用没关系）
    func start() {
        stopTask?.cancel(); stopTask = nil
        if !running { started = Date() }
        running = true
        if bleOn { ble.start() }
        if sessionWanted { Task { _ = await Health.shared.ensureHeart(); startSession() } }
        startHealthWatch()
    }

    // 离开记录页 10 分钟还没回来，就停掉
    func stopLater() {
        stopTask?.cancel()
        stopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(600))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    func stop() {
        stopTask?.cancel(); stopTask = nil
        running = false
        ble.stop()
        stopSession()
        if let q = hkQuery { Health.shared.hk.stop(q); hkQuery = nil }
        HRLog.flush()
    }

    func setBLE(_ on: Bool) {
        bleOn = on
        if on {
            ble.start(); running = true
            if !inEntry { stopLater() }      // 在「我」页先连上看看，过一会儿自动断开
        } else { ble.stop(); bleStatus = "未连接" }
    }
    func forgetBLE() { ble.forget(); bleName = nil; if bleOn { ble.start() } }

    func setSession(_ on: Bool) {
        sessionWanted = on
        // 只在记录页里才真的开始训练；在「我」页打开只是记住，下次进记录页自动开始
        if on { Task { _ = await Health.shared.ensureHeart(); if inEntry { startSession(); running = true } else { sessionStatus = "进记录页时自动开始" } } } else { stopSession(); sessionStatus = "已关闭" }
    }

    private func startSession() {
        guard session == nil else { return }
        if #available(iOS 26.0, *) {
            let s = HRSession(store: Health.shared.hk)
            s.onBPM = { v in MainActor.assumeIsolated { HeartLive.shared.receive(v, from: "耳机/手表"); HeartLive.shared.sessionStatus = "正在读耳机/手表心率" } }
            s.onStatus = { t in MainActor.assumeIsolated { HeartLive.shared.sessionStatus = t; BugLog.add("心率训练：" + t) } }
            do {
                try s.start(); session = s; sessionOn = true
                sessionStatus = "已开始训练，等耳机心率…"
                // 25 秒还没收到心率：提示检查耳机
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(25))
                    guard let self, self.sessionOn, self.source != "耳机/手表" || self.fresh == nil else { return }
                    self.sessionStatus = "训练已开始，但还没收到心率。确认 AirPods 两只都戴好，并在「设置 → 你的 AirPods → 心率」打开"
                }
            } catch {
                sessionOn = false
                sessionStatus = "开始训练失败：\(error.localizedDescription)"
                BugLog.add("心率训练失败：\(error)")
            }
        } else {
            sessionStatus = "需要 iOS 26 以上"
        }
    }
    private func stopSession() {
        if #available(iOS 26.0, *), let s = session as? HRSession {
            // 练了 5 分钟以上就存成一次力量训练（Apple 健康里能看到时长、心率、消耗）
            s.stop(save: Date().timeIntervalSince(s.began) > 300)
        }
        session = nil; sessionOn = false
    }

    // Apple Watch 等写进 Apple 健康的心率：有新数据就拿最新的一条（手表同步会慢几秒到几分钟）
    private func startHealthWatch() {
        guard Health.shared.connected, hkQuery == nil else { return }
        let type = HKQuantityType(.heartRate)
        let pred = HKQuery.predicateForSamples(withStart: Date().addingTimeInterval(-120), end: nil)
        let handler: (HKAnchoredObjectQuery, [HKSample]?, [HKDeletedObject]?, HKQueryAnchor?, Error?) -> Void = { _, samples, _, _, _ in
            guard let q = (samples as? [HKQuantitySample])?.max(by: { $0.endDate < $1.endDate }) else { return }
            let v = Int(q.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())).rounded())
            let at = q.endDate
            let watch = q.sourceRevision.productType?.contains("Watch") == true
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let me = HeartLive.shared
                    // 只在比现有的新、而且是 2 分钟内的数据时才用（耳机/手环直连的更实时，优先）
                    guard Date().timeIntervalSince(at) < 120, (me.lastAt ?? .distantPast) < at else { return }
                    if me.source == "手环" || me.source == "耳机/手表", me.fresh != nil { return }
                    me.bpm = v; me.lastAt = at; me.source = watch ? "Apple Watch" : "Apple 健康"
                }
            }
        }
        let q = HKAnchoredObjectQuery(type: type, predicate: pred, anchor: nil, limit: HKObjectQueryNoLimit, resultsHandler: handler)
        q.updateHandler = handler
        Health.shared.hk.execute(q)
        hkQuery = q
    }
}

// MARK: - 蓝牙心率（标准心率服务 0x180D，小米/华为手环的「心率广播」、心率带都支持）

final class HRBLE: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private static let service = CBUUID(string: "180D")
    private static let measure = CBUUID(string: "2A37")
    private static let savedKey = "xt.hrBLEId"
    private var central: CBCentralManager?
    private var device: CBPeripheral?
    private var wanted = false
    var onBPM: (Int) -> Void = { _ in }
    var onStatus: (String, String?) -> Void = { _, _ in }

    func start() {
        if wanted, device != nil { return }
        wanted = true
        if central == nil { central = CBCentralManager(delegate: self, queue: nil) } else { go() }
    }
    func stop() {
        wanted = false
        central?.stopScan()
        if let d = device { central?.cancelPeripheralConnection(d) }
        device = nil
    }
    func forget() {
        UserDefaults.standard.removeObject(forKey: Self.savedKey)
        stop()
    }

    private func go() {
        guard wanted, let c = central, c.state == .poweredOn else { return }
        // 1. 以前连过的那个  2. 已经连在手机上的心率设备  3. 搜附近开着心率广播的
        if let s = UserDefaults.standard.string(forKey: Self.savedKey), let id = UUID(uuidString: s),
           let p = c.retrievePeripherals(withIdentifiers: [id]).first {
            connect(p); return
        }
        if let p = c.retrieveConnectedPeripherals(withServices: [Self.service]).first { connect(p); return }
        onStatus("正在搜索…", nil)
        c.scanForPeripherals(withServices: [Self.service])
    }
    private func connect(_ p: CBPeripheral) {
        device = p
        p.delegate = self
        onStatus("正在连接…", p.name)
        central?.connect(p)
    }

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        switch c.state {
        case .poweredOn: go()
        case .unauthorized: onStatus("没有蓝牙权限，去设置里打开", nil)
        case .poweredOff: onStatus("蓝牙关着", nil)
        default: break
        }
    }
    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        c.stopScan()
        connect(p)
    }
    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        UserDefaults.standard.set(p.identifier.uuidString, forKey: Self.savedKey)
        onStatus("已连接", p.name)
        p.discoverServices([Self.service])
    }
    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        onStatus("连不上，确认手环开着心率广播", p.name)
        if wanted { DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.go() } }
    }
    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        onStatus(wanted ? "断开了，正在重连…" : "未连接", p.name)
        if wanted { c.connect(p) }
    }
    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        for s in p.services ?? [] where s.uuid == Self.service { p.discoverCharacteristics([Self.measure], for: s) }
    }
    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        for ch in s.characteristics ?? [] where ch.uuid == Self.measure { p.setNotifyValue(true, for: ch) }
    }
    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard let d = ch.value, d.count >= 2 else { return }
        let b = [UInt8](d)
        let v = (b[0] & 0x01) == 0 ? Int(b[1]) : (d.count >= 3 ? Int(b[1]) | (Int(b[2]) << 8) : 0)
        if v > 0 { onBPM(v) }
    }
}

// MARK: - iOS 26：在 iPhone 上开始一次力量训练，读 AirPods Pro 3 / Powerbeats Pro 2 / 手表的实时心率

@available(iOS 26.0, *)
final class HRSession: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    let store: HKHealthStore
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    var began = Date()
    var onBPM: (Int) -> Void = { _ in }
    var onStatus: (String) -> Void = { _ in }
    init(store: HKHealthStore) { self.store = store }
    private func status(_ t: String) { DispatchQueue.main.async { self.onStatus(t) } }

    func start() throws {
        let c = HKWorkoutConfiguration()
        c.activityType = .traditionalStrengthTraining
        c.locationType = .indoor
        let s = try HKWorkoutSession(healthStore: store, configuration: c)
        let b = s.associatedWorkoutBuilder()
        let src = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: c)
        src.enableCollection(for: HKQuantityType(.heartRate), predicate: nil)   // 明确要心率
        b.dataSource = src
        s.delegate = self
        b.delegate = self
        session = s; builder = b
        began = Date()
        s.startActivity(with: began)
        b.beginCollection(withStart: began) { [weak self] ok, err in
            if !ok { self?.status("开始记录失败：\(err?.localizedDescription ?? "未知原因")") }
        }
    }

    func stop(save: Bool) {
        guard let s = session, let b = builder else { return }
        s.end()
        b.endCollection(withEnd: Date()) { _, _ in
            if save { b.finishWorkout { _, _ in } } else { b.discardWorkout() }
        }
        session = nil; builder = nil
    }

    func workoutBuilder(_ b: HKLiveWorkoutBuilder, didCollectDataOf types: Set<HKSampleType>) {
        let t = HKQuantityType(.heartRate)
        guard types.contains(t), let q = b.statistics(for: t)?.mostRecentQuantity() else { return }
        let v = Int(q.doubleValue(for: HKUnit.count().unitDivided(by: .minute())).rounded())
        DispatchQueue.main.async { self.onBPM(v) }
    }
    func workoutBuilderDidCollectEvent(_ b: HKLiveWorkoutBuilder) {}
    func workoutSession(_ s: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        if toState == .stopped || toState == .ended { status("训练已结束") }
    }
    func workoutSession(_ s: HKWorkoutSession, didFailWithError error: Error) {
        status("训练出错：\(error.localizedDescription)")
    }
}

// MARK: - 心率设置（休息条上点心形打开）

struct HeartSheet: View {
    @ObservedObject private var hr = HeartLive.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "heart.fill").foregroundStyle(.red)
                                .symbolEffect(.pulse, isActive: hr.fresh != nil)
                            Text(hr.fresh.map(String.init) ?? "--")
                                .font(.system(size: 48, weight: .heavy, design: .rounded)).monospacedDigit()
                                .contentTransition(.numericText())
                            Text("次/分").foregroundStyle(.secondary)
                            Spacer()
                            Text(hr.fresh != nil ? hr.source : "还没有实时心率").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .frame(height: 60)
                    }
                }
                Section {
                    if HeartLive.canSession {
                        Toggle(isOn: Binding(get: { hr.sessionWanted }, set: { hr.setSession($0) })) {
                            Label("耳机 / Apple Watch", systemImage: "airpodspro")
                        }
                        if hr.sessionWanted {
                            // 固定 3 行高：文字变了行高也不变（列表行高反复变会让排版死循环）
                            Text(hr.sessionStatus).font(.caption).foregroundStyle(.secondary)
                                .lineLimit(3, reservesSpace: true)
                        }
                    }
                    Toggle(isOn: Binding(get: { hr.bleOn }, set: { hr.setBLE($0) })) {
                        Label("手环 / 心率带（蓝牙）", systemImage: "dot.radiowaves.left.and.right")
                    }
                    if hr.bleOn {
                        HStack {
                            Text(hr.bleName ?? "手环").foregroundStyle(.secondary)
                            Spacer()
                            Text(hr.bleStatus).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        if hr.bleName != nil { Button("换一个手环") { hr.forgetBLE() } }
                    }
                } header: { Text("心率从哪来") } footer: {
                    Text((HeartLive.canSession ? "耳机 / Apple Watch：打开记录页时会在 iPhone 上开始一次「力量训练」，戴着 AirPods Pro 3 或 Powerbeats Pro 2 就能读实时心率（其他款 AirPods 测不了心率）。练完存进 Apple 健康。\n" : "")
                         + "手环：先在手环的 App 里打开「心率广播」（小米、华为、Polar、佳明等都有），这里会自动搜到。\nApple Watch 写进 Apple 健康的心率也会自动用上，但会慢一点。")
                }
                Section {
                    Stepper(value: $hr.line, in: 80...160, step: 5) {
                        HStack {
                            Text("降到")
                            Text("\(hr.line)").font(.title3.bold()).monospacedDigit().foregroundStyle(.green)
                            Text("次/分 就提醒")
                        }
                    }
                    Toggle("心率回到恢复线就提醒开下一组", isOn: $hr.alertOn)
                } header: { Text("恢复线") } footer: {
                    Text("组间休息时，倒计时到了或心率降到这里，先到先响。想多歇就设低一点，练得快就设高一点。")
                }
            }
            .navigationTitle("组间心率")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("好") { dismiss() } } }
        }
    }
}
