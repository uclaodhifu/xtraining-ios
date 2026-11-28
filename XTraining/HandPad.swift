import SwiftUI
import PencilKit
import Vision

// 输入方式（我 → 输入方式）：0 只有重量/次数手写（默认）  1 全部手写，格子里留原样笔迹  2 都用系统键盘
enum InputMode { static let key = "xt.inputMode" }

// 正在手写板上改识别结果（这时弹出的键盘不要把手写板关掉）
@MainActor enum PadFix { static var editing = false }

struct WriteCell: Equatable { var ex: UUID; var set: UUID; var weight: Bool }

// 笔迹存在本机文件里（每格一个小文件），训练数据里只记编号
// PencilKit 在夜间模式会自动把颜色反过来（黑变白），画成图时固定按白天模式画，颜色才是我们指定的
func lightTrait<T>(_ f: () -> T) -> T {
    var out: T!
    UITraitCollection(userInterfaceStyle: .light).performAsCurrent { out = f() }
    return out
}
enum InkColor {
    static let day = UIColor(red: 0.114, green: 0.227, blue: 0.431, alpha: 1)
    static let night = UIColor(red: 0.72, green: 0.83, blue: 1, alpha: 1)
}

enum InkStore {
    private static let dir: URL = {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ink", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()
    private static let cache = NSCache<NSString, UIImage>()
    static func save(_ d: PKDrawing, id: String) {
        try? d.dataRepresentation().write(to: dir.appendingPathComponent(id))
        known[id] = true
        cache.removeObject(forKey: "\(id)-true" as NSString); cache.removeObject(forKey: "\(id)-false" as NSString)   // 只清这一格，别的笔迹图不用重画
    }
    // 有没有这张笔迹（记在内存里，滑动表格时不用一遍遍查文件，免得掉帧）
    private static var known: [String: Bool] = [:]
    static func has(_ id: String?) -> String? {
        guard let id else { return nil }
        if let k = known[id] { return k ? id : nil }
        let ok = FileManager.default.fileExists(atPath: dir.appendingPathComponent(id).path)
        known[id] = ok
        return ok ? id : nil
    }
    // 备份用：原始笔迹数据读出来 / 写回去
    static func raw(_ id: String) -> Data? { try? Data(contentsOf: dir.appendingPathComponent(id)) }
    static func restore(_ id: String, _ data: Data) {
        guard !id.isEmpty, !id.contains("/"), (try? PKDrawing(data: data)) != nil else { return }
        let url = dir.appendingPathComponent(id)
        if FileManager.default.fileExists(atPath: url.path) { return }
        try? data.write(to: url)
        known[id] = true
    }
    static func load(_ id: String) -> PKDrawing? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent(id)) else { return nil }
        return try? PKDrawing(data: data)
    }
    // 画成图（按当前白天/夜间重新上墨蓝色）
    static func cached(_ id: String, dark: Bool) -> UIImage? { cache.object(forKey: "\(id)-\(dark)" as NSString) }
    static func image(_ id: String, dark: Bool) -> UIImage? {
        let k = "\(id)-\(dark)" as NSString
        if let i = cache.object(forKey: k) { return i }
        guard let d = load(id), !d.strokes.isEmpty else { return nil }
        let color = dark ? InkColor.night : InkColor.day
        let re = PKDrawing(strokes: d.strokes.map { var s = $0; s.ink = PKInk(.pen, color: color); return s })
        let img = lightTrait { re.image(from: re.bounds.insetBy(dx: -6, dy: -6), scale: 2) }
        cache.setObject(img, forKey: k)
        return img
    }
}

// 格子里显示原样笔迹
// 画好的图有缓存就直接用；第一次要画的先占位，稍后再画，滑动时不卡
struct InkView: View {
    let id: String
    var height: CGFloat = 30
    @Environment(\.colorScheme) private var scheme
    @State private var img: UIImage? = nil
    var body: some View {
        let dark = scheme == .dark
        let ready = img ?? InkStore.cached(id, dark: dark)
        Group {
            if let ready { Image(uiImage: ready).resizable().scaledToFit().frame(maxHeight: height) }
            else { Color.clear.frame(width: height, height: height) }
        }
        .task(id: "\(id)-\(dark)") {
            if InkStore.cached(id, dark: dark) != nil { img = nil; return }
            await Task.yield()
            img = InkStore.image(id, dark: dark)
        }
    }
}

