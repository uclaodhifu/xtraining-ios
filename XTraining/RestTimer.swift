import ActivityKit
import SwiftUI
import UserNotifications

// 组间休息计时：App 里显示倒计时，同时开锁屏/灵动岛实时活动，到点发通知（App 在后台也会响）
@MainActor
final class RestTimer: ObservableObject {
    static let shared = RestTimer()
    @Published private(set) var start: Date?
    @Published private(set) var end: Date?
    @AppStorage("restSec") var preset = 90
    private var activity: Activity<RestAttributes>?
    private var exercise = ""
    private var tick: Task<Void, Never>?

    var running: Bool { end.map { $0 > Date() } ?? false }

    func begin(_ sec: Int, exercise: String = "") {
        preset = sec
        self.exercise = exercise
        let now = Date()
        start = now; end = now.addingTimeInterval(TimeInterval(sec))
        schedule()
        Task { await live() }
        watch()
        Haptic.tap(.medium)
    }

    func add(_ sec: Int) {
        guard let e = end, let s = start else { return }
        let ne = max(Date().addingTimeInterval(1), e.addingTimeInterval(TimeInterval(sec)))
        end = ne; start = min(s, ne)
        schedule()
        Task { await live() }
        Haptic.tap()
    }

    func stop(keepAlert: Bool = false) {
        tick?.cancel()
        start = nil; end = nil
        // 手动停才取消提醒；时间到了自然结束时让通知照常响
        if !keepAlert { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["rest-end"]) }
        let a = activity; activity = nil
        Task { await a?.end(nil, dismissalPolicy: .immediate) }
        // 清掉上次没关掉的
        Task { for x in Activity<RestAttributes>.activities { await x.end(nil, dismissalPolicy: .immediate) } }
    }

    private func watch() {
        tick?.cancel()
        tick = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(0.5))
                guard let self, let e = self.end else { return }
                if Date() >= e {
                    Haptic.success()
                    self.stop(keepAlert: true)
                    return
                }
            }
        }
    }

    private func schedule() {
        guard let e = end else { return }
        let c = UNUserNotificationCenter.current()
        c.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        c.removePendingNotificationRequests(withIdentifiers: ["rest-end"])
        let n = UNMutableNotificationContent()
        n.title = "休息结束"
        n.body = exercise.isEmpty ? "开始下一组 💪" : "开始下一组：\(exercise) 💪"
        n.sound = .default
        n.interruptionLevel = .timeSensitive
        let t = UNTimeIntervalNotificationTrigger(timeInterval: max(1, e.timeIntervalSinceNow), repeats: false)
        c.add(UNNotificationRequest(identifier: "rest-end", content: n, trigger: t))
    }

    private func live() async {
        guard let s = start, let e = end, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let st = RestAttributes.ContentState(start: s, end: e, exercise: exercise)
        let content = ActivityContent(state: st, staleDate: e)
        if let a = activity {
            await a.update(content)
        } else {
            activity = try? Activity.request(attributes: RestAttributes(), content: content)
        }
    }
}

// 记录页底部的休息条
struct RestBar: View {
    @ObservedObject private var t = RestTimer.shared
    var exercise: String = ""
    private let presets = [60, 90, 120, 180]

    var body: some View {
        Group {
            if let s = t.start, let e = t.end, t.running {
                HStack(spacing: 12) {
                    ZStack {
                        ProgressView(timerInterval: s...e, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                            .progressViewStyle(.circular).tint(Brand.pink).scaleEffect(1.3)
                        Image(systemName: "timer").font(.caption.bold())
                    }
                    .frame(width: 40, height: 40)
                    Text(timerInterval: s...e, countsDown: true)
                        .font(.system(size: 30, weight: .heavy, design: .rounded)).monospacedDigit()
                    Spacer()
                    pill("−15") { t.add(-15) }
                    pill("+15") { t.add(15) }
                    Button { t.stop() } label: {
                        Image(systemName: "xmark").font(.footnote.bold()).frame(width: 34, height: 34)
                            .background(Color.primary.opacity(0.1), in: Circle())
                    }
                    .foregroundStyle(.primary)
                }
            } else {
                HStack(spacing: 8) {
                    Label("休息", systemImage: "timer").font(.subheadline.bold()).foregroundStyle(.secondary)
                    Spacer()
                    ForEach(presets, id: \.self) { p in
                        Button { t.begin(p, exercise: exercise) } label: {
                            Text(p % 60 == 0 ? "\(p / 60)分" : "\(p / 60):\(String(format: "%02d", p % 60))")
                                .font(.subheadline.bold()).padding(.horizontal, 12).padding(.vertical, 8)
                                .foregroundStyle(p == t.preset ? Brand.ink : Color.primary)
                                .background(p == t.preset ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.primary.opacity(0.08)), in: Capsule())
                        }
                        .buttonStyle(PressScale())
                    }
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .padding(.horizontal, 14).padding(.bottom, 6)
        .animation(.snappy, value: t.running)
    }

    private func pill(_ s: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Text(s).font(.footnote.bold()).padding(.horizontal, 10).frame(height: 34)
                .background(Color.primary.opacity(0.1), in: Capsule())
        }
        .foregroundStyle(.primary)
    }
}
