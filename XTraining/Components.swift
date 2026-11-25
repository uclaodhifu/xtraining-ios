import SwiftUI

// 卡片：圆角 + 毛玻璃，白天/夜间都好看
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.15)))
    }
}
extension View {
    func card() -> some View { modifier(CardStyle()) }
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

// 大按钮
struct BigButton: View {
    let title: String
    var gradient = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.headline)
                .frame(maxWidth: .infinity, minHeight: 50)
                .foregroundStyle(gradient ? Color.white : Color.primary)
                .background {
                    if gradient { RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Brand.gradient) }
                    else { RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.tertiarySystemFill)) }
                }
        }
        .buttonStyle(.plain)
    }
}

struct StatTile: View {
    let value: String
    let label: String
    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.title2.bold()).monospacedDigit()
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
        let t = s.w.isEmpty ? (s.r.isEmpty ? "—" : "\(s.r)次") : (s.r.isEmpty ? "\(s.w)kg" : "\(s.w)kg × \(s.r)")
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
