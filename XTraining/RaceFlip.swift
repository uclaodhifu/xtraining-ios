import SwiftUI
import EventKit
import EventKitUI
import UserNotifications

// 赛事页新样式：最上面一张黑色翻页钟卡片（倒计时 月/周/天），下面是其余比赛的小卡片

struct RaceFlipCard: View {
    @EnvironmentObject var store: Store
    @Environment(\.openURL) private var openURL
    let e: Race
    var compact = false          // 下面列表里点开的：小一号，按钮一样有
    @State private var addCal = false

    private var left: Int { e.date.map { max(0, Day.between(Day.today, $0)) } ?? 0 }

    var body: some View {
        let followed = store.follow.contains(e.id)
        let n = left
        let m = n / 30, w = (n % 30) / 7, d = (n % 30) % 7
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(e.poster.2).font(.system(size: 11, weight: .heavy)).tracking(1)
                    .foregroundStyle(Color(hex: 0xff5b5b))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color(hex: 0xe03131).opacity(0.18)))
                Text(e.level + (followed ? " · 已追" : "")).font(.caption).foregroundStyle(.white.opacity(0.6))
                Spacer()
            }
            Text(e.name).font(.system(size: compact ? 16 : 19, weight: .heavy)).foregroundStyle(.white)
                .lineLimit(2).padding(.top, 8)
            Text(dateLine).font(.footnote).foregroundStyle(.white.opacity(0.7)).padding(.top, 4)
            if let dv = e.divs { Text(dv).font(.footnote).foregroundStyle(.white.opacity(0.85)).lineLimit(1).padding(.top, 4) }
            Text(e.timeText).font(.caption).foregroundStyle(.white.opacity(0.5)).padding(.top, 3)

            if n == 0 {
                Text(e.isPast ? "已结束" : "今天开赛")
                    .font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 18)
            } else {
                HStack(spacing: compact ? 10 : 14) {
                    FlipDigits(value: m, label: "月", small: compact)
                    FlipDigits(value: w, label: "周", small: compact)
                    FlipDigits(value: d, label: "天", small: compact)
                }
                .padding(.horizontal, compact ? 30 : 14).padding(.top, compact ? 10 : 14)
            }
            Group {
            Rectangle().fill(.white.opacity(0.08)).frame(height: 1).padding(.vertical, compact ? 10 : 12)
            HStack(spacing: 0) {
                action(followed ? "已追" : "追赛", followed ? "bell.fill" : "bell", on: followed) {
                    store.toggleFollow(e); Haptic.tap(.medium)
                }
                action("加日历", "calendar.badge.plus") { addCal = true }
                if let u = e.url, let url = URL(string: u) {
                    action("赛事主页", "link") { openURL(url) }
                }
                if !e.isWorld {
                    action("抖音观看", "play.rectangle.fill") { douyin() }
                }
            }
            }
        }
        .padding(compact ? 12 : 16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x29292b), Color(hex: 0x1a1a1c)], startPoint: .top, endPoint: .bottom))
        )
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.08)))
        .shadow(color: .black.opacity(0.25), radius: 14, y: 8)
        .environment(\.colorScheme, .dark)
        .sheet(isPresented: $addCal) { CalendarAdd(e: e).ignoresSafeArea() }
    }

    private var dateLine: String {
        func md(_ s: String) -> String { let p = s.split(separator: "-"); return p.count == 3 ? "\(p[1]).\(p[2])" : s }
        var s = e.date.map(md) ?? "日期待公布"
        if let end = e.end, end != e.date { s += " – " + md(end) }
        let place = [e.country, e.city].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        return place.isEmpty ? s : s + " · " + place
    }

    private func action(_ t: String, _ icon: String, on: Bool = false, _ go: @escaping () -> Void) -> some View {
        Button(action: go) {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background { if on { Circle().fill(Brand.gradient) } else { Circle().fill(.white.opacity(0.1)) } }
                Text(t).font(.system(size: 11)).foregroundStyle(.white.opacity(0.8))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PressScale())
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

// 翻页钟数字：中间一道缝，上半截亮一点，数字变化时翻动
struct FlipDigits: View {
    let value: Int
    let label: String
    var small = false
    var body: some View {
        VStack(spacing: 6) {
            Text(String(format: "%02d", min(value, 99)))
                .font(.system(size: small ? 24 : 36, weight: .black, design: .rounded)).monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(.numericText(countsDown: true))
                .animation(.snappy, value: value)
                .frame(maxWidth: .infinity, minHeight: small ? 38 : 56)
                .background {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: 0x0e0e10))
                        VStack(spacing: 0) {
                            LinearGradient(colors: [.white.opacity(0.07), .clear], startPoint: .top, endPoint: .bottom)
                            Color.clear
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .shadow(color: .black.opacity(0.5), radius: 6, y: 4)
                }
                .overlay { Rectangle().fill(.black).frame(height: 2) }
            Text(label).font(.system(size: 10, weight: .heavy)).tracking(3).foregroundStyle(.white.opacity(0.5))
        }
    }
}

