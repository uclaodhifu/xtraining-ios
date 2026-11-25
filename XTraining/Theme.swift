import SwiftUI

// 配色主题（和白天/夜间分开选）
enum Skin: String, CaseIterable, Identifiable {
    case ins, x, tiktok, sunset, mint, ocean
    var id: String { rawValue }
    var name: String {
        switch self {
        case .ins: return "霓虹"
        case .x: return "黑白"
        case .tiktok: return "电光"
        case .sunset: return "落日"
        case .mint: return "薄荷"
        case .ocean: return "深海"
        }
    }
    var colors: [Color] {
        switch self {
        case .ins: return [Color(hex: 0xfeda75), Color(hex: 0xfa7e1e), Color(hex: 0xd62976), Color(hex: 0x962fbf), Color(hex: 0x4f5bd5)]
        case .x: return [Color(.label), Color(.label).opacity(0.8)]
        case .tiktok: return [Color(hex: 0x25f4ee), Color(hex: 0xfe2c55)]
        case .sunset: return [Color(hex: 0xffb347), Color(hex: 0xff5e3a)]
        case .mint: return [Color(hex: 0x5be7a9), Color(hex: 0x00a37a)]
        case .ocean: return [Color(hex: 0x5ac8fa), Color(hex: 0x3a5bff)]
        }
    }
    var accent: Color {
        switch self {
        case .ins: return Color(hex: 0xd62976)
        case .x: return Color(hex: 0x1d9bf0)
        case .tiktok: return Color(hex: 0xfe2c55)
        case .sunset: return Color(hex: 0xff5e3a)
        case .mint: return Color(hex: 0x00a37a)
        case .ocean: return Color(hex: 0x3a5bff)
        }
    }
    // 渐变按钮上的字
    var ink: Color { self == .x ? Color(.systemBackground) : .white }
    // 首页背景的三团光
    var blobs: [Color] {
        switch self {
        case .ins: return [Color(hex: 0xfa7e1e), Color(hex: 0xd62976), Color(hex: 0x962fbf)]
        case .x: return [Color.gray, Color.gray, Color(hex: 0x1d9bf0)]
        case .tiktok: return [Color(hex: 0x25f4ee), Color(hex: 0xfe2c55), Color(hex: 0x25f4ee)]
        case .sunset: return [Color(hex: 0xffb347), Color(hex: 0xff5e3a), Color(hex: 0xffd166)]
        case .mint: return [Color(hex: 0x5be7a9), Color(hex: 0x00a37a), Color(hex: 0x5ac8fa)]
        case .ocean: return [Color(hex: 0x5ac8fa), Color(hex: 0x3a5bff), Color(hex: 0xaf52de)]
        }
    }
    var swatch: LinearGradient { LinearGradient(colors: colors, startPoint: .bottomLeading, endPoint: .topTrailing) }
    static var current: Skin { Skin(rawValue: UserDefaults.standard.string(forKey: "skin") ?? "") ?? .ins }
}

// 标题后面的小动画
enum BadgeFX { case bounce, pulse, wave, spin, beat, float, shake }

struct BadgeDef: Identifiable {
    let id: String
    let label: String
    let symbol: String
    let color: Color
    let fx: BadgeFX
}