// 手写板：手指写，停一下自动识别。数字模式只留数字和小数点；文字模式认中文（写动作名）
struct HandPad: View {
    @Binding var value: String
    let title: String
    var textMode = false
    var nextLabel = "下一格  →"
    var plus = false          // 次数格：多一个「＋」键，写 10+5（组内暂停）
    var padHeight: CGFloat = 230   // 横屏时矮一点
    var onInk: ((PKDrawing) -> Void)? = nil
    var onNext: () -> Void
    var onClose: () -> Void

    @State private var canvas = PKCanvasView()
    @State private var dotAt: Int? = nil     // 点「.」时前面已经写了几位数字
    @State private var plusAt: [Int] = []    // 点「＋」时前面已经写了几位数字
    @State private var job: DispatchWorkItem? = nil
    @State private var empty = true
    @State private var miss = false      // 刚才没认出来
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.caption.bold()).foregroundStyle(Paper.pencil).lineLimit(1)
                Spacer()
                if textMode {
                    Text(value.isEmpty ? "—" : value).font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Paper.ink).lineLimit(1)
                } else {
                    // 认出来的数字：用来算涨跌和进步；认错了点一下直接改
                    HStack(spacing: 4) {
                        Text("认成").font(.caption2).foregroundStyle(Paper.pencil)
                        // UIKit 输入框：键盘弹出之前就标记「正在改」，手写板不会被键盘关掉
                        NumField(value: $value, decimal: true, label: "认成(\(title))", placeholder: "?",
                                 font: .monospacedDigitSystemFont(ofSize: 18, weight: .bold),
                                 color: value.isEmpty ? UIColor(Tone.down) : UIColor(Paper.ink), allowPlus: plus) { f in
                            if f { job?.cancel(); job = nil }   // 正在改：后台识别别再把改好的数字盖掉
                            PadFix.editing = f
                            // 改完了：把这次的笔迹按改对的数字记下来，下次认得更准
                            if !f, !value.isEmpty, !canvas.drawing.strokes.isEmpty { DigitReader.learn(canvas.drawing, answer: value) }
                        }
                            .frame(width: 64, height: 30)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Paper.ink.opacity(0.07)))
                    }
                }
                Button { onClose() } label: {
                    Image(systemName: "chevron.down").font(.footnote.bold()).foregroundStyle(Paper.pencil)
                        .frame(width: 30, height: 30).background(Circle().fill(Paper.ink.opacity(0.07)))
                }
            }
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(scheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.75))
                Rectangle().fill(Paper.rule).frame(height: 1.5).offset(y: 60)
                if empty {
                    Text(textMode ? "在这里写动作名，比如 杠铃卧推" : "在这里用手指写数字")
                        .font(.subheadline).foregroundStyle(Paper.pencil.opacity(0.7)).allowsHitTesting(false)
                }
                InkCanvas(canvas: canvas, dark: scheme == .dark) {
                    empty = canvas.drawing.strokes.isEmpty
                    if !textMode && !empty { onInk?(canvas.drawing) }   // 写一笔就直接贴到格子里，不等识别
                    scheduleRecognize()
                }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .frame(height: padHeight)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Paper.ink.opacity(0.15)))
            HStack(spacing: 8) {
                key("清除", wide: false) { clear() }
                if plus { key("＋", wide: false, tint: .orange) { addPlus() } }
                key(nextLabel, wide: true, strong: true) { flush(); onNext() }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Paper.bg).shadow(color: .black.opacity(0.18), radius: 12, y: -2))
        .padding(.horizontal, 10).padding(.bottom, 6)
        .onAppear { reset() }
        .onChange(of: title) { _, t in BugLog.add("手写板换到 \(t)"); reset() }
    }

    private func key(_ t: String, wide: Bool, strong: Bool = false, tint: Color? = nil, _ a: @escaping () -> Void) -> some View {
        Button { Haptic.tap(); a() } label: {
            Text(t).font(.headline).frame(maxWidth: wide ? .infinity : 64, minHeight: 44)
                .foregroundStyle(strong ? Color.white : (tint ?? Paper.ink))
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(strong ? Paper.ink : (tint ?? Paper.ink).opacity(tint == nil ? 0.08 : 0.15)))
        }
        .buttonStyle(PressScale())
    }

    private func reset() { job?.cancel(); job = nil; canvas.drawing = PKDrawing(); dotAt = nil; plusAt = []; empty = true; miss = false }
    // 组内暂停：先写的 10 后面加个 +，接着写 5（笔迹照常写在后面）
    private func addPlus() {
        flush()
        let k = value.filter(\.isNumber).count
        guard k > 0, !plusAt.contains(k) else { return }
        plusAt.append(k)
        if !value.hasSuffix("+") { value += "+" }
        BugLog.add("手写 次数 点了 ＋（组内暂停），现在是 \"\(value)\"")
    }
    private func clear() { BugLog.add("手写 \(title) 点了清除（原来 \"\(value)\"）"); reset(); value = "" }
    // 小数点没写/认不出来：记住前面几位，之后认出来的数字在这里插一个点
    private func dot() {
        flush()
        dotAt = value.filter(\.isNumber).count
        if !value.contains(".") { value += "." }
    }
    private func apply(_ r: String) {
        if textMode { value = r; return }
        var v = r
        if let k = dotAt, !v.contains("."), k <= v.count { v.insert(".", at: v.index(v.startIndex, offsetBy: k)) }
        if !plusAt.isEmpty {
            // 按数字个数找位置插 +（「10」后面点了＋，再写「5」→ 10+5）
            let digits = v.filter { $0.isNumber || $0 == "." || $0 == "+" }
            var out = "", n = 0
            for c in digits {
                if c == "+" { if !out.isEmpty && !out.hasSuffix("+") { out.append("+") }; continue }
                if c.isNumber, plusAt.contains(n), n > 0, !out.hasSuffix("+") { out.append("+") }
                out.append(c); if c.isNumber { n += 1 }
            }
            if plusAt.contains(n) && n > 0 && !out.hasSuffix("+") { out.append("+") }
            v = out
        }
        value = v
    }
    private func flush() {
        guard job != nil, !canvas.drawing.strokes.isEmpty else { return }
        job?.cancel(); job = nil
        let d = canvas.drawing
        if plus, !textMode, HandPad.splitPlus(d) != nil {
            let r = HandPad.readNumber(d, text: false, plus: true)
            BugLog.add("手写 \(title) 点下一格前认出「+」→ \"\(r)\"")
            if !r.isEmpty { apply(r) }
            onInk?(d)
            return
        }
        let v = HandPad.read(d, text: textMode)
        var r = v
        if !textMode {
            let m = DigitReader.read(d)
            r = DigitReader.fuse(v, m)
            BugLog.add("手写 \(title) 点下一格前认成 \"\(r)\"（系统 \"\(v)\" / 笔画 \"\(m.text)\" \(m.digits)个字，\(d.strokes.count)笔）")
        }
        if !r.isEmpty { apply(r) }
        onInk?(d)
    }
    private func scheduleRecognize() {
        job?.cancel()
        let tm = textMode
        guard !canvas.drawing.strokes.isEmpty else { return }
        var w: DispatchWorkItem!
        let usePlus = plus
        w = DispatchWorkItem {
            let d = canvas.drawing
            // 次数格里手写了「+」（组内暂停）：+ 左右两边分开认，再拼成 10+5
            if usePlus, !tm, let (l, rt) = HandPad.splitPlus(d) {
                let pl = HandPad.page(l), pr = rt.strokes.isEmpty ? nil : HandPad.page(rt)
                let ml = DigitReader.read(l), mr: (text: String, digits: Int)? = rt.strokes.isEmpty ? nil : DigitReader.read(rt)
                DispatchQueue.global(qos: .userInitiated).async {
                    let a = pl.map { DigitReader.fuse(HandPad.recognize($0, text: false), ml) } ?? ""
                    var b = pr.map { HandPad.recognize($0, text: false) } ?? ""
                    if let mr { b = DigitReader.fuse(b, mr) }
                    let r = a.isEmpty ? "" : a + "+" + b
                    DispatchQueue.main.async {
                        guard let me = w, job === me, !me.isCancelled else { return }
                        job = nil
                        BugLog.add("手写 \(title) 认出「+」，左边 \"\(a)\" 右边 \"\(b)\" → \"\(r)\"")
                        if !r.isEmpty { apply(r) }
                    }
                }
                return
            }
            guard let cg = HandPad.page(d) else { return }
            let mine: (text: String, digits: Int)? = tm ? nil : DigitReader.read(d)
            DispatchQueue.global(qos: .userInitiated).async {
                let v = HandPad.recognize(cg, text: tm)
                var r = v
                if let mine { r = DigitReader.fuse(v, mine) }
                let strokes = d.strokes.count
                DispatchQueue.main.async {
                    guard let me = w, job === me, !me.isCancelled else { return }   // 这期间又写了一笔或者点了清除/改数字：这次结果作废
                    job = nil
                    if !tm { BugLog.add("手写 \(title) 认成 \"\(r)\"（系统 \"\(v)\" / 笔画 \"\(mine?.text ?? "")\" \(mine?.digits ?? 0)个字，\(strokes)笔）→ 格子 \"\(r.isEmpty ? value : r)\"") }
                    // 后台悄悄认一下数字，只用来算涨跌和统计，界面上不显示
                    if !r.isEmpty { apply(r) }
                    if textMode { onInk?(d) }
                }
            }
        }
        job = w
        DispatchQueue.main.asyncAfter(deadline: .now() + (textMode ? 0.9 : 0.6), execute: w)
    }

    // 同步认一遍（点「下一格」时用）：有手写的「+」就左右分开认
    static func readNumber(_ d: PKDrawing, text: Bool, plus: Bool) -> String {
        func one(_ x: PKDrawing) -> String {
            guard !x.strokes.isEmpty else { return "" }
            var r = read(x, text: text)
            if !text { r = DigitReader.fuse(r, DigitReader.read(x)) }
            return r
        }
        if plus, !text, let (l, rt) = splitPlus(d) {
            let a = one(l)
            return a.isEmpty ? "" : a + "+" + one(rt)
        }
        return one(d)
    }

    // 找手写的「+」：一笔横、一笔竖，长短差不多，在中间互相交叉。
    // 找到了就把这两笔去掉，返回 + 左边和右边的笔画
    static func splitPlus(_ d: PKDrawing) -> (PKDrawing, PKDrawing)? {
        let ss = d.strokes
        guard ss.count >= 3 else { return nil }   // + 前面至少要有一个数字
        let b = ss.map { $0.renderBounds }
        let digitH = b.map(\.height).max() ?? 0
        for i in ss.indices {
            let h = b[i]
            guard h.width > max(h.height * 2.2, 8) else { continue }        // 横
            for j in ss.indices where j != i {
                let v = b[j]
                guard v.height > max(v.width * 2.2, 8) else { continue }    // 竖
                let ratio = h.width / v.height
                guard ratio > 0.45, ratio < 2.2 else { continue }           // 长短差不多
                guard v.height < digitH * 0.95 else { continue }            // + 比数字矮
                // 交叉在中间：横线的高度在竖线中段，竖线的位置在横线中段
                let hy = h.midY, vx = v.midX
                guard hy > v.minY + v.height * 0.2, hy < v.maxY - v.height * 0.2,
                      vx > h.minX + h.width * 0.2, vx < h.maxX - h.width * 0.2 else { continue }
                let cx = (h.midX + v.midX) / 2
                let rest = ss.indices.filter { $0 != i && $0 != j }
                let left = rest.filter { b[$0].midX < cx }.map { ss[$0] }
                let right = rest.filter { b[$0].midX >= cx }.map { ss[$0] }
                guard !left.isEmpty else { continue }
                return (PKDrawing(strokes: left), PKDrawing(strokes: right))
            }
        }
        return nil
    }

    // 笔画画成白底黑字的图，交给 iPhone 自带的文字识别（不联网）
    // 手写的短数字系统有时认不出，所以：放在一张宽一点的白纸中间、笔画加粗，认不出再换几种设置多试几次
    static func read(_ drawing: PKDrawing, text: Bool) -> String {
        guard let cg = page(drawing) else { return "" }
        return recognize(cg, text: text)
    }
    // 画成图这一步放在主线程做（PencilKit 在后台线程画可能是空白）
    static func page(_ drawing: PKDrawing) -> CGImage? {
        let d = PKDrawing(strokes: drawing.strokes.map { var s = $0; s.ink = PKInk(.pen, color: .black); return s })
        let b = d.bounds
        guard !b.isEmpty else { return nil }
        let ink = lightTrait { d.image(from: b.insetBy(dx: -8, dy: -8), scale: 2) }
        // 统一缩放到字高约 120 像素，左右留足白边
        let k = 120 / max(ink.size.height, 1)
        let w = ink.size.width * k, h = ink.size.height * k
        let page = CGSize(width: max(w + 160, h * 4), height: h + 120)
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: page, format: fmt).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: page))
            ink.draw(in: CGRect(x: (page.width - w) / 2, y: (page.height - h) / 2, width: w, height: h))
        }
        return img.cgImage
    }
    static func recognize(_ cg: CGImage, text: Bool) -> String {
        let tries: [([String], Bool, VNRequestTextRecognitionLevel)] = text
            ? [(["zh-Hans", "en-US"], true, .accurate), (["zh-Hans"], false, .accurate)]
            : [(["en-US"], false, .accurate), (["zh-Hans", "en-US"], false, .accurate), (["en-US"], true, .accurate), (["en-US"], false, .fast)]
        for (langs, correct, level) in tries {
            let req = VNRecognizeTextRequest()
            req.recognitionLevel = level
            req.usesLanguageCorrection = correct
            req.recognitionLanguages = langs
            req.minimumTextHeight = 0.05
            try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([req])
            let obs = (req.results ?? []).sorted { $0.boundingBox.minX < $1.boundingBox.minX }
            if text {
                let r = obs.compactMap { $0.topCandidates(1).first?.string }.joined().trimmingCharacters(in: .whitespaces)
                if !r.isEmpty { return r }
                continue
            }
            let raw = obs.compactMap { o in o.topCandidates(5).first { fix($0.string).contains(where: \.isNumber) } ?? o.topCandidates(1).first }
                .map { fix($0.string) }.joined()
            var seenDot = false
            let r = String(raw.filter { c in
                if c == "." { if seenDot { return false }; seenDot = true; return true }
                return c.isNumber
            })
            if !r.isEmpty { return r }
        }
        return ""
    }
    private static func fix(_ s: String) -> String {
        let map: [Character: Character] = ["O": "0", "o": "0", "D": "0", "Q": "0", "l": "1", "I": "1", "|": "1", "i": "1", "!": "1",
                                           "Z": "2", "z": "2", "S": "5", "s": "5", "b": "6", "G": "6", "T": "7", "B": "8",
                                           "g": "9", "q": "9", ",": ".", "·": "."]
        return String(s.map { map[$0] ?? $0 })
    }
}