// 其余比赛：一行小卡片，左边是还有几天
struct RaceMiniRow: View {
    @EnvironmentObject var store: Store
    let e: Race
    var body: some View {
        let n = e.date.map { Day.between(Day.today, $0) } ?? 0
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(e.date == nil ? "—" : n <= 0 ? "今天" : "\(n)").font(.system(size: n <= 0 ? 15 : 20, weight: .black, design: .rounded)).monospacedDigit()
                Text(n <= 0 ? "TODAY" : "DAYS").font(.system(size: 9, weight: .heavy)).tracking(1.5).foregroundStyle(.secondary)
            }
            .frame(width: 52, height: 48)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(e.name).font(.subheadline.bold()).lineLimit(1)
                    if store.follow.contains(e.id) { Image(systemName: "bell.fill").font(.caption2).foregroundStyle(Brand.pink) }
                }
                Text([e.date.map { d in let p = d.split(separator: "-"); return p.count == 3 ? "\(p[1]).\(p[2])" : d }, e.city].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(e.level).font(.system(size: 11, weight: .heavy)).foregroundStyle(Color(hex: 0xe03131))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color(hex: 0xe03131).opacity(0.12)))
                .lineLimit(1)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        .contentShape(Rectangle())
    }
}

// 加到系统日历：用系统自带的新建日程页面（不用申请日历权限）
struct CalendarAdd: UIViewControllerRepresentable {
    let e: Race
    @Environment(\.dismiss) private var dismiss
    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let vc = EKEventEditViewController()
        vc.eventStore = store
        let ev = EKEvent(eventStore: store)
        ev.title = e.name
        ev.location = [e.country, e.city].compactMap { $0 }.joined(separator: " ")
        let start = e.startAt ?? Date()
        ev.startDate = start
        if let end = e.end, end != e.date {
            ev.endDate = (Calendar.current.date(byAdding: .day, value: 1, to: Day.date(end)) ?? start)
            ev.isAllDay = true
        } else {
            ev.endDate = start.addingTimeInterval(8 * 3600)
        }
        ev.notes = [e.divs, e.desc].compactMap { $0 }.joined(separator: "\n")
        if let u = e.url { ev.url = URL(string: u) }
        ev.addAlarm(EKAlarm(relativeOffset: -86400))
        vc.event = ev
        vc.editViewDelegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: EKEventEditViewController, context: Context) {}
    func makeCoordinator() -> Coord { Coord(dismiss) }
    final class Coord: NSObject, EKEventEditViewDelegate {
        let dismiss: DismissAction
        init(_ d: DismissAction) { dismiss = d }
        func eventEditViewController(_ c: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) { dismiss() }
    }
}

