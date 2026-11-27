import SwiftUI

// MARK: - 打卡地球：自己画的 3D 地球（正射投影），可拖动旋转、双指缩放

enum GlobeLand {
    // 陆地轮廓（Natural Earth 1:110m，公有领域），经纬度 ×10 存成整数
    static let polys: [[SIMD2<Double>]] = {
        guard let u = Bundle.main.url(forResource: "GlobeLand", withExtension: "json"),
              let d = try? Data(contentsOf: u), let a = try? JSONDecoder().decode([[Int]].self, from: d) else { return [] }
        return a.map { r in stride(from: 0, to: r.count - 1, by: 2).map { SIMD2(Double(r[$0]) / 10, Double(r[$0 + 1]) / 10) } }
    }()
}

struct GlobeProj {
    var lon0: Double   // 正中间的经度
    var lat0: Double   // 正中间的纬度
    var r: Double
    var c: CGPoint
    // 返回屏幕坐标和是否在正面（背面的点压到边缘上，画陆地用）
    func p(_ lon: Double, _ lat: Double) -> (CGPoint, Bool) {
        let l = (lon - lon0) * .pi / 180, f = lat * .pi / 180, f0 = lat0 * .pi / 180
        let cosc = sin(f0) * sin(f) + cos(f0) * cos(f) * cos(l)
        var x = cos(f) * sin(l), y = cos(f0) * sin(f) - sin(f0) * cos(f) * cos(l)
        if cosc < 0 { let n = max(1e-9, (x * x + y * y).squareRoot()); x /= n; y /= n }
        return (CGPoint(x: c.x + x * r, y: c.y - y * r), cosc >= 0)
    }
    func depth(_ lon: Double, _ lat: Double) -> Double {
        let l = (lon - lon0) * .pi / 180, f = lat * .pi / 180, f0 = lat0 * .pi / 180
        return sin(f0) * sin(f) + cos(f0) * cos(f) * cos(l)
    }
}

// 地球本体（海 + 陆地 + 经纬线 + 大气光）
struct GlobeBall: View {
    var proj: GlobeProj
    var dots: [(Double, Double)] = []
    var small = false
    var body: some View {
        Canvas { ctx, _ in
            let c = proj.c, r = proj.r
            let disk = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            if !small {
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 1.08, y: c.y - r * 1.08, width: r * 2.16, height: r * 2.16)),
                         with: .radialGradient(Gradient(stops: [.init(color: .clear, location: 0.88), .init(color: Color(hex: 0x8a7dff).opacity(0.45), location: 0.93), .init(color: .clear, location: 1)]),
                                               center: c, startRadius: 0, endRadius: r * 1.08))
            }
            ctx.fill(disk, with: .radialGradient(Gradient(colors: [Color(hex: 0x3a4a9a), Color(hex: 0x1a2160), Color(hex: 0x0b0f33)]),
                                                 center: CGPoint(x: c.x - r * 0.3, y: c.y - r * 0.35), startRadius: 0, endRadius: r * 1.4))
            ctx.clip(to: disk)
            // 经纬线
            if !small {
                var g = Path()
                for lat in stride(from: -60.0, through: 60, by: 30) {
                    var first = true
                    for lon in stride(from: -180.0, through: 180, by: 6) {
                        let (pt, vis) = proj.p(lon, lat)
                        if !vis { first = true; continue }
                        if first { g.move(to: pt); first = false } else { g.addLine(to: pt) }
                    }
                }
                for lon in stride(from: -180.0, to: 180, by: 30) {
                    var first = true
                    for lat in stride(from: -80.0, through: 80, by: 5) {
                        let (pt, vis) = proj.p(lon, lat)
                        if !vis { first = true; continue }
                        if first { g.move(to: pt); first = false } else { g.addLine(to: pt) }
                    }
                }
                ctx.stroke(g, with: .color(.white.opacity(0.07)), lineWidth: 0.6)
            }
            // 陆地
            var land = Path()
            for poly in GlobeLand.polys {
                var any = false
                var pts: [CGPoint] = []
                pts.reserveCapacity(poly.count)
                for v in poly { let (pt, vis) = proj.p(v.x, v.y); if vis { any = true }; pts.append(pt) }
                if any { land.addLines(pts); land.closeSubpath() }
            }
            ctx.fill(land, with: .color(Color(hex: small ? 0x7d8cff : 0x4f5fb8)))
            if !small { ctx.stroke(land, with: .color(Color(hex: 0x8f9cff).opacity(0.45)), lineWidth: 0.7) }
            // 光点
            for (lon, lat) in dots {
                let (pt, vis) = proj.p(lon, lat); guard vis else { continue }
                let s: CGFloat = small ? 2.4 : 6
                ctx.fill(Path(ellipseIn: CGRect(x: pt.x - s * 1.6, y: pt.y - s * 1.6, width: s * 3.2, height: s * 3.2)), with: .color(Color(hex: 0xdd2a7b).opacity(0.35)))
                ctx.fill(Path(ellipseIn: CGRect(x: pt.x - s / 2, y: pt.y - s / 2, width: s, height: s)), with: .color(Color(hex: 0xffd1e6)))
            }
            // 边缘一点高光
            ctx.fill(disk, with: .radialGradient(Gradient(colors: [.clear, .clear, .black.opacity(0.35)]), center: c, startRadius: 0, endRadius: r))
        }
    }
}

