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
// 休息条：醒目的绿色卡片；最后 10 秒变红并跳动
struct RestBar: View {
    @ObservedObject private var t = RestTimer.shared
    var exercise: String = ""
    private let presets = [60, 90, 120, 180, 300]
    @Namespace private var ns
    @State private var tapped: Int? = nil       // 刚点的那个时长（放大弹一下）
    @State private var wave: CGFloat = -1       // 开始计时时扫过卡片的一道光
    @State private var ring = false             // 计时圈外扩散的波纹

    private static let green = [Color(hex: 0x34548a), Color(hex: 0x1d3a6e)]   // 墨蓝，和训练本的钢笔色一致
    private static let idle = green
    private static func colors(_ left: Double, _ total: Double) -> [Color] {
        let f = total > 0 ? left / total : 0
        if left <= 10 { return [Color(hex: 0xff3b30), Color(hex: 0xd6246e)] }   // 快到了：红
        _ = f
        return green                                                              // 其余时间：绿
    }

    @State private var chipsW: CGFloat = 0      // 时长按钮那一排有多宽（滑动选择用）
    @State private var keyboard = false         // 键盘弹出来时先把计时条收起来，免得和键盘叠在一起

    var body: some View {
        ZStack {
            if !keyboard { bar.transition(.move(edge: .bottom).combined(with: .opacity)) } else { Color.clear.frame(height: 0) }
        }
        .animation(.easeOut(duration: 0.2), value: keyboard)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboard = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboard = false }
    }

    private var bar: some View {
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
                                .symbolEffect(.bounce, value: ring)
                            Circle().stroke(.white.opacity(ring ? 0 : 0.8), lineWidth: 3)
                                .scaleEffect(ring ? 2.4 : 1)
                        }
                        .frame(width: 40, height: 40)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(urgent ? "准备下一组" : "休息中").font(.caption2.bold()).opacity(0.85)
                            Text(timerInterval: s...e, countsDown: true)
                                .font(.system(size: 32, weight: .heavy, design: .rounded)).monospacedDigit()
                                .matchedGeometryEffect(id: "time", in: ns)
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
                    .overlay {
                        // 一道光从左扫到右
                        GeometryReader { g in
                            LinearGradient(colors: [.clear, .white.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing)
                                .frame(width: g.size.width * 0.35)
                                .rotationEffect(.degrees(18))
                                .offset(x: wave * g.size.width * 1.2)
                        }
                        .allowsHitTesting(false)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .blendMode(.plusLighter)
                    }
                    .animation(.easeInOut(duration: 0.8), value: left <= 10)
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "timer").font(.subheadline.bold())
                    // 手指在这排上左右滑：只换选中的时长，不开始；点一下才开始计时
                    HStack(spacing: 6) {
                        ForEach(presets, id: \.self) { p in
                            Button { start(p) } label: {
                                Text(p % 60 == 0 ? "\(p / 60)分" : "\(p / 60):\(String(format: "%02d", p % 60))")
                                    .font(.subheadline.bold()).lineLimit(1).minimumScaleFactor(0.8)
                                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                                    .foregroundStyle(p == t.preset ? Color(hex: 0x1d3a6e) : .white)
                                    .background(p == t.preset ? Color.white : Color.white.opacity(0.22), in: Capsule())
                                    .matchedGeometryEffect(id: p == t.preset ? "time" : "chip\(p)", in: ns)
                                    .scaleEffect(tapped == p ? 1.3 : 1)
                                    .rotationEffect(.degrees(tapped == p ? -6 : 0))
                            }
                            .buttonStyle(PressScale())
                        }
                    }
                    .background(GeometryReader { g in Color.clear.onAppear { chipsW = g.size.width }.onChange(of: g.size.width) { _, w in chipsW = w } })
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 6)
                            .onChanged { v in
                                guard chipsW > 0 else { return }
                                let i = min(presets.count - 1, max(0, Int(v.location.x / (chipsW / CGFloat(presets.count)))))
                                let p = presets[i]
                                if p != t.preset {
                                    withAnimation(.snappy(duration: 0.18)) { t.preset = p }
                                    UISelectionFeedbackGenerator().selectionChanged()
                                }
                            }
                    )
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

    private func start(_ p: Int) {
        Haptic.tap(.medium)
        withAnimation(.spring(response: 0.25, dampingFraction: 0.45)) { t.preset = p; tapped = p }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            wave = -0.5; ring = false
            withAnimation(.spring(response: 0.55, dampingFraction: 0.75)) {
                t.begin(p, exercise: exercise)
                tapped = nil
            }
            withAnimation(.easeOut(duration: 0.9).delay(0.25)) { wave = 1.1 }
            withAnimation(.easeOut(duration: 1.1).delay(0.3)) { ring = true }
        }
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
