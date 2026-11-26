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
// 休息条：醒目的彩色卡片。没计时是橙粉渐变；计时中按剩余时间从绿变橙再变红，最后 10 秒会跳动
struct RestBar: View {
    @ObservedObject private var t = RestTimer.shared
    var exercise: String = ""
    private let presets = [60, 90, 120, 180]

    private static let idle = [Color(hex: 0xff7a18), Color(hex: 0xff3d7f)]
    private static func colors(_ left: Double, _ total: Double) -> [Color] {
        let f = total > 0 ? left / total : 0
        if left <= 10 { return [Color(hex: 0xff3b30), Color(hex: 0xd6246e)] }   // 快到了：红
        if f > 0.5 { return [Color(hex: 0x12b886), Color(hex: 0x0ca678).opacity(0.9)] } // 刚开始：绿
        return [Color(hex: 0xffa94d), Color(hex: 0xff6b00)]                       // 过半：橙
    }

    var body: some View {
        Group {
            if let s = t.start, let e = t.end, t.running {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let left = max(0, e.timeIntervalSince(ctx.date))
                    let total = e.timeIntervalSince(s)
                    let urgent = left <= 10
                    HStack(spacing: 12) {
                        ZStack {
                            ProgressView(timerInterval: s...e, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                                .progressViewStyle(.circular).tint(.white).scaleEffect(1.3)
                            Image(systemName: "timer").font(.caption.bold())
                        }
                        .frame(width: 40, height: 40)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(urgent ? "准备下一组" : "休息中").font(.caption2.bold()).opacity(0.85)
                            Text(timerInterval: s...e, countsDown: true)
                                .font(.system(size: 32, weight: .heavy, design: .rounded)).monospacedDigit()
                                .scaleEffect(urgent && Int(left) % 2 == 0 ? 1.08 : 1, anchor: .leading)
                                .animation(.spring(duration: 0.3), value: Int(left))
                        }
                        Spacer()
                        pill("−15") { t.add(-15) }
                        pill("+15") { t.add(15) }
                        Button { t.stop() } label: {
                            Image(systemName: "xmark").font(.footnote.bold()).frame(width: 34, height: 34)
                                .background(Color.white.opacity(0.22), in: Circle())
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(card(Self.colors(left, total)))
                    .animation(.easeInOut(duration: 0.8), value: left <= 10)
                    .animation(.easeInOut(duration: 0.8), value: total > 0 && left / total > 0.5)
                }
            } else {
                HStack(spacing: 8) {
                    Label("休息", systemImage: "timer").font(.subheadline.bold())
                    Spacer()
                    ForEach(presets, id: \.self) { p in
                        Button { t.begin(p, exercise: exercise) } label: {
                            Text(p % 60 == 0 ? "\(p / 60)分" : "\(p / 60):\(String(format: "%02d", p % 60))")
                                .font(.subheadline.bold()).padding(.horizontal, 12).padding(.vertical, 8)
                                .foregroundStyle(p == t.preset ? Color(hex: 0xff3d7f) : .white)
                                .background(p == t.preset ? Color.white : Color.white.opacity(0.22), in: Capsule())
                        }
                        .buttonStyle(PressScale())
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(card(Self.idle))
            }
        }
        .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
        .padding(.horizontal, 14).padding(.bottom, 6)
        .animation(.snappy, value: t.running)
    }

    private func card(_ c: [Color]) -> some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(LinearGradient(colors: c, startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.25)))
    }

    private func pill(_ s: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Text(s).font(.footnote.bold()).padding(.horizontal, 10).frame(height: 34)
                .background(Color.white.opacity(0.22), in: Capsule())
        }
        .foregroundStyle(.white)
    }
}