// PencilKit 画布：手指也能写
struct InkCanvas: UIViewRepresentable {
    let canvas: PKCanvasView
    var dark = false
    var onChange: () -> Void
    func makeUIView(context: Context) -> PKCanvasView {
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.overrideUserInterfaceStyle = .light   // 不让 PencilKit 自己反色，颜色我们按白天/夜间指定
        canvas.tool = PKInkingTool(.pen, color: dark ? InkColor.night : InkColor.day, width: 10)
        canvas.delegate = context.coordinator
        canvas.isScrollEnabled = false
        return canvas
    }
    func updateUIView(_ v: PKCanvasView, context: Context) {
        context.coordinator.onChange = onChange
        let want = dark ? InkColor.night : InkColor.day
        if (v.tool as? PKInkingTool)?.color != want { v.tool = PKInkingTool(.pen, color: want, width: 10) }
    }
    func makeCoordinator() -> Coord { Coord(onChange) }
    final class Coord: NSObject, PKCanvasViewDelegate {
        var onChange: () -> Void
        init(_ f: @escaping () -> Void) { onChange = f }
        func canvasViewDrawingDidChange(_ c: PKCanvasView) { onChange() }
    }
}

// 日志表格里的一组：手写过的显示原样笔迹（重量 × 次数），没手写的照常显示数字
struct SetInkLabel: View {
    let s: SetRow
    var h: CGFloat = 16
    var font: Font = .caption
    var num = false        // 笔迹下面用小字写上认出来的数字（改过「认成」就显示改后的）
    var body: some View {
        if InkStore.has(s.inkW) == nil && InkStore.has(s.inkR) == nil {
            Text(setLabel(s)).font(font)
        } else if num {
            VStack(spacing: 0) {
                ink(h - 10)
                Text(setLabel(s)).font(.system(size: 9, weight: .semibold, design: .rounded)).monospacedDigit()
                    .opacity(0.75).lineLimit(1).minimumScaleFactor(0.6).frame(height: 10)
            }
        } else {
            ink(h)
        }
    }
    private func ink(_ h: CGFloat) -> some View {
        HStack(spacing: 1) {
            part(s.inkW, s.platesText.map { "\($0)片" } ?? s.w, h)
            Text("×").font(font)
            part(s.inkR, s.r, h)
        }
    }
    @ViewBuilder private func part(_ id: String?, _ text: String, _ h: CGFloat) -> some View {
        if let id = InkStore.has(id) { InkView(id: id, height: h) } else { Text(text.isEmpty ? "—" : text).font(font) }
    }
}