// MARK: - 卡通小人：6 个人物（「我 → 我的打卡小人」自己选），按这次练的部位做动作，循环
enum LiftKind { case squat, flex, jack, wave, jump, run
    static func of(_ part: String?) -> LiftKind {
        switch part {
        case "腿": return .squat
        case "胸", "手臂": return .flex
        case "背", "肩": return .jack
        case "有氧": return .run
        case nil: return .wave
        default: return .jump
        }
    }
    static let all: [LiftKind] = [.squat, .flex, .jack, .wave, .jump, .run]
    var name: String {
        switch self { case .squat: return "深蹲"; case .flex: return "秀肌肉"; case .jack: return "开合跳"; case .wave: return "挥手"; case .jump: return "跳一下"; case .run: return "跑步" }
    }
}

enum LifterChar: String, CaseIterable, Identifiable {
    case boy, girl, bald, cap, panda, robot
    var id: String { rawValue }
    var name: String { ["阿强", "小美", "大壮", "帽子哥", "滚滚", "铁甲"][Self.allCases.firstIndex(of: self)!] }
    var desc: String { ["短发小哥", "马尾女生", "光头壮汉", "反戴棒球帽", "健身熊猫", "健身机器人"][Self.allCases.firstIndex(of: self)!] }
    var shirt: Color { [Color(hex: 0xff7a00), Color(hex: 0xe64980), Color(hex: 0x2f9e44), Color(hex: 0xfab005), Color(hex: 0x222222), Color(hex: 0x868e96)][Self.allCases.firstIndex(of: self)!] }
    var pants: Color { [Color(hex: 0x2b2d42), Color(hex: 0x343a40), Color(hex: 0x212529), Color(hex: 0x1864ab), Color(hex: 0x222222), Color(hex: 0x495057)][Self.allCases.firstIndex(of: self)!] }
    var arm: Color {
        switch self { case .bald: return Color(hex: 0xf2c39b); case .panda: return Color(hex: 0x222222); case .robot: return Color(hex: 0xadb5bd); default: return Color(hex: 0xffd8b5) }
    }
    var width: CGFloat { switch self { case .bald: return 15; case .panda: return 14; case .girl: return 11; default: return 12 } }
    static var mine: LifterChar {
        get { LifterChar(rawValue: UserDefaults.standard.string(forKey: "xt.lifter") ?? "") ?? .boy }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "xt.lifter") }
    }
    static func from(_ s: String?) -> LifterChar { LifterChar(rawValue: s ?? "") ?? .boy }
}

