import SwiftUI

// 比赛海报：自己画的（灯光舞台 + 系统健身人物符号 + 大字），不用任何官方图片
struct RacePoster: View {
    let e: Race
    var height: CGFloat = 150

    private static let flags: [String: String] = [
        "美国": "🇺🇸", "科威特": "🇰🇼", "罗马尼亚": "🇷🇴", "巴西": "🇧🇷", "西班牙": "🇪🇸", "葡萄牙": "🇵🇹",
        "印度": "🇮🇳", "阿根廷": "🇦🇷", "南非": "🇿🇦", "奥地利": "🇦🇹", "新西兰": "🇳🇿", "沙特阿拉伯": "🇸🇦",
        "泰国": "🇹🇭", "中国台湾": "🇨🇳", "中国": "🇨🇳", "英国": "🇬🇧", "澳大利亚": "🇦🇺", "加拿大": "🇨🇦",
        "德国": "🇩🇪", "意大利": "🇮🇹", "法国": "🇫🇷", "日本": "🇯🇵", "韩国": "🇰🇷", "阿联酋": "🇦🇪", "墨西哥": "🇲🇽",
    ]
    // 每场比赛固定一个姿势，看起来不重复
    private static let poses = ["figure.strengthtraining.traditional", "figure.arms.open", "figure.strengthtraining.functional", "figure.cross.training", "trophy.fill"]

    var body: some View {
        let p = e.poster
        let pose = Self.poses[stableIndex(e.id, Self.poses.count)]
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [p.0, p.1], startPoint: .topLeading, endPoint: .bottomTrailing)
            // 舞台灯
            GeometryReader { g in
                let w = g.size.width, h = g.size.height
                ZStack {
                    ForEach(0..<3, id: \.self) { k in
                        Path { path in
                            let x = w * (0.55 + 0.18 * CGFloat(k))
                            path.move(to: CGPoint(x: x, y: -10))
                            path.addLine(to: CGPoint(x: x - w * 0.22, y: h + 10))
                            path.addLine(to: CGPoint(x: x + w * 0.02, y: h + 10))
                            path.closeSubpath()
                        }
                        .fill(LinearGradient(colors: [.white.opacity(0.32), .clear], startPoint: .top, endPoint: .bottom))
                        .blur(radius: 6)
                    }
                    Ellipse().fill(.white.opacity(0.22)).frame(width: w * 0.5, height: 22).blur(radius: 10)
                        .position(x: w * 0.74, y: h - 8)
                }
            }
            // 大字水印
            Text(p.2).font(.system(size: height * 0.62, weight: .black)).italic()
                .foregroundStyle(.white.opacity(0.10)).lineLimit(1).minimumScaleFactor(0.3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .offset(x: -6, y: -height * 0.08)
            // 人物剪影
            Image(systemName: pose).font(.system(size: height * 0.62, weight: .bold))
                .foregroundStyle(.black.opacity(0.55))
                .shadow(color: .white.opacity(0.35), radius: 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 22).padding(.bottom, 6)
            LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .center, endPoint: .bottom)
            // 日期 + 国旗 + 名字
            HStack(alignment: .bottom, spacing: 10) {
                VStack(spacing: 0) {
                    Text(month).font(.caption2.bold()).foregroundStyle(.white.opacity(0.85))
                    Text(day).font(.system(size: 26, weight: .heavy)).foregroundStyle(.white)
                }
                .frame(width: 52, height: 52)
                .background(.ultraThinMaterial.opacity(0.9), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text((Self.flags[e.country ?? (e.isWorld ? "" : "中国")] ?? "🏆") + " " + p.2)
                        .font(.caption.weight(.heavy)).foregroundStyle(.white.opacity(0.9))
                    Text(e.city ?? e.org).font(.footnote.bold()).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                }
            }
            .padding(12)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var month: String {
        guard let d = e.date, d.count >= 7, let m = Int(d.dropFirst(5).prefix(2)) else { return "待定" }
        return "\(m)月"
    }
    private var day: String {
        guard let d = e.date, d.count >= 10 else { return "—" }
        return String(d.suffix(2))
    }
    private func stableIndex(_ s: String, _ n: Int) -> Int {
        Int(s.unicodeScalars.reduce(UInt32(7)) { ($0 &* 31) &+ $1.value } % UInt32(n))
    }
}
