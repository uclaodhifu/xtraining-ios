import SwiftUI
import UIKit
import UniformTypeIdentifiers

// 问题录制：在「我 → 开始录制问题」点开始，照常操作把问题做一遍，点停止，再把记录发给开发者
// 只记输入过程（点了哪里、哪个页面、按了哪个数字、手写认成了什么、格子变化），不录屏幕，不记照片
// 没在录制时也悄悄留最近 300 条，录制时从「开始」那一刻算起
enum BugLog {
    private static let key = "xt.bugLog2"
    private static let maxLines = 300
    private static let maxRecLines = 3000
    private struct Line: Codable { var t: Double; var s: String }
    private static var lines: [Line] = UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([Line].self, from: $0) } ?? []
    private static var pending = false
    static var recording = false     // 录制中：多留一些，数步数
    static var steps = 0

    static func add(_ s: String) {
        let line = Line(t: Date().timeIntervalSince1970, s: s)
        let work = {
            lines.append(line)
            let cap = recording ? maxRecLines : maxLines
            if lines.count > cap { lines.removeFirst(lines.count - cap) }
            if recording { steps += 1 }
            // 攒一下再写，打字时不卡
            if !pending {
                pending = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    pending = false
                    if let d = try? JSONEncoder().encode(lines) { UserDefaults.standard.set(d, forKey: key) }
                }
            }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }
    static func trim(after start: Date) {
        lines.removeAll { $0.t < start.timeIntervalSince1970 - 0.01 }
    }

    static var header: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let v = info["CFBundleShortVersionString"] as? String ?? "?"
        let b = info["CFBundleVersion"] as? String ?? "?"
        let mode = ["数字手写", "全部手写", "键盘"][min(max(UserDefaults.standard.integer(forKey: InputMode.key), 0), 2)]
        let unit = UserDefaults.standard.string(forKey: WU.key) ?? "kg"
        let kb = UITextInputMode.activeInputModes.compactMap(\.primaryLanguage).joined(separator: ",")
        let now = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short)
        return """
        X Training \(v) (\(b)) · iOS \(UIDevice.current.systemVersion) · \(modelName)
        输入方式：\(mode) · 单位 \(unit) · 键盘 \(kb.isEmpty ? "?" : kb) · \(now)
        """
    }
    // 从 start 开始的记录，时间写成「开始后第几秒」
    static func report(note: String, from start: Date?) -> String {
        let n = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let t0 = start?.timeIntervalSince1970 ?? (lines.first?.t ?? 0)
        let body = lines.filter { $0.t >= t0 - 0.01 }.map { l in
            String(format: "%6.1fs  ", l.t - t0) + l.s
        }
        return header + "\n问题：" + (n.isEmpty ? "（没填）" : n) + "\n\n" + (body.isEmpty ? "（没录到操作）" : body.joined(separator: "\n"))
    }
    // 机型代号，比如 iPhone17,1
    static var modelName: String {
        var u = utsname(); uname(&u)
        return withUnsafeBytes(of: &u.machine) { p in String(decoding: p.prefix { $0 != 0 }, as: UTF8.self) }
    }
}

// 录制状态 + 顶上的红色「录制中」小条（放在单独的窗口里，弹出的页面也盖不住它）
@MainActor final class BugRecorder: ObservableObject {
    static let shared = BugRecorder()
    @Published private(set) var start: Date? = nil
    private(set) var lastStart: Date? = nil
    private var pill: UIWindow? = nil
    var isRecording: Bool { start != nil }

    func begin() {
        let now = Date()
        BugLog.trim(after: now)
        BugLog.steps = 0; BugLog.recording = true
        start = now; lastStart = now
        BugLog.add("▶ 开始录制")
        TapSpy.install()
        showPill()
        Haptic.tap()
    }
    func stop() {
        guard start != nil else { return }
        BugLog.add("■ 停止录制")
        start = nil; BugLog.recording = false
        pill?.isHidden = true; pill = nil
        Haptic.success()
        // 停下来就弹出「录好了」，写一句问题、发出去
        present(BugReportView(start: lastStart))
    }
    private func showPill() {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive })
                ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let w = UIWindow(windowScene: scene)
        let size = CGSize(width: 190, height: 44)
        let top = scene.windows.first(where: \.isKeyWindow)?.safeAreaInsets.top ?? 50
        w.frame = CGRect(x: (scene.screen.bounds.width - size.width) / 2, y: max(top - 6, 8), width: size.width, height: size.height)
        w.windowLevel = .alert + 1
        let host = UIHostingController(rootView: RecPill().environmentObject(self))
        host.view.backgroundColor = .clear
        w.rootViewController = host
        w.backgroundColor = .clear
        w.isHidden = false
        pill = w
    }
    func present<V: View>(_ v: V) {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        guard var top = scene?.windows.first(where: \.isKeyWindow)?.rootViewController ?? scene?.windows.first?.rootViewController else { return }
        while let p = top.presentedViewController, !p.isBeingDismissed { top = p }
        top.present(UIHostingController(rootView: v), animated: true)
    }
}