struct Lifter: View {
    var kind: LiftKind
    var char: LifterChar = .boy
    var t: Double          // 动画时间（秒）
    var size: CGFloat = 40
    var body: some View {
        Canvas { ctx, sz in
            let k = sz.width / 40
            ctx.scaleBy(x: k, y: k)
            let s = (1 - cos(t * 2.6)) / 2          // 0~1 循环
            let skin = Color(hex: 0xffd8b5), plate = Color(hex: 0xff5c8a)
            let c = char, shirt = c.shirt, pants = c.pants, arm = c.arm, W = c.width
            func line(_ pts: [CGPoint], _ col: Color, _ w: CGFloat) {
                var p = Path(); p.addLines(pts); ctx.stroke(p, with: .color(col), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
            }
            func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ col: Color) { ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(col)) }
            func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ col: Color, _ rr: CGFloat = 2) { ctx.fill(Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: rr), with: .color(col)) }
            func arc(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ col: Color) {
                var h = Path(); h.addArc(center: CGPoint(x: x, y: y), radius: r, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false); h.closeSubpath(); ctx.fill(h, with: .color(col))
            }
            func head(_ x: CGFloat, _ y: CGFloat) {
                switch c {
                case .boy:
                    circle(x, y, 5, skin); arc(x, y - 0.4, 5.2, Color(hex: 0x222222))
                case .girl:
                    var tail = Path(); tail.move(to: CGPoint(x: x + 4, y: y - 3)); tail.addQuadCurve(to: CGPoint(x: x + 5, y: y + 6), control: CGPoint(x: x + 10, y: y - 2)); tail.addLine(to: CGPoint(x: x + 3, y: y)); ctx.fill(tail, with: .color(Color(hex: 0x6b3a1e)))
                    circle(x, y, 5, skin); arc(x, y, 5.3, Color(hex: 0x6b3a1e)); circle(x + 4.6, y - 3, 1.3, plate)
                case .bald:
                    circle(x, y, 5.4, Color(hex: 0xf2c39b))
                    var beard = Path(); beard.addArc(center: CGPoint(x: x, y: y + 1.5), radius: 4.2, startAngle: .degrees(20), endAngle: .degrees(160), clockwise: false); ctx.stroke(beard, with: .color(Color(hex: 0x5a3a22)), lineWidth: 2)
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 3.4, y: y - 3.8, width: 3.2, height: 1.6)), with: .color(.white.opacity(0.5)))
                case .cap:
                    circle(x, y, 5, skin); arc(x, y - 0.8, 5.3, Color(hex: 0x1c7ed6)); rect(x - 8.5, y - 1.6, 5, 1.8, Color(hex: 0x1c7ed6), 0.9)
                case .panda:
                    circle(x - 4.2, y - 4.2, 2.2, Color(hex: 0x222222)); circle(x + 4.2, y - 4.2, 2.2, Color(hex: 0x222222))
                    circle(x, y, 5.4, .white)
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 3.5, y: y - 1.9, width: 3, height: 3.8)), with: .color(Color(hex: 0x222222)))
                    ctx.fill(Path(ellipseIn: CGRect(x: x + 0.5, y: y - 1.9, width: 3, height: 3.8)), with: .color(Color(hex: 0x222222)))
                    circle(x, y + 2.4, 0.8, Color(hex: 0x222222))
                case .robot:
                    line([CGPoint(x: x, y: y - 5), CGPoint(x: x, y: y - 8)], Color(hex: 0xadb5bd), 1); circle(x, y - 8.5, 1.2, plate)
                    rect(x - 5, y - 4.6, 10, 9, Color(hex: 0xced4da), 2.5); rect(x - 3.6, y - 2, 7.2, 3, Color(hex: 0x212529), 1.5)
                    circle(x - 1.6, y - 0.5, 0.8, Color(hex: 0x4dd4ff)); circle(x + 1.6, y - 0.5, 0.8, Color(hex: 0x4dd4ff))
                }
            }
            func torso(_ y: CGFloat, _ h: CGFloat) {
                rect(20 - W / 2, y, W, h, shirt, 5)
                if c == .panda { ctx.fill(Path(ellipseIn: CGRect(x: 20 - W / 2 + 2.5, y: y + 2, width: W - 5, height: h - 3)), with: .color(.white)) }
                if c == .robot { rect(17, y + 3, 6, 4, Color(hex: 0x4dd4ff).opacity(0.7), 1) }
            }
            func legs(_ y: CGFloat) {
                line([CGPoint(x: 17, y: y), CGPoint(x: 15, y: y + 7), CGPoint(x: 15, y: 42)], pants, 4)
                line([CGPoint(x: 23, y: y), CGPoint(x: 25, y: y + 7), CGPoint(x: 25, y: 42)], pants, 4)
            }
            let S = CGFloat(s)
            switch kind {
            case .squat:   // 徒手深蹲：手往前伸
                let d = 8 * S
                head(20, 10 + d)
                torso(16 + d, 11 - 2 * S)
                line([CGPoint(x: 15, y: 19 + d), CGPoint(x: 6, y: 20 + d)], arm, 3.2)
                line([CGPoint(x: 25, y: 19 + d), CGPoint(x: 34, y: 20 + d)], arm, 3.2)
                line([CGPoint(x: 16, y: 26 + d * 0.8), CGPoint(x: 10 - 2 * S, y: 33 + d * 0.3), CGPoint(x: 14, y: 42)], pants, 4)
                line([CGPoint(x: 24, y: 26 + d * 0.8), CGPoint(x: 30 + 2 * S, y: 33 + d * 0.3), CGPoint(x: 26, y: 42)], pants, 4)
            case .jack:    // 开合跳
                let u = S
                head(20, 10 - 2 * u)
                torso(16 - 2 * u, 13)
                line([CGPoint(x: 15, y: 18 - 2 * u), CGPoint(x: 9 - 3 * u, y: 24 - 14 * u), CGPoint(x: 10 - 2 * u, y: 30 - 24 * u)], arm, 3.2)
                line([CGPoint(x: 25, y: 18 - 2 * u), CGPoint(x: 31 + 3 * u, y: 24 - 14 * u), CGPoint(x: 30 + 2 * u, y: 30 - 24 * u)], arm, 3.2)
                line([CGPoint(x: 17, y: 28 - 2 * u), CGPoint(x: 14 - 6 * u, y: 42)], pants, 4)
                line([CGPoint(x: 23, y: 28 - 2 * u), CGPoint(x: 26 + 6 * u, y: 42)], pants, 4)
            case .flex:    // 秀肌肉：二头一鼓一鼓
                head(20, 10)
                torso(16, 13)
                line([CGPoint(x: 15, y: 18), CGPoint(x: 8, y: 19), CGPoint(x: 8, y: 12 - S)], arm, 3.4)
                line([CGPoint(x: 25, y: 18), CGPoint(x: 32, y: 19), CGPoint(x: 32, y: 12 - S)], arm, 3.4)
                circle(8.6, 16 - S * 0.5, 2 + 1.4 * S, arm); circle(31.4, 16 - S * 0.5, 2 + 1.4 * S, arm)
                legs(28)
            case .wave:    // 挥手
                let w = CGFloat(sin(t * 6))
                head(20, 10)
                torso(16, 13)
                line([CGPoint(x: 15, y: 18), CGPoint(x: 12, y: 25), CGPoint(x: 13, y: 30)], arm, 3.2)
                line([CGPoint(x: 25, y: 18), CGPoint(x: 30, y: 12), CGPoint(x: 30 + 4 * w, y: 5)], arm, 3.2)
                legs(28)
            case .jump:    // 跳一下
                let j = -6 * S
                ctx.fill(Path(ellipseIn: CGRect(x: 20 - (8 - 3 * S), y: 42, width: 2 * (8 - 3 * S), height: 2.4)), with: .color(.black.opacity(0.12)))
                head(20, 10 + j)
                torso(16 + j, 12)
                line([CGPoint(x: 15, y: 18 + j), CGPoint(x: 9, y: 12 + j), CGPoint(x: 8, y: 6 + j)], arm, 3.2)
                line([CGPoint(x: 25, y: 18 + j), CGPoint(x: 31, y: 12 + j), CGPoint(x: 32, y: 6 + j)], arm, 3.2)
                line([CGPoint(x: 17, y: 27 + j), CGPoint(x: 14, y: 33 + j), CGPoint(x: 16, y: 39 + j)], pants, 4)
                line([CGPoint(x: 23, y: 27 + j), CGPoint(x: 26, y: 33 + j), CGPoint(x: 24, y: 39 + j)], pants, 4)
            case .run:
                let a = sin(t * 7), bob = CGFloat(abs(a)) * -1.5
                head(21, 8 + bob)
                torso(14 + bob, 13)
                let A = CGFloat(a)
                line([CGPoint(x: 16, y: 17 + bob), CGPoint(x: 11 + 5 * A, y: 23 + bob)], arm, 3.2)
                line([CGPoint(x: 25, y: 17 + bob), CGPoint(x: 29 - 5 * A, y: 22 + bob)], arm, 3.2)
                line([CGPoint(x: 18, y: 27 + bob), CGPoint(x: 15 + 7 * A, y: 34), CGPoint(x: 12 + 9 * A, y: 41)], pants, 4)
                line([CGPoint(x: 22, y: 27 + bob), CGPoint(x: 25 - 7 * A, y: 34), CGPoint(x: 28 - 9 * A, y: 41)], pants, 4)
            }
        }
        .frame(width: size, height: size * 1.1)
    }
}

