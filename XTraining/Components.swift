import SwiftUI

// 卡片：iOS 26 以上用液态玻璃，以下用毛玻璃
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        let base = content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        if #available(iOS 26.0, *) {
            base.glassEffect(.regular, in: shape)
        } else {
            base
                .background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
                .shadow(color: .black.opacity(0.06), radius: 12, y: 6)
        }
    }
}

// 系统开了“减弱动态效果”或低电量模式时，动画收敛一点，也更省电
enum Motion {
    static var calm: Bool { UIAccessibility.isReduceMotionEnabled || ProcessInfo.processInfo.isLowPowerModeEnabled }
    static var reduce: Bool { UIAccessibility.isReduceMotionEnabled }
}

// 出现时从下面浮上来，按顺序一个个出现
struct Rise: ViewModifier {
    let index: Int
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || Motion.reduce ? 0 : 18)
            .blur(radius: shown || Motion.reduce ? 0 : 6)
            .scaleEffect(shown || Motion.reduce ? 1 : 0.97, anchor: .top)
            .onAppear {
                if Motion.reduce { withAnimation(.easeOut(duration: 0.2)) { shown = true }; return }
                withAnimation(.spring(response: 0.55, dampingFraction: 0.82).delay(Double(index) * 0.06)) { shown = true }
            }
    }
}

extension View {
    func card() -> some View { modifier(CardStyle()) }
    func rise(_ i: Int) -> some View { modifier(Rise(index: i)) }
}

// 部位按钮（可多选）
struct PartChips: View {
    let parts: [String]
    @Binding var selected: [String]
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: min(parts.count, 6)), spacing: 8) {
            ForEach(parts, id: \.self) { p in
                let on = selected.contains(p)
                Button {
                    if on { selected.removeAll { $0 == p } } else { selected = parts.filter { $0 == p || selected.contains($0) } }
                } label: {
                    Text(p).font(.subheadline.bold())
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .foregroundStyle(on ? Color.white : Color.primary)
                        .background(on ? Parts.color(p) : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .scaleEffect(on ? 1.04 : 1)
                }
                .buttonStyle(.plain)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: on)
            }
        }
        .sensoryFeedback(.selection, trigger: selected)
    }
}

// 大按钮：渐变 + 一道光慢慢扫过，按下去会缩一下
struct BigButton: View {
    let title: String
    var gradient = true
    let action: () -> Void
    @State private var sweep = false
    var body: some View {
        Button(action: action) {
            Text(title).font(.headline)
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(gradient ? Brand.ink : Color.primary)
                .background {
                    let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
                    if gradient {
                        shape.fill(Brand.gradient)
                            .overlay {
                                GeometryReader { g in
                                    LinearGradient(colors: [.clear, .white.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
                                        .frame(width: g.size.width * 0.35)
                                        .rotationEffect(.degrees(18))
                                        .offset(x: sweep ? g.size.width * 1.2 : -g.size.width * 0.5)
                                }
                                .clipShape(shape)
                                .allowsHitTesting(false)
                            }
                            .shadow(color: Brand.pink.opacity(0.3), radius: 10, y: 5)
                    } else {
                        shape.fill(Color(.tertiarySystemFill))
                    }
                }
        }
        .buttonStyle(PressScale())
        .onAppear {
            guard gradient, !Motion.calm else { return }
            withAnimation(.easeInOut(duration: 2.2).delay(0.6).repeatForever(autoreverses: false)) { sweep = true }
        }
    }
}

struct StatTile: View {
    let value: String
    let label: String
    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 24, weight: .heavy, design: .rounded)).monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy, value: value)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// 一次训练的卡片（首页列表用）
struct WorkoutCard: View {
    let w: Workout
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ForEach(w.parts, id: \.self) { p in
                    Circle().fill(Parts.color(p)).frame(width: 8, height: 8)
                }
                Text(w.displayTitle).font(.headline)
                Spacer()
                Text(Day.label(w.date)).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(w.exercises.prefix(6)) { x in
                HStack(alignment: .firstTextBaseline) {
                    Text(x.name).font(.subheadline)
                    Spacer()
                    Text(setsText(x)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            if w.exercises.count > 6 { Text("还有 \(w.exercises.count - 6) 个动作").font(.caption).foregroundStyle(.secondary) }
            if !w.note.isEmpty { Text(w.note).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
        }
        .card()
    }
}

// “80kg × 5 ×2组 · 70kg × 8”
func setsText(_ x: Exercise) -> String {
    if x.isCardio {
        let m = x.sets.reduce(0) { $0 + (Double($1.min) ?? 0) }
        return m > 0 ? "\(fmtNum(m)) 分钟" : "有氧"
    }
    var groups: [(String, Int)] = []
    for s in x.sets {
        let t = s.w.isEmpty ? (s.r.isEmpty ? "—" : "\(s.r)次") : (s.r.isEmpty ? "\(s.w)\(WU.s)" : "\(s.w)\(WU.s) × \(s.r)")
        if let last = groups.last, last.0 == t { groups[groups.count - 1].1 += 1 } else { groups.append((t, 1)) }
    }
    return groups.map { $0.1 > 1 ? "\($0.0) ×\($0.1)组" : $0.0 }.joined(separator: " · ")
}

func fmtNum(_ d: Double) -> String {
    d == d.rounded() ? String(Int(d)) : String(format: "%.1f", d)
}

// 震动
enum Haptic {
    static func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        let g = UIImpactFeedbackGenerator(style: style); g.prepare(); g.impactOccurred()
    }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}

// 重量单位：公斤 / 磅（我 → 重量单位）。记录里存的就是当前单位的数字，换单位时整体换算一次
enum WU {
    static let key = "xt.unit"
    static var lb: Bool { UserDefaults.standard.string(forKey: key) == "lb" }
    static var s: String { lb ? "lb" : "kg" }
    static var plates: [Double] { lb ? [45, 35, 25, 10, 5, 2.5] : [20, 15, 10, 5, 2.5] }
    static let perKg = 2.20462262
    // 换算一个数：磅保留到 0.1（60kg → 132.3lb），公斤保留到 0.1，正好的整数不带小数
    static func conv(_ v: Double, toLb: Bool) -> Double {
        let x = toLb ? v * perKg : v / perKg
        let r = (x * 10).rounded() / 10
        return abs(r - r.rounded()) < 0.051 ? r.rounded() : r
    }
    static func conv(_ s: String, toLb: Bool) -> String {
        guard let v = Double(s), v > 0 else { return s }
        return fmtNum(conv(v, toLb: toLb))
    }
    // 挂片：20kg ↔ 45lb 这样一一对应
    static func plate(_ v: Double, toLb: Bool) -> Double {
        let kg: [Double] = [20, 15, 10, 5, 2.5], lb: [Double] = [45, 35, 25, 10, 5, 2.5]
        if toLb, let i = kg.firstIndex(of: v) { return lb[i] }
        if !toLb, let i = lb.firstIndex(of: v) { return i < kg.count ? kg[i] : 2.5 }
        return conv(v, toLb: toLb)
    }
}
