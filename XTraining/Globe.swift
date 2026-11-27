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

// MARK: - 卡通小人：按最常练的部位做动作，循环
enum LiftKind { case bench, squat, pull, run, press, curl
    static func of(_ part: String?) -> LiftKind {
        switch part {
        case "胸": return .bench
        case "背": return .pull
        case "有氧": return .run
        case "肩": return .press
        case "手臂": return .curl
        default: return .squat
        }
    }
}

struct Lifter: View {
    var kind: LiftKind
    var shirt: Color
    var t: Double          // 动画时间（秒）
    var size: CGFloat = 40
    var body: some View {
        Canvas { ctx, sz in
            let k = sz.width / 40
            ctx.scaleBy(x: k, y: k)
            let s = (1 - cos(t * 2.6)) / 2          // 0~1 循环
            let skin = Color(hex: 0xffd8b5), pants = Color(hex: 0x2b2d42), bar = Color(white: 0.85), plate = Color(hex: 0xff5c8a)
            func line(_ pts: [CGPoint], _ c: Color, _ w: CGFloat) {
                var p = Path(); p.addLines(pts); ctx.stroke(p, with: .color(c), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
            }
            func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ c: Color) { ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(c)) }
            func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ c: Color, _ rr: CGFloat = 2) { ctx.fill(Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: rr), with: .color(c)) }
            func head(_ x: CGFloat, _ y: CGFloat) { circle(x, y, 4.6, skin); var h = Path(); h.addArc(center: CGPoint(x: x, y: y - 0.5), radius: 4.8, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false); ctx.fill(h, with: .color(shirt.opacity(0.9))) }
            func barbell(_ y: CGFloat) { rect(2, y - 1.2, 36, 2.4, bar, 1); rect(1, y - 5, 4, 10, plate, 1.5); rect(35, y - 5, 4, 10, plate, 1.5) }
            let S = CGFloat(s)
            switch kind {
            case .squat:
                let d = 7 * S
                barbell(14 + d)
                head(20, 8 + d)
                rect(14, 14 + d, 12, 12 - 2 * S, shirt, 5)
                line([CGPoint(x: 16, y: 25 + d * 0.8), CGPoint(x: 11 - 2 * S, y: 33 + d * 0.3), CGPoint(x: 14, y: 42)], pants, 4)
                line([CGPoint(x: 24, y: 25 + d * 0.8), CGPoint(x: 29 + 2 * S, y: 33 + d * 0.3), CGPoint(x: 26, y: 42)], pants, 4)
            case .bench:
                rect(4, 31, 32, 3, Color(white: 0.55), 1.5)
                circle(9, 27, 4.2, skin)
                rect(12, 25, 16, 6, shirt, 3)
                rect(27, 26, 8, 4, pants, 2)
                let y = 9 + 8 * S
                line([CGPoint(x: 15, y: 25), CGPoint(x: 15, y: y)], skin, 3)
                line([CGPoint(x: 24, y: 25), CGPoint(x: 24, y: y)], skin, 3)
                barbell(y)
            case .pull:
                rect(2, 2, 36, 3, Color(white: 0.75), 1.5)
                let up = -7 * S
                line([CGPoint(x: 12, y: 4), CGPoint(x: 15, y: 16 + up)], skin, 3.2)
                line([CGPoint(x: 28, y: 4), CGPoint(x: 25, y: 16 + up)], skin, 3.2)
                head(20, 13 + up)
                rect(14, 18 + up, 12, 13, shirt, 5)
                line([CGPoint(x: 17, y: 30 + up), CGPoint(x: 16, y: 42 + up)], pants, 4)
                line([CGPoint(x: 23, y: 30 + up), CGPoint(x: 24, y: 42 + up)], pants, 4)
            case .run:
                let a = sin(t * 7), bob = CGFloat(abs(a)) * -1.5
                head(21, 8 + bob)
                ctx.drawLayer { l in
                    l.translateBy(x: 20, y: 20); l.rotate(by: .degrees(10)); l.translateBy(x: -20, y: -20)
                    l.fill(Path(roundedRect: CGRect(x: 14, y: 14 + bob, width: 12, height: 13), cornerRadius: 5), with: .color(shirt))
                }
                let A = CGFloat(a)
                line([CGPoint(x: 16, y: 17 + bob), CGPoint(x: 11 + 5 * A, y: 23 + bob)], skin, 3.2)
                line([CGPoint(x: 25, y: 17 + bob), CGPoint(x: 29 - 5 * A, y: 22 + bob)], skin, 3.2)
                line([CGPoint(x: 18, y: 27 + bob), CGPoint(x: 15 + 7 * A, y: 34), CGPoint(x: 12 + 9 * A, y: 41)], pants, 4)
                line([CGPoint(x: 22, y: 27 + bob), CGPoint(x: 25 - 7 * A, y: 34), CGPoint(x: 28 - 9 * A, y: 41)], pants, 4)
            case .press:
                let y = 15 - 12 * S
                head(20, 10)
                line([CGPoint(x: 15, y: 18), CGPoint(x: 11, y: (18 + y) / 2), CGPoint(x: 12, y: y)], skin, 3)
                line([CGPoint(x: 25, y: 18), CGPoint(x: 29, y: (18 + y) / 2), CGPoint(x: 28, y: y)], skin, 3)
                barbell(y)
                rect(14, 16, 12, 13, shirt, 5)
                line([CGPoint(x: 17, y: 28), CGPoint(x: 16, y: 42)], pants, 4)
                line([CGPoint(x: 23, y: 28), CGPoint(x: 24, y: 42)], pants, 4)
            case .curl:
                head(20, 9)
                rect(14, 15, 12, 13, shirt, 5)
                let ang = Double(S) * 2.2
                for (sx, dir) in [(CGFloat(15), CGFloat(-1)), (CGFloat(25), CGFloat(1))] {
                    let elbow = CGPoint(x: sx + dir * 1.5, y: 25)
                    let hand = CGPoint(x: elbow.x + dir * CGFloat(sin(ang)) * 2, y: elbow.y + CGFloat(cos(ang)) * 8)
                    line([CGPoint(x: sx, y: 17), elbow, hand], skin, 3)
                    rect(hand.x - 4, hand.y - 1.5, 8, 3, plate, 1.5)
                }
                line([CGPoint(x: 17, y: 28), CGPoint(x: 16, y: 42)], pants, 4)
                line([CGPoint(x: 23, y: 28), CGPoint(x: 24, y: 42)], pants, 4)
            }
        }
        .frame(width: size, height: size * 1.1)
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

    private var gyms: [GymInfo] { (gs.world?.gyms ?? []).filter { range == 2 ? $0.checkins > 0 : $0.count(range) > 0 } }

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
                    let figures = Set(ranked.prefix(zoom > 1.8 ? 16 : 8).map(\.id))
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
                Lifter(kind: .of(g.top.first), shirt: GymAvatar.palette(g.id)[0], t: t, size: 36)
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