// 「我 → 我的打卡小人」：6 个人物选一个
struct LifterPicker: View {
    @State private var mine = LifterChar.mine
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("在地球上，你打卡的健身房会站着你选的小人").font(.subheadline).foregroundStyle(.secondary)
                TimelineView(.animation(minimumInterval: 1 / 30, paused: Motion.calm)) { tl in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    VStack(spacing: 14) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                            ForEach(Array(LifterChar.allCases.enumerated()), id: \.element) { i, c in
                                let on = c == mine
                                Button { Haptic.tap(); mine = c; LifterChar.mine = c; GymStore.shared.setChar(c) } label: {
                                    VStack(spacing: 4) {
                                        Lifter(kind: LiftKind.all[i], char: c, t: t + Double(i) * 0.4, size: 62)
                                            .frame(maxWidth: .infinity).frame(height: 84)
                                            .background(RoundedRectangle(cornerRadius: 12).fill(RadialGradient(colors: [Color(hex: 0xeef0ff).opacity(0.8), .clear], center: .bottom, startRadius: 0, endRadius: 70)))
                                        Text(c.name).font(.headline).foregroundStyle(.primary)
                                        Text(c.desc).font(.caption2).foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 10).padding(.horizontal, 6)
                                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
                                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(on ? Brand.pink : .clear, lineWidth: 2.5))
                                    .overlay(alignment: .topTrailing) {
                                        if on { Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(.white, Brand.pink).padding(6) }
                                    }
                                }
                                .buttonStyle(PressScale())
                            }
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(mine.name)在地球上会根据你这次练的部位做动作").font(.footnote).foregroundStyle(Color(hex: 0xa5a8c2))
                            HStack {
                                ForEach(LiftKind.all, id: \.self) { k in
                                    VStack(spacing: 2) {
                                        Lifter(kind: k, char: mine, t: t, size: 44)
                                        Text(k.name).font(.system(size: 10)).foregroundStyle(Color(hex: 0xc9cbe0))
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                            }
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(LinearGradient(colors: [Color(hex: 0x1b1f3b), Color(hex: 0x05060f)], startPoint: .topLeading, endPoint: .bottomTrailing)))
                    }
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("我的打卡小人")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 打卡地球页面
struct GlobeScreen: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var gs = GymStore.shared
    @State private var lon0 = 112.0
    @State private var lat0 = 30.0
    @State private var zoom = 1.0
    @State private var dragStart: (Double, Double)? = nil
    @State private var zoomStart: Double? = nil
    @State private var lastTouch = Date.distantPast
    @State private var spinBase = Date()
    @State private var range = 0
    @State private var selected: GymInfo? = nil
    @State private var open: GymInfo? = nil

