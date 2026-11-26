import SwiftUI
import PencilKit
import Vision

// 输入方式（我 → 输入方式）：0 只有重量/次数手写（默认）  1 全部手写，格子里留原样笔迹  2 都用系统键盘
enum InputMode { static let key = "xt.inputMode" }

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
        cache.removeAllObjects()
    }
    static func load(_ id: String) -> PKDrawing? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent(id)) else { return nil }
        return try? PKDrawing(data: data)
    }
    // 画成图（按当前白天/夜间重新上墨蓝色）
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
struct InkView: View {
    let id: String
    var height: CGFloat = 30
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        if let img = InkStore.image(id, dark: scheme == .dark) {
            Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: height)
        }
    }
}

// 手写板：手指写，停一下自动识别。数字模式只留数字和小数点；文字模式认中文（写动作名）
struct HandPad: View {
    @Binding var value: String
    let title: String
    var textMode = false
    var nextLabel = "下一格  →"
    var onInk: ((PKDrawing) -> Void)? = nil
    var onNext: () -> Void
    var onClose: () -> Void

    @State private var canvas = PKCanvasView()
    @State private var dotAt: Int? = nil     // 点「.」时前面已经写了几位数字
    @State private var job: DispatchWorkItem? = nil
    @State private var empty = true
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.caption.bold()).foregroundStyle(Paper.pencil).lineLimit(1)
                Spacer()
                Text(value.isEmpty ? "—" : value).font(textMode ? .system(size: 20, weight: .bold) : Paper.hand(30))
                    .foregroundStyle(Paper.ink).lineLimit(1)
                    .contentTransition(.numericText()).animation(.snappy, value: value)
                Button { onClose() } label: {
                    Image(systemName: "chevron.down").font(.footnote.bold()).foregroundStyle(Paper.pencil)
                        .frame(width: 30, height: 30).background(Circle().fill(Paper.ink.opacity(0.07)))
                }
            }
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(scheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.75))
                Rectangle().fill(Paper.rule).frame(height: 1.5).offset(y: 34)
                if empty {
                    Text(textMode ? "在这里写动作名，比如 杠铃卧推" : "在这里用手指写数字")
                        .font(.subheadline).foregroundStyle(Paper.pencil.opacity(0.7)).allowsHitTesting(false)
                }
                InkCanvas(canvas: canvas, dark: scheme == .dark) { empty = canvas.drawing.strokes.isEmpty; scheduleRecognize() }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .frame(height: 150)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Paper.ink.opacity(0.15)))
            HStack(spacing: 8) {
                if !textMode { key(".", wide: false) { dot() } }
                key("清除", wide: false) { clear() }
                key(nextLabel, wide: true, strong: true) { flush(); onNext() }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Paper.bg).shadow(color: .black.opacity(0.18), radius: 12, y: -2))
        .padding(.horizontal, 10).padding(.bottom, 6)
        .onAppear { reset() }
        .onChange(of: title) { _, _ in reset() }
    }

    private func key(_ t: String, wide: Bool, strong: Bool = false, _ a: @escaping () -> Void) -> some View {
        Button { Haptic.tap(); a() } label: {
            Text(t).font(.headline).frame(maxWidth: wide ? .infinity : 64, minHeight: 44)
                .foregroundStyle(strong ? Color.white : Paper.ink)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(strong ? Paper.ink : Paper.ink.opacity(0.08)))
        }
        .buttonStyle(PressScale())
    }

    private func reset() { job?.cancel(); job = nil; canvas.drawing = PKDrawing(); dotAt = nil; empty = true }
    private func clear() { reset(); value = "" }
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
        value = v
    }
    private func flush() {
        guard job != nil, !canvas.drawing.strokes.isEmpty else { return }
        job?.cancel(); job = nil
        let d = canvas.drawing
        let r = HandPad.read(d, text: textMode)
        if !r.isEmpty { apply(r) }
        onInk?(d)
    }
    private func scheduleRecognize() {
        job?.cancel()
        let d = canvas.drawing, tm = textMode
        guard !d.strokes.isEmpty else { return }
        let w = DispatchWorkItem {
            DispatchQueue.global(qos: .userInitiated).async {
                let r = HandPad.read(d, text: tm)
                DispatchQueue.main.async {
                    job = nil
                    if !r.isEmpty { apply(r); Haptic.tap() }
                    onInk?(d)   // 认不出来也先把笔迹留下
                }
            }
        }
        job = w
        DispatchQueue.main.asyncAfter(deadline: .now() + (textMode ? 0.9 : 0.6), execute: w)
    }

    // 笔画画成白底黑字的图，交给 iPhone 自带的文字识别（不联网）
    // 手写的短数字系统有时认不出，所以：放在一张宽一点的白纸中间、笔画加粗，认不出再换几种设置多试几次
    static func read(_ drawing: PKDrawing, text: Bool) -> String {
        let d = PKDrawing(strokes: drawing.strokes.map { var s = $0; s.ink = PKInk(.marker, color: .black); return s })
        let b = d.bounds
        guard !b.isEmpty else { return "" }
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
        guard let cg = img.cgImage else { return "" }
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