enum Badges {
    static let all: [BadgeDef] = [
        BadgeDef(id: "fire", label: "燃", symbol: "flame.fill", color: .orange, fx: .bounce),
        BadgeDef(id: "bolt", label: "闪电", symbol: "bolt.fill", color: .yellow, fx: .pulse),
        BadgeDef(id: "bell", label: "举铁", symbol: "dumbbell.fill", color: Color(hex: 0x8e8e93), fx: .shake),
        BadgeDef(id: "heart", label: "心跳", symbol: "heart.fill", color: .red, fx: .beat),
        BadgeDef(id: "star", label: "星星", symbol: "star.fill", color: .yellow, fx: .spin),
        BadgeDef(id: "crown", label: "王冠", symbol: "crown.fill", color: Color(hex: 0xffcc00), fx: .float),
        BadgeDef(id: "cup", label: "奖杯", symbol: "trophy.fill", color: Color(hex: 0xffb340), fx: .bounce),
        BadgeDef(id: "drop", label: "汗水", symbol: "drop.fill", color: .cyan, fx: .float),
        BadgeDef(id: "run", label: "冲刺", symbol: "figure.run", color: .green, fx: .shake),
        BadgeDef(id: "muscle", label: "力量", symbol: "figure.strengthtraining.traditional", color: .purple, fx: .bounce),
        BadgeDef(id: "spark", label: "闪耀", symbol: "sparkles", color: .pink, fx: .pulse),
        BadgeDef(id: "gem", label: "钻石", symbol: "diamond.fill", color: .teal, fx: .spin),
        BadgeDef(id: "wave", label: "节奏", symbol: "waveform", color: .indigo, fx: .wave),
        BadgeDef(id: "zz", label: "休息", symbol: "moon.zzz.fill", color: .indigo, fx: .float),
    ]
    static func find(_ id: String) -> BadgeDef? { all.first { $0.id == id } }
}

struct BadgeView: View {
    let id: String
    var size: CGFloat = 26
    var body: some View {
        if let b = Badges.find(id) {
            TimelineView(.periodic(from: .now, by: 1.2)) { ctx in
                icon(b, Int(ctx.date.timeIntervalSinceReferenceDate / 1.2))
            }
        }
    }
    @ViewBuilder private func icon(_ b: BadgeDef, _ tick: Int) -> some View {
        let img = Image(systemName: b.symbol)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(b.color.gradient)
        switch b.fx {
        case .bounce: img.symbolEffect(.bounce, value: tick)
        case .pulse: img.symbolEffect(.pulse)
        case .wave: img.symbolEffect(.variableColor.iterative.reversing)
        case .spin: img.rotationEffect(.degrees(Double(tick) * 72)).animation(.spring(duration: 0.8), value: tick)
        case .beat: img.scaleEffect(tick % 2 == 0 ? 1 : 1.2).animation(.spring(response: 0.25, dampingFraction: 0.35), value: tick)
        case .float: img.offset(y: tick % 2 == 0 ? 0 : -5).animation(.easeInOut(duration: 1.2), value: tick)
        case .shake: img.rotationEffect(.degrees(tick % 2 == 0 ? -12 : 12)).animation(.spring(response: 0.3, dampingFraction: 0.3), value: tick)
        }
    }
}

// 默认的 X TRAINING 字标
struct XLogo: View {
    var size: CGFloat = 34
    @State private var shine = false
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text("X").font(.system(size: size * 1.15, weight: .black)).italic()
                .foregroundStyle(Brand.gradient)
                .hueRotation(.degrees(shine ? 25 : 0))
            Text("TRAINING").font(.system(size: size * 0.78, weight: .heavy)).italic().kerning(1.5)
        }
        .onAppear { withAnimation(.easeInOut(duration: 2.4).repeatForever()) { shine = true } }
    }
}

// 彩带
struct Confetti: View {
    let start = Date()
    private let bits: [(x: Double, speed: Double, spin: Double, size: Double, color: Color, delay: Double)] = (0..<90).map { _ in
        (Double.random(in: 0...1), Double.random(in: 260...520), Double.random(in: -6...6), Double.random(in: 6...11),
         [Color.pink, .orange, .yellow, .green, .blue, .purple, .red].randomElement()!, Double.random(in: 0...0.5))
    }
    var body: some View {
        TimelineView(.animation) { ctx in
            Canvas { g, size in
                let t = ctx.date.timeIntervalSince(start)
                for b in bits {
                    let tt = t - b.delay
                    guard tt > 0 else { continue }
                    let y = -20 + b.speed * tt + 120 * tt * tt
                    guard y < size.height + 20 else { continue }
                    let x = b.x * size.width + sin(tt * 3 + b.spin) * 24
                    var gg = g
                    gg.translateBy(x: x, y: y)
                    gg.rotate(by: .radians(tt * b.spin))
                    gg.fill(Path(CGRect(x: -b.size / 2, y: -b.size / 4, width: b.size, height: b.size / 2)), with: .color(b.color))
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}