    // 所有健身房都上地球（后台新建、还没人打卡的也显示头像），有人打卡的才站小人
    private var gyms: [GymInfo] { gs.world?.gyms ?? [] }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                let r = min(w * 0.6, h * 0.5) * zoom
                let center = CGPoint(x: w / 2, y: h * 0.52)
                TimelineView(.animation(minimumInterval: 1 / 30, paused: Motion.calm)) { tl in
                    let now = tl.date
                    // 不碰它的时候慢慢自己转
                    let idle = now.timeIntervalSince(lastTouch) > 4 && selected == nil && !Motion.calm
                    let spin = idle ? now.timeIntervalSince(max(spinBase, lastTouch.addingTimeInterval(4))) * 2.5 : 0
                    let proj = GlobeProj(lon0: lon0 - spin, lat0: lat0, r: r, c: center)
                    let t = now.timeIntervalSinceReferenceDate
                    let ranked = gyms.sorted { $0.count(range) > $1.count(range) }
                    let figures = Set(ranked.filter { $0.count(range) > 0 }.prefix(zoom > 1.8 ? 16 : 8).map(\.id))
                    let faces = Set(ranked.prefix(zoom > 1.8 ? 40 : 18).map(\.id))
                    ZStack {
                        GlobeBall(proj: proj, dots: gyms.filter { !faces.contains($0.id) }.map { ($0.lon, $0.lat) })
                        ForEach(ranked.filter { faces.contains($0.id) }.sorted { proj.depth($0.lon, $0.lat) < proj.depth($1.lon, $1.lat) }) { g in
                            let pv = proj.p(g.lon, g.lat)
                            let dep = proj.depth(g.lon, g.lat)
                            if pv.1 && dep > 0.15 {
                                pin(g, figure: figures.contains(g.id), t: t + Double(abs(g.id.hashValue % 100)) / 10)
                                    .scaleEffect(0.7 + 0.3 * dep, anchor: .bottom)
                                    .opacity(min(1, (dep - 0.15) * 4))
                                    .position(x: pv.0.x, y: pv.0.y - 30)
                            }
                        }
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { v in
                            if dragStart == nil { freeze(); dragStart = (lon0, lat0) }
                            let k = 180 / (.pi * r)
                            lon0 = dragStart!.0 - v.translation.width * k
                            lat0 = min(80, max(-80, dragStart!.1 + v.translation.height * k))
                            lastTouch = Date()
                        }
                        .onEnded { _ in dragStart = nil; lastTouch = Date() }
                        .simultaneously(with: MagnificationGesture()
                            .onChanged { m in
                                if zoomStart == nil { freeze(); zoomStart = zoom }
                                zoom = min(4, max(0.7, zoomStart! * m)); lastTouch = Date()
                            }
                            .onEnded { _ in zoomStart = nil; lastTouch = Date() })
                )
                .onTapGesture { withAnimation(.snappy) { selected = nil } }
            }
            .ignoresSafeArea(edges: .bottom)
            .background(
                ZStack {
                    RadialGradient(colors: [Color(hex: 0x1b1f3b), Color(hex: 0x05060f)], center: UnitPoint(x: 0.5, y: 0.3), startRadius: 0, endRadius: 600)
                    Stars()
                }.ignoresSafeArea()
            )
            .safeAreaInset(edge: .top) { header }
            .overlay(alignment: .bottom) { if let g = selected { card(g).padding(.horizontal, 14).padding(.bottom, 20).transition(.move(edge: .bottom).combined(with: .opacity)) } }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $open) { g in GymPage(gymID: g.id) }
            .task {
                if let g = gs.lastGym { lon0 = g.lon; lat0 = max(-60, min(60, g.lat)) }
                await gs.refresh()
                gs.seenCount = max(1, gs.myGymWeek)
            }
        }
        .preferredColorScheme(.dark)
    }

    // 停下自动旋转时把当前角度存下来，不会跳
    private func freeze() {
        let now = Date()
        if now.timeIntervalSince(lastTouch) > 4 && selected == nil && !Motion.calm {
            lon0 -= now.timeIntervalSince(max(spinBase, lastTouch.addingTimeInterval(4))) * 2.5
        }
        spinBase = now
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("打卡地球").font(.system(size: 30, weight: .heavy))
                    Text(sub).font(.footnote).foregroundStyle(Color(hex: 0xa5a8c2))
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.headline).foregroundStyle(.white)
                        .frame(width: 36, height: 36).background(.ultraThinMaterial, in: Circle())
                }
            }
            Picker("", selection: $range) { Text("本周").tag(0); Text("本月").tag(1); Text("全部").tag(2) }
                .pickerStyle(.segmented)
        }
        .padding(.horizontal, 20).padding(.top, 8)
    }

    private var sub: String {
        guard let w = gs.world else { return gs.failed ? "连不上服务器，稍后再试" : "正在加载…" }
        if w.gyms.isEmpty { return "还没有人打卡，练完去训练页选健身房吧" }
        switch range {
        case 0: return "本周 \(w.weekPeople) 人在 \(w.weekGyms) 家健身房练过"
        case 1: return "本月 \(w.monthPeople) 人在 \(w.monthGyms) 家健身房练过"
        default: return "一共 \(w.allPeople) 人在 \(w.gyms.filter { $0.checkins > 0 }.count) 家健身房打过卡"
        }
    }

    private func pin(_ g: GymInfo, figure: Bool, t: Double) -> some View {
        VStack(spacing: 1) {
            if figure {
                Text("\(g.count(range))").font(.system(size: 10, weight: .heavy)).foregroundStyle(Color(hex: 0xffd1e6))
                // 站的是最近在这打卡的人自己选的小人，人多的地方站 2~3 个
                let people = Array(g.recent.prefix(g.count(range) >= 6 ? 3 : g.count(range) >= 3 ? 2 : 1))
                HStack(spacing: -8) {
                    ForEach(Array(people.enumerated()), id: \.offset) { i, p in
                        Lifter(kind: .of(p.parts.first ?? g.top.first), char: p.uid == gs.uid ? .mine : .from(p.a), t: t + Double(i) * 0.7, size: 34)
                    }
                    if people.isEmpty { Lifter(kind: .of(g.top.first), char: .boy, t: t, size: 34) }
                }
            }
            GymAvatar(url: g.cover, seed: g.id, size: 30, ring: true)
            Text(g.name).font(.system(size: 10, weight: .bold)).lineLimit(1).frame(maxWidth: 90)
                .padding(.horizontal, 6).padding(.vertical, 1).background(Capsule().fill(.black.opacity(0.55)))
        }
        .foregroundStyle(.white)
        .onTapGesture { Haptic.tap(); lastTouch = Date(); withAnimation(.snappy) { selected = g } }
    }

    private func card(_ g: GymInfo) -> some View {
        Button { open = g } label: {
            HStack(spacing: 12) {
                GymAvatar(url: g.cover, seed: g.id, size: 50, ring: true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(g.name).font(.headline).lineLimit(1)
                    Text([g.city, "本周 \(g.week) 人练过", g.top.first.map { "最多练\($0)" }].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(Color(hex: 0xa5a8c2)).lineLimit(1)
                }
                Spacer()
                Text("看看").font(.subheadline.bold()).padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(LinearGradient(colors: [Color(hex: 0xf58529), Color(hex: 0xdd2a7b)], startPoint: .leading, endPoint: .trailing)))
            }
            .foregroundStyle(.white)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.12)))
        }
        .buttonStyle(PressScale())
    }
}

