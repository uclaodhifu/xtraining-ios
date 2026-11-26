import SwiftUI
import PencilKit
import Vision

// 记重量/次数用的手写板：不弹打字键盘，手指直接写数字，停一下自动识别
// 小数点：识别不出来时点「.」，前面写的先记下，后面接着写小数部分
struct WriteCell: Equatable { var ex: UUID; var set: UUID; var weight: Bool }

struct HandPad: View {
    @Binding var value: String
    let title: String
    var onNext: () -> Void
    var onClose: () -> Void

    @State private var canvas = PKCanvasView()
    @State private var committed = ""      // 点了「.」之前已经认好的部分
    @State private var current = ""        // 现在纸上写的这部分
    @State private var job: DispatchWorkItem? = nil
    @State private var busy = false

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.caption.bold()).foregroundStyle(Paper.pencil)
                Spacer()
                Text(value.isEmpty ? "—" : value).font(Paper.hand(30)).foregroundStyle(Paper.ink)
                    .contentTransition(.numericText()).animation(.snappy, value: value)
                Button { onClose() } label: {
                    Image(systemName: "chevron.down").font(.footnote.bold()).foregroundStyle(Paper.pencil)
                        .frame(width: 30, height: 30).background(Circle().fill(Paper.ink.opacity(0.07)))
                }
            }
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.systemBackground).opacity(0.7))
                // 本子横线，写在线上
                Rectangle().fill(Paper.rule).frame(height: 1.5).offset(y: 34)
                if committed.isEmpty && current.isEmpty && !busy {
                    Text("在这里用手指写数字").font(.subheadline).foregroundStyle(Paper.pencil.opacity(0.7)).allowsHitTesting(false)
                }
                InkCanvas(canvas: canvas) { scheduleRecognize() }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .frame(height: 150)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Paper.ink.opacity(0.15)))
            HStack(spacing: 8) {
                key(".", wide: false) { dot() }
                key("清除", wide: false) { clear() }
                key("下一格  →", wide: true, strong: true) { flush(); onNext() }
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

    private func reset() {
        job?.cancel(); canvas.drawing = PKDrawing(); committed = ""; current = ""
    }
    private func clear() {
        reset(); value = ""
    }
    private func dot() {
        flush()
        committed = (committed + current).replacingOccurrences(of: ".", with: "") + "."
        current = ""; canvas.drawing = PKDrawing()
        value = committed
    }
    // 下一格之前，如果还在等识别，马上认一次
    private func flush() {
        guard job != nil, !canvas.drawing.strokes.isEmpty else { return }
        job?.cancel(); job = nil
        let r = HandPad.read(canvas.drawing, size: canvas.bounds.size)
        if !r.isEmpty { current = r; value = clean(committed + current) }
    }
    private func scheduleRecognize() {
        job?.cancel()
        let d = canvas.drawing, size = canvas.bounds.size
        guard !d.strokes.isEmpty else { return }
        let w = DispatchWorkItem {
            busy = true
            DispatchQueue.global(qos: .userInitiated).async {
                let r = HandPad.read(d, size: size)
                DispatchQueue.main.async {
                    busy = false; job = nil
                    if !r.isEmpty { current = r; value = clean(committed + current); Haptic.tap() }
                }
            }
        }
        job = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: w)
    }
    private func clean(_ s: String) -> String {
        var seenDot = false
        return String(s.filter { c in
            if c == "." { if seenDot { return false }; seenDot = true; return true }
            return c.isNumber
        })
    }

    // 把笔画画成白底黑字的图，交给系统的文字识别，只留数字和小数点
    static func read(_ drawing: PKDrawing, size: CGSize) -> String {
        let strokes = drawing.strokes.map { s -> PKStroke in var s = s; s.ink = PKInk(.pen, color: .black); return s }
        let d = PKDrawing(strokes: strokes)
        var rect = d.bounds.insetBy(dx: -24, dy: -24)
        if rect.isEmpty { rect = CGRect(origin: .zero, size: size) }
        let ink = d.image(from: rect, scale: 3)
        let img = UIGraphicsImageRenderer(size: ink.size).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: ink.size))
            ink.draw(at: .zero)
        }
        guard let cg = img.cgImage else { return "" }
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = false
        req.recognitionLanguages = ["en-US"]
        try? VNImageRequestHandler(cgImage: cg).perform([req])
        let cands = (req.results ?? []).sorted { $0.boundingBox.minX < $1.boundingBox.minX }
            .compactMap { $0.topCandidates(3).first { fix($0.string).contains(where: \.isNumber) } ?? $0.topCandidates(1).first }
        let raw = cands.map { fix($0.string) }.joined()
        var seenDot = false
        return String(raw.filter { c in
            if c == "." { if seenDot { return false }; seenDot = true; return true }
            return c.isNumber
        })
    }
    // 手写常见认错的字母改回数字
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
    var onChange: () -> Void
    func makeUIView(context: Context) -> PKCanvasView {
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.tool = PKInkingTool(.pen, color: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.62, green: 0.75, blue: 1, alpha: 1) : UIColor(red: 0.114, green: 0.227, blue: 0.431, alpha: 1) }, width: 9)
        canvas.delegate = context.coordinator
        canvas.isScrollEnabled = false
        return canvas
    }
    func updateUIView(_ v: PKCanvasView, context: Context) { context.coordinator.onChange = onChange }
    func makeCoordinator() -> Coord { Coord(onChange) }
    final class Coord: NSObject, PKCanvasViewDelegate {
        var onChange: () -> Void
        init(_ f: @escaping () -> Void) { onChange = f }
        func canvasViewDrawingDidChange(_ c: PKCanvasView) { onChange() }
    }
}