private struct RecPill: View {
    @EnvironmentObject var rec: BugRecorder
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(.white).frame(width: 8, height: 8)
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text("录制中 " + clock(ctx.date)).font(.footnote.bold()).monospacedDigit().foregroundStyle(.white)
            }
            Button { rec.stop() } label: {
                Text("停止").font(.footnote.bold()).foregroundStyle(.red)
                    .padding(.horizontal, 12).padding(.vertical, 5).background(Capsule().fill(.white))
            }
        }
        .padding(.leading, 14).padding(.trailing, 6).padding(.vertical, 6)
        .background(Capsule().fill(Color.red).shadow(color: .red.opacity(0.35), radius: 8, y: 3))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private func clock(_ now: Date) -> String {
        let s = Int(now.timeIntervalSince(rec.start ?? now))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// 录制时记下手指点在哪（只记位置和点到的是输入框、手写板还是按钮，不截图）
@MainActor enum TapSpy {
    private static var added = Set<ObjectIdentifier>()
    private final class Del: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith o: UIGestureRecognizer) -> Bool { true }
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive t: UITouch) -> Bool {
            if BugLog.recording, let w = g.view as? UIWindow {
                let p = t.location(in: w)
                let hit = w.hitTest(p, with: nil)
                BugLog.add("点 (\(Int(p.x)),\(Int(p.y))) \(kind(hit))")
            }
            return false     // 只看不拦，原来的点按照常生效
        }
        private func kind(_ v: UIView?) -> String {
            var x = v
            while let c = x {
                if c is UITextField { return "输入框" }
                if c is UITextView { return "文字框" }
                if String(describing: type(of: c)).contains("PKCanvas") { return "手写板" }
                if c is UIControl { return "按钮" }
                x = c.superview
            }
            return ""
        }
    }
    private static let del = Del()
    static func install() {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for w in scene.windows where w.windowLevel == .normal && !added.contains(ObjectIdentifier(w)) {
                let g = UITapGestureRecognizer()
                g.cancelsTouchesInView = false
                g.delaysTouchesBegan = false
                g.delaysTouchesEnded = false
                g.delegate = del
                w.addGestureRecognizer(g)
                added.insert(ObjectIdentifier(w))
            }
        }
    }
}

// 「我」页面里的入口
struct BugRecordRow: View {
    @ObservedObject private var rec = BugRecorder.shared
    var body: some View {
        Button { rec.isRecording ? rec.stop() : rec.begin() } label: {
            HStack(spacing: 12) {
                Image(systemName: rec.isRecording ? "stop.fill" : "record.circle").font(.subheadline.bold()).foregroundStyle(.white)
                    .frame(width: 30, height: 30).background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.red))
                VStack(alignment: .leading, spacing: 2) {
                    Text(rec.isRecording ? "停止录制" : "开始录制问题").foregroundStyle(Color.primary)
                    Text(rec.isRecording ? "停下来就能把记录发出去" : "点了以后照常操作，把出问题的步骤做一遍").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(Color(.tertiaryLabel))
            }
        }
    }
}

// 停止后：写一句问题，上传（系统分享，发微信 / 邮件给开发者）
struct BugReportView: View {
    let start: Date?
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var copied = false
    @State private var sending = false
    @State private var done: String? = nil
    @State private var failed = false
    private var text: String { BugLog.report(note: note, from: start) }
    var end = Date()
    private var seconds: Int { Int(end.timeIntervalSince(start ?? end)) }
    var body: some View {
        NavigationStack {
            Form {
                Section("出了什么问题？（可不填）") {
                    TextField("比如：次数打 12 只出来 1", text: $note, axis: .vertical).lineLimit(2...4)
                }
                Section {
                    Text(text).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.secondary)
                        .lineLimit(60).textSelection(.enabled)
                } header: { Text("录到的内容") } footer: {
                    Text("只有 App 版本、系统、机型和这次录到的操作步骤，不含训练记录、照片和个人信息。")
                }
                Section {
                    if let done {
                        Label("已上传，编号 \(done)。开发者能直接看到，不用再发。", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else if failed {
                        Text("没传上去（网络连不上服务器）。点下面用微信 / 邮件发给开发者也一样。").font(.footnote).foregroundStyle(.secondary)
                        ShareLink(item: BugFile(text: text), preview: SharePreview("X Training 问题记录")) {
                            Text("发微信 / 邮件给开发者").bold().foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .listRowBackground(Color.red)
                    } else {
                        Button {
                            sending = true
                            let t = text
                            Task {
                                let id = await BugUpload.send(t)
                                sending = false
                                if let id { done = id; Haptic.success() } else { failed = true }
                            }
                        } label: {
                            HStack {
                                if sending { ProgressView().tint(.white) }
                                Text(sending ? "上传中…" : "上传记录").bold()
                            }
                            .foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .disabled(sending)
                        .listRowBackground(Color.red)
                    }
                    Button {
                        UIPasteboard.general.string = text
                        Haptic.success(); copied = true
                    } label: { Text(copied ? "已复制" : "复制记录").frame(maxWidth: .infinity) }
                }
            }
            .navigationTitle("录好了 · \(seconds) 秒 · \(BugLog.steps) 步").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("关闭") { dismiss() } } }
        }
    }
}

// 上传到服务器（香港机房）；传不上（国内有时连不上）就退回系统分享
enum BugUpload {
    static let url = URL(string: "https://xt-bugs.vercel.app/api/upload")!
    static func send(_ text: String) async -> String? {
        var r = URLRequest(url: url, timeoutInterval: 15)
        r.httpMethod = "POST"
        r.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        r.setValue("xtraining", forHTTPHeaderField: "X-App")
        r.httpBody = Data(text.utf8)
        guard let (d, resp) = try? await URLSession.shared.data(for: r),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], j["ok"] as? Bool == true else { return nil }
        return j["id"] as? String ?? "OK"
    }
}

struct BugFile: Transferable {
    let text: String
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .plainText) { Data($0.text.utf8) }
            .suggestedFileName("XTraining-问题记录.txt")
    }
}