struct Stars: View {
    var body: some View {
        Canvas { ctx, sz in
            var seed: UInt64 = 42
            func rnd() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 33) / Double(1 << 31) }
            for _ in 0..<90 {
                let x = rnd() * sz.width, y = rnd() * sz.height, s = 0.6 + rnd() * 1.2
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: s, height: s)), with: .color(.white.opacity(0.25 + rnd() * 0.5)))
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 首页右上角的小地球按钮（慢慢转，常去的健身房有新打卡亮小红点）
struct GlobeButton: View {
    @ObservedObject private var gs = GymStore.shared
    @State private var show = false
    var size: CGFloat = 38
    var body: some View {
        Button { Haptic.tap(); show = true } label: {
            TimelineView(.animation(minimumInterval: 1 / 15, paused: Motion.calm)) { tl in
                let spin = Motion.calm ? 0 : tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600) * 8
                GlobeBall(proj: GlobeProj(lon0: 112 - spin, lat0: 25, r: size / 2, c: CGPoint(x: size / 2, y: size / 2)),
                          dots: (gs.world?.gyms ?? []).prefix(30).map { ($0.lon, $0.lat) }, small: true)
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            .shadow(color: Color(hex: 0x8134af).opacity(0.45), radius: 6)
            .overlay(alignment: .topTrailing) {
                if gs.hasNew { Circle().fill(Color.red).frame(width: 11, height: 11).overlay(Circle().strokeBorder(.white, lineWidth: 2)).offset(x: 1, y: -1) }
            }
        }
        .buttonStyle(PressScale())
        .accessibilityLabel("打卡地球")
        .fullScreenCover(isPresented: $show) { GlobeScreen() }
        .task { await gs.refresh() }
    }
}

// 「我」页面里的两行：我的打卡小人、公开到打卡地球
struct MeLifterRow: View {
    @ObservedObject private var gs = GymStore.shared
    @State private var tick = 0
    var body: some View {
        NavigationLink {
            LifterPicker().onDisappear { tick += 1 }
        } label: {
            HStack {
                Label("我的打卡小人", systemImage: "figure.strengthtraining.traditional")
                Spacer()
                Lifter(kind: .squat, char: LifterChar.mine, t: 0.6, size: 24).id(tick)
                Text(LifterChar.mine.name).foregroundStyle(.secondary)
            }
        }
        Toggle(isOn: Binding(get: { gs.isPublic }, set: { gs.isPublic = $0 })) {
            Label("公开到打卡地球", systemImage: "globe.asia.australia.fill")
        }
        .tint(.green)
    }
}
