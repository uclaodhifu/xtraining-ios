import SwiftUI

// 本子风格 + 涨跌配色（11-26 方案）
// 部位色只用在标题和小圆点；格子底色专门表示涨跌：进步浅绿、退步浅红、持平浅灰、新纪录金色、没练斜纹灰
enum Paper {
    private static func dyn(_ light: UIColor, _ dark: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
    static let bg = dyn(UIColor(red: 0.984, green: 0.973, blue: 0.945, alpha: 1), UIColor(red: 0.15, green: 0.145, blue: 0.135, alpha: 1))
    static let rule = dyn(UIColor(red: 0.85, green: 0.89, blue: 0.94, alpha: 1), UIColor(white: 1, alpha: 0.09))
    static let margin = dyn(UIColor(red: 0.95, green: 0.65, blue: 0.65, alpha: 1), UIColor(red: 0.75, green: 0.35, blue: 0.35, alpha: 0.8))
    static let ink = dyn(UIColor(red: 0.114, green: 0.227, blue: 0.431, alpha: 1), UIColor(red: 0.62, green: 0.75, blue: 1, alpha: 1))
    static let pencil = dyn(UIColor(red: 0.62, green: 0.6, blue: 0.56, alpha: 1), UIColor(white: 0.58, alpha: 1))
    // iOS 自带的手写风字体，只用来写数字
    static func hand(_ size: CGFloat) -> Font { .custom("Noteworthy-Bold", size: size) }
}

enum Tone {
    static let up = Color(hex: 0x2f9e44), down = Color(hex: 0xe03131), gold = Color(hex: 0xf5a700)
    static func fill(_ t: Trend, pr: Bool = false) -> Color {
        if pr { return gold.opacity(0.22) }
        switch t {
        case .up: return up.opacity(0.14)
        case .down: return down.opacity(0.12)
        case .same: return Color.primary.opacity(0.06)
        case .none: return .clear
        }
    }
    static func text(_ t: Trend, pr: Bool = false) -> Color {
        if pr { return Color(hex: 0xb07800) }
        switch t { case .up: return up; case .down: return down; default: return .primary }
    }
}

// 和上次比差多少：重量不同写 ±kg，重量一样写 ±次，都一样写“持平”
func deltaText(_ a: Exercise, _ b: Exercise?) -> String {
    guard let b else { return "首次" }
    let d = a.best - b.best
    if abs(d) > 0.001 { return (d > 0 ? "+" : "−") + fmtNum(abs(d)) + "kg" }
    let ar = a.sets.filter { $0.weight == a.best }.map(\.reps).max() ?? 0
    let br = b.sets.filter { $0.weight == b.best }.map(\.reps).max() ?? 0
    let r = ar - br
    if abs(r) > 0.001 { return (r > 0 ? "+" : "−") + fmtNum(abs(r)) + "次" }
    return "持平"
}

// 一组和上次同一组比
func setDelta(_ cur: SetRow, _ prev: SetRow?) -> (String, Trend)? {
    guard let w = Double(cur.w), let r = Double(cur.r) else { return nil }
    guard let p = prev, let pw = Double(p.w) else { return ("首次", .up) }
    let pr = Double(p.r) ?? 0
    if abs(w - pw) > 0.001 { return ((w > pw ? "+" : "−") + fmtNum(abs(w - pw)) + "kg", w > pw ? .up : .down) }
    if abs(r - pr) > 0.001 { return ((r > pr ? "+" : "−") + fmtNum(abs(r - pr)) + "次", r > pr ? .up : .down) }
    return ("持平", .same)
}

struct DeltaTag: View {
    let text: String
    let t: Trend
    var pr = false
    var body: some View {
        Text(pr ? "★ 新纪录" : (t == .same ? "= " + text : text))
            .font(.system(size: 11, weight: .heavy, design: .rounded)).lineLimit(1).fixedSize()
            .foregroundStyle(Tone.text(t, pr: pr))
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(pr ? Tone.gold.opacity(0.25) : (t == .same ? Color.primary.opacity(0.07) : Tone.fill(t))))
    }
}

// 没练：斜纹灰，和“空着”区分开
struct Stripes: View {
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.primary.opacity(0.035)))
            var p = Path(); var x: CGFloat = -size.height
            while x < size.width { p.move(to: CGPoint(x: x, y: size.height)); p.addLine(to: CGPoint(x: x + size.height, y: 0)); x += 8 }
            ctx.stroke(p, with: .color(.primary.opacity(0.06)), lineWidth: 3)
        }
    }
}