// 下面列表里点开的：之前的白卡片 + 赛事方配色海报，倒计时放在海报上，按钮和之前一样
struct RaceOpenCard: View {
    @EnvironmentObject var store: Store
    @Environment(\.openURL) private var openURL
    let e: Race
    @State private var addCal = false
    @State private var denied = false

    private var left: Int { e.date.map { max(0, Day.between(Day.today, $0)) } ?? 0 }

    var body: some View {
        let followed = store.follow.contains(e.id)
        let p = e.poster
        let n = left
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [p.0, p.1], startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(p.2).font(.system(size: 76, weight: .black)).italic()
                    .foregroundStyle(.white.opacity(0.12)).lineLimit(1).minimumScaleFactor(0.3)
                    .offset(x: -4, y: -10)
                VStack(alignment: .leading, spacing: 0) {
                    Text(p.2 + " · " + e.level).font(.system(size: 11, weight: .heavy)).tracking(1).foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 5).fill(.black.opacity(0.2)))
                    Spacer(minLength: 8)
                    if n == 0 {
                        Text(e.isPast ? "已结束" : "今天开赛").font(.system(size: 28, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white).frame(maxWidth: .infinity)
                    } else {
                        HStack(spacing: 10) {
                            digit(n / 30, "月"); digit((n % 30) / 7, "周"); digit((n % 30) % 7, "天")
                        }
                    }
                }
                .padding(12)
            }
            .frame(height: 124)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(e.name).font(.headline).lineLimit(2)
                Text([e.city, e.level].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                if let d = e.divs { Text(d).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                Text(e.timeText).font(.caption2.bold()).foregroundStyle(Brand.pink)
            }
            .padding(.horizontal, 4)

            HStack(spacing: 8) {
                Button {
                    store.toggleFollow(e); Haptic.tap(.medium)
                    if !followed { checkPermission() }
                } label: {
                    Label(followed ? "已追" : "追赛", systemImage: followed ? "bell.fill" : "bell")
                        .symbolEffect(.bounce, value: followed)
                        .font(.subheadline.bold()).frame(maxWidth: .infinity, minHeight: 36)
                        .foregroundStyle(followed ? Brand.ink : Color.primary)
                        .background { if followed { Capsule().fill(Brand.gradient) } else { Capsule().fill(Color(.tertiarySystemFill)) } }
                }
                .buttonStyle(.plain)
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
            HStack(spacing: 8) {
                small("加日历", "calendar.badge.plus") { addCal = true }
                if !e.isWorld, let u = e.url, let url = URL(string: u) {
                    small("赛事主页", "link") { openURL(url) }
                }
            }
        }
        .card()
        .sheet(isPresented: $addCal) { CalendarAdd(e: e).ignoresSafeArea() }
        .alert("通知被关掉了", isPresented: $denied) {
            Button("去设置") { if let u = URL(string: UIApplication.openSettingsURLString) { openURL(u) } }
            Button("先不用", role: .cancel) {}
        } message: { Text("打开 X Training 的通知，追的比赛才能按时提醒你。") }
    }

    private func digit(_ v: Int, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(String(format: "%02d", min(v, 99)))
                .font(.system(size: 26, weight: .black, design: .rounded)).monospacedDigit().foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.black.opacity(0.28)))
                .overlay { Rectangle().fill(.black.opacity(0.35)).frame(height: 2) }
            Text(label).font(.system(size: 10, weight: .heavy)).tracking(3).foregroundStyle(.white.opacity(0.85))
        }
    }

    private func small(_ t: String, _ icon: String, _ go: @escaping () -> Void) -> some View {
        Button(action: go) {
            Label(t, systemImage: icon).font(.caption.bold()).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(Capsule().fill(Color(.quaternarySystemFill)))
        }
        .buttonStyle(.plain)
    }

    private func checkPermission() {
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            let s = await UNUserNotificationCenter.current().notificationSettings()
            if s.authorizationStatus == .denied { denied = true }
        }
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
