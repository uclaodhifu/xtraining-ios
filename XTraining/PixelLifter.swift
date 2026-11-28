import SwiftUI
import UIKit

// MARK: - 像素风打卡小人（8-bit）：28x30 格子，大头身，自动黑描边，动作一格一格跳帧

struct Px { let x: Int; let y: Int; let c: UInt32 }

enum PixelArt {
    static let ol: UInt32 = 0x1d1b2e
    static let skin: UInt32 = 0xffd8b5
    // 格子范围（画布按这个缩放）：x -1...29，y -4...30
    static let minX = -1, maxX = 29, minY = -4, maxY = 30

    // 照片头的圆（格子坐标，已含 ox）
    static let photoC = (x: 13.5, y: 6.5, r: 6.6)

    private static var cache: [String: [Px]] = [:]

    // 画到 Canvas 上
    static func render(_ ctx: inout GraphicsContext, _ sz: CGSize, char: LifterChar, kind: LiftKind, t: Double, photo: UIImage?) {
        let fps: Double = kind == .run ? 6 : 3
        let f: Int = Int(floor(t * fps)) & 1
        let gw: CGFloat = CGFloat(maxX - minX)
        let gh: CGFloat = CGFloat(maxY - minY)
        let k: CGFloat = min(sz.width / gw, sz.height / gh)
        let ox: CGFloat = (sz.width - gw * k) / 2 - CGFloat(minX) * k
        let oy: CGFloat = (sz.height - gh * k) - CGFloat(minY) * k
        // 地上的影子（跳起来时变小）
        let sw: CGFloat = (kind == .jump && f == 1) ? 9 : 13
        let shadow = CGRect(x: ox + (16 - sw / 2) * k, y: oy + 28 * k, width: sw * k, height: k)
        ctx.fill(Path(shadow), with: .color(.black.opacity(0.18)))
        var groups: [UInt32: Path] = [:]
        let e: CGFloat = k * 0.04   // 稍微盖一点，避免格子缝
        for p in sprite(char, kind, f) {
            let rc = CGRect(x: ox + CGFloat(p.x) * k, y: oy + CGFloat(p.y) * k, width: k + e, height: k + e)
            groups[p.c, default: Path()].addRect(rc)
        }
        for (c, path) in groups { ctx.fill(path, with: .color(Color(hex: c))) }
        guard char == .photo, let photo else { return }
        // 照片像素化后盖在白圈里面
        var lift: CGFloat = 0
        if kind == .squat && f == 1 { lift = 3 } else if kind == .jump && f == 1 { lift = -3 } else if kind == .run && f == 0 { lift = -1 }
        let r: CGFloat = CGFloat(photoC.r)
        let cx: CGFloat = CGFloat(photoC.x) + 0.5, cy: CGFloat = CGFloat(photoC.y) + 0.5 + lift
        let box = CGRect(x: ox + (cx - r) * k, y: oy + (cy - r) * k, width: 2 * r * k, height: 2 * r * k)
        var c2 = ctx
        c2.clip(to: Path(ellipseIn: box))
        c2.draw(Image(uiImage: PixelPhoto.small(photo)).interpolation(.none), in: box)
    }

    static func sprite(_ c: LifterChar, _ k: LiftKind, _ f: Int) -> [Px] {
        let key = "\(c.rawValue)-\(k)-\(f)"
        if let s = cache[key] { return s }
        var g = Grid()
        draw(&g, c, k, f)
        g.outline()
        let s = g.p.map { Px(x: $0.key.x, y: $0.key.y, c: $0.value) }
        cache[key] = s
        return s
    }

    struct P: Hashable { let x: Int; let y: Int }
    struct Grid {
        var p: [P: UInt32] = [:]
        var ox = 2, oy = 0
        mutating func r(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: UInt32) {
            guard w > 0, h > 0 else { return }
            for i in x..<(x + w) { for j in y..<(y + h) { p[P(x: i + ox, y: j + oy)] = c } }
        }
        mutating func d(_ x: Int, _ y: Int, _ c: UInt32) { p[P(x: x + ox, y: y + oy)] = c }
        mutating func outline() {
            var add: [P: UInt32] = [:]
            for q in p.keys {
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let n = P(x: q.x + dx, y: q.y + dy)
                    if p[n] == nil { add[n] = PixelArt.ol }
                }
            }
            p.merge(add) { a, _ in a }
        }
    }

    static func dark(_ c: UInt32, _ k: Double = 0.72) -> UInt32 {
        let r = Double((c >> 16) & 0xff) * k, g = Double((c >> 8) & 0xff) * k, b = Double(c & 0xff) * k
        return (UInt32(r) << 16) | (UInt32(g) << 8) | UInt32(b)
    }
    static func light(_ c: UInt32, _ k: Double = 0.35) -> UInt32 {
        func m(_ v: UInt32) -> UInt32 { let x = Double(v); return UInt32(x + (255 - x) * k) }
        return (m((c >> 16) & 0xff) << 16) | (m((c >> 8) & 0xff) << 8) | m(c & 0xff)
    }

    struct Look { let shirt: UInt32, pants: UInt32, sole: UInt32, arm: UInt32, big: Int }
    static func look(_ c: LifterChar) -> Look {
        switch c {
        case .boy: return Look(shirt: 0xff7a00, pants: 0x2b2d42, sole: 0xff7a00, arm: skin, big: 0)
        case .girl: return Look(shirt: 0xe64980, pants: 0x343a40, sole: 0xe64980, arm: skin, big: 0)
        case .bald: return Look(shirt: 0x2f9e44, pants: 0x212529, sole: 0x2f9e44, arm: 0xf2c39b, big: 1)
        case .cap: return Look(shirt: 0xfab005, pants: 0x1864ab, sole: 0x1864ab, arm: skin, big: 0)
        case .panda: return Look(shirt: 0x222222, pants: 0x222222, sole: 0x51cf66, arm: 0x333333, big: 0)
        case .robot: return Look(shirt: 0xadb5bd, pants: 0x495057, sole: 0x4dd4ff, arm: 0xced4da, big: 0)
        case .blogger: return Look(shirt: 0x1a1a1a, pants: 0x3a3a3c, sole: 0xff3b5c, arm: 0xe9b48a, big: 1)
        case .photo: return Look(shirt: 0xdd2a7b, pants: 0x2b2d42, sole: 0xdd2a7b, arm: skin, big: 0)
        }
    }

    // 招牌姿势（「挥手」= 没练具体部位时的待机动作，用每个人自己的招牌姿势）
    enum Sig { case double, hip, peace, selfie }
    static func sig(_ c: LifterChar) -> Sig {
        switch c { case .girl, .photo: return .hip; case .cap: return .peace; case .blogger: return .selfie; default: return .double }
    }

    // MARK: 画
    static func draw(_ g: inout Grid, _ c: LifterChar, _ k: LiftKind, _ f: Int) {
        let L = look(c), A = L.arm, P = L.pants, T = L.shirt, b = L.big
        var dy = 0           // 上半身往下移（深蹲）
        var jump = 0         // 整个人往上（跳）

        // —— 腿 + 鞋 ——
        func shoe(_ x: Int, _ y: Int) { g.r(x, y, 4, 2, 0xffffff); g.r(x, y + 1, 4, 1, L.sole) }
        func legsStand() {
            g.r(9, 21, 2, 4, P); g.r(13, 21, 2, 4, P); g.r(10, 21, 1, 4, dark(P, 0.8)); g.r(14, 21, 1, 4, dark(P, 0.8))
            shoe(7, 25); shoe(13, 25)
        }
        switch k {
        case .squat:
            if f == 1 {
                dy = 3
                g.r(7, 23, 4, 2, P); g.r(13, 23, 4, 2, P); g.r(10, 23, 1, 2, dark(P, 0.8))
                shoe(5, 25); shoe(15, 25)
            } else { legsStand() }
        case .jack:
            if f == 1 {
                g.r(8, 21, 2, 2, P); g.r(7, 23, 2, 2, P); g.r(14, 21, 2, 2, P); g.r(15, 23, 2, 2, P)
                shoe(4, 25); shoe(16, 25)
            } else { legsStand() }
        case .run:
            let s = f == 0 ? 1 : -1
            g.r(9, 21, 2, 2, P); g.r(13, 21, 2, 2, P)
            g.r(11 - 4 * s - (s > 0 ? 0 : 0), 23, 2, 2, P); g.r(11 + 2 * s + (s > 0 ? 0 : 1), 23, 2, 2, P)
            shoe(9 - 5 * s, 25); shoe(11 + 3 * s, 25)
        case .jump:
            if f == 1 { jump = 3; g.oy = -3 }
            if f == 1 {
                g.r(9, 21, 2, 3, P); g.r(13, 21, 2, 3, P); shoe(7, 24); shoe(13, 24)
            } else { legsStand() }
        default: legsStand()
        }

        // —— 身子 ——
        g.oy = dy - jump
        g.r(7 - b, 13, 10 + 2 * b, 3, T); g.r(8 - b / 2, 16, 8 + b, 3, T); g.r(9, 19, 6, 2, T)
        g.r(16 + b, 13, 1, 3, dark(T)); g.r(15 + b / 2, 16, 1, 3, dark(T)); g.r(14, 19, 1, 2, dark(T))
        g.r(8 - b, 13, 2, 2, light(T))
        torsoDetail(&g, c)

        // —— 手臂 ——
        func flexL(_ up: Int) {
            g.r(2 - b, 14, 6, 2, A); g.r(3 - b, 12 - up, 3, 2 + up, A); g.d(4 - b, 12 - up, light(A))
            g.r(1 - b, 8 - up, 2, 6, A); g.r(0 - b, 5 - up, 3, 3, A); g.d(1 - b, 13, dark(A))
        }
        func flexR(_ up: Int) {
            g.r(16 + b, 14, 6, 2, A); g.r(18 + b, 12 - up, 3, 2 + up, A); g.d(19 + b, 12 - up, light(A))
            g.r(21 + b, 8 - up, 2, 6, A); g.r(21 + b, 5 - up, 3, 3, A); g.r(22 + b, 9 - up, 1, 5, dark(A))
        }
        func downL() { g.r(4 - b, 14, 3, 2, A); g.r(3 - b, 16, 2, 4, A); g.r(3 - b, 20, 2, 2, A) }
        func downR() { g.r(17 + b, 14, 3, 2, A); g.r(19 + b, 16, 2, 4, A); g.r(19 + b, 20, 2, 2, A) }
        func hipL() { g.r(4, 14, 3, 2, A); g.r(3, 16, 2, 3, A); g.r(4, 19, 3, 2, A) }
        func upL() { g.r(4 - b, 13, 3, 2, A); g.r(2 - b, 9, 2, 4, A); g.r(1 - b, 6, 3, 3, A) }
        func upR() { g.r(17 + b, 13, 3, 2, A); g.r(20 + b, 9, 2, 4, A); g.r(20 + b, 6, 3, 3, A) }
        func forward() {
            g.r(1 - b, 14, 6, 2, A); g.r(-1 - b, 13, 3, 3, A)
            g.r(17 + b, 14, 6, 2, A); g.r(22 + b, 13, 3, 3, A)
        }
        switch k {
        case .squat: if f == 1 { forward() } else { downL(); downR() }
        case .flex: if f == 0 { flexL(0); flexR(1) } else { flexL(1); flexR(0); g.r(3 - b, 10, 3, 1, A); g.r(18 + b, 10, 3, 1, A) }
        case .jack: if f == 1 { upL(); upR() } else { downL(); downR() }
        case .jump: upL(); upR()
        case .run:
            if f == 0 { g.r(4, 14, 3, 2, A); g.r(2, 12, 2, 3, A); g.r(17, 14, 3, 2, A); g.r(20, 16, 2, 3, A) }
            else { g.r(4, 14, 3, 2, A); g.r(3, 16, 2, 3, A); g.r(17, 14, 3, 2, A); g.r(20, 12, 2, 3, A) }
        case .wave:
            switch sig(c) {
            case .double: flexL(f); flexR(1 - f)
            case .hip: hipL(); flexR(f)
            case .peace:
                g.r(4, 14, 3, 2, A); g.r(3, 16, 2, 4, A); g.r(3, 20, 2, 2, A)
                g.r(16, 14, 5, 2, A); g.r(20, 8 - f, 2, 6 + f, A); g.r(20, 5 - f, 3, 3, A); g.r(20, 2 - f, 1, 3, A); g.r(22, 2 - f, 1, 3, A)
            case .selfie:
                flexL(f); g.r(16 + b, 14, 5, 2, A); g.r(20 + b, 7, 2, 7, A); g.r(20 + b, 5, 3, 2, A)
                g.r(21 + b, 2, 1, 3, 0x555555); g.r(19 + b, -3, 5, 5, 0x2c2c2e); g.d(20 + b, -2, 0x4dd4ff)
            }
        }
        if c == .bald, k == .flex || (k == .wave && sig(c) == .double) {  // 护腕
            g.r(1 - b, 11 - (k == .flex ? f : f), 2, 1, 0x2f9e44)
        }

        // —— 头（跳/深蹲跟着身子动；跑步头往前探一点）——
        g.oy = dy - jump + (k == .run ? (f == 0 ? -1 : 0) : 0)
        head(&g, c)
    }

    static func torsoDetail(_ g: inout Grid, _ c: LifterChar) {
        switch c {
        case .boy: g.r(11, 15, 1, 3, 0xffffff); g.r(13, 15, 1, 3, 0xffffff); g.d(12, 15, 0xffffff); g.d(12, 17, 0xffffff)
        case .girl: g.r(8, 14, 8, 2, 0x212529)
        case .bald: g.r(6, 13, 2, 2, 0xf2c39b); g.r(16, 13, 2, 2, 0xf2c39b); g.r(10, 16, 4, 1, 0xffffff)
        case .cap: g.d(10, 13, 0xffd700); g.d(11, 14, 0xffd700); g.d(12, 14, 0xffd700); g.d(13, 13, 0xffd700); g.r(11, 17, 2, 2, 0x1864ab)
        case .panda: g.r(9, 15, 6, 5, 0xffffff); g.r(7, 13, 10, 1, 0x69db7c); g.r(15, 14, 1, 3, 0x69db7c)
        case .robot: g.r(11, 15, 2, 2, 0x4dd4ff); g.d(10, 16, 0xa5f0ff); g.d(13, 16, 0xa5f0ff)
        case .blogger: g.r(7, 13, 2, 2, 0xe9b48a); g.r(15, 13, 2, 2, 0xe9b48a); g.r(10, 16, 4, 1, 0xff3b5c)
        case .photo: g.r(10, 18, 4, 1, 0xc2255c); g.d(11, 14, 0xffffff); g.d(12, 14, 0xffffff)
        }
    }

    static func head(_ g: inout Grid, _ c: LifterChar) {
        let O = ol
        func eyes(_ y: Int, _ kind: Int = 0) {   // 0 普通 1 眨眼 2 眯眼 3 瞪眼
            switch kind {
            case 1: g.r(9, y + 1, 2, 1, O); g.r(13, y, 2, 2, O); g.d(13, y, 0xffffff)
            case 2: g.r(9, y + 1, 2, 1, O); g.r(13, y + 1, 2, 1, O)
            case 3: g.r(9, y, 2, 2, O); g.r(13, y, 2, 2, O); g.d(8, y - 1, O); g.d(15, y - 1, O)
            default: g.r(9, y, 2, 2, O); g.r(13, y, 2, 2, O); g.d(9, y, 0xffffff); g.d(13, y, 0xffffff)
            }
        }
        func blush(_ y: Int) { g.d(7, y, 0xff8fa3); g.d(16, y, 0xff8fa3) }
        func grin(_ y: Int) { g.r(10, y, 4, 1, O); g.r(10, y + 1, 4, 1, 0xe03131); g.r(11, y, 2, 1, 0xffffff) }
        switch c {
        case .boy:
            g.r(6, 2, 12, 10, skin); g.r(6, 1, 12, 3, 0x3b2314); g.r(5, 2, 1, 4, 0x3b2314); g.r(18, 2, 1, 4, 0x3b2314)
            g.d(8, 4, 0x3b2314); g.d(12, 4, 0x3b2314); g.d(15, 4, 0x3b2314)
            g.r(5, 0, 14, 1, 0x1c7ed6); g.r(4, 5, 2, 4, 0x1c7ed6); g.r(18, 5, 2, 4, 0x1c7ed6)
            eyes(6); blush(9); grin(9)
        case .girl:
            g.r(18, 3, 3, 7, 0x7a4321); g.r(20, 8, 2, 3, 0x7a4321)
            g.r(6, 2, 12, 10, skin); g.r(6, 1, 12, 3, 0x7a4321); g.r(5, 2, 1, 6, 0x7a4321); g.r(6, 2, 12, 1, 0xffffff); g.r(17, 1, 2, 2, 0xff5c8a)
            eyes(6, 1); blush(9); g.r(10, 9, 4, 1, O); g.d(12, 10, 0xff8fa3)
        case .bald:
            g.r(5, 1, 14, 11, 0xf2c39b); g.r(7, 2, 3, 1, 0xfff3e6); g.r(6, 9, 12, 3, 0x5a3a22); g.r(8, 12, 8, 1, 0x5a3a22)
            eyes(5, 3); g.r(10, 9, 4, 2, 0xffffff); g.d(11, 9, O); g.d(12, 10, O); g.d(18, 4, 0x74c0fc); g.d(18, 5, 0x74c0fc)
        case .cap:
            g.r(6, 3, 12, 9, skin); g.r(6, 0, 12, 4, 0x1c7ed6); g.r(16, 2, 5, 2, 0x1c7ed6); g.r(10, 1, 2, 2, 0xffffff)
            eyes(6, 2); blush(9); grin(9)
        case .panda:
            g.r(5, 0, 3, 3, 0x222222); g.r(16, 0, 3, 3, 0x222222); g.r(6, 2, 12, 10, 0xffffff)
            g.r(8, 5, 3, 3, 0x222222); g.r(13, 5, 3, 3, 0x222222); g.d(9, 5, 0xffffff); g.d(14, 5, 0xffffff)
            g.r(11, 9, 2, 1, 0x222222); blush(9); g.r(11, 10, 2, 2, O)
        case .robot:
            g.d(12, -2, 0xff5c8a); g.r(12, -1, 1, 2, 0x868e96)
            g.r(6, 1, 12, 11, 0xdee2e6); g.r(7, 4, 10, 4, 0x212529); g.r(8, 5, 2, 1, 0x4dd4ff); g.r(14, 5, 2, 1, 0x4dd4ff)
            g.d(9, 6, 0x4dd4ff); g.d(15, 6, 0x4dd4ff); g.r(5, 5, 1, 3, 0x868e96); g.r(18, 5, 1, 3, 0x868e96); g.r(10, 9, 4, 1, 0x4dd4ff); g.r(7, 2, 2, 1, 0xffffff)
        case .blogger:
            g.r(6, 2, 12, 10, 0xe9b48a); g.r(6, 1, 12, 3, 0x1a1a1a); g.r(5, 3, 14, 1, 0xff3b5c); g.d(5, 2, 0xff3b5c)
            g.r(7, 6, 4, 2, 0x111111); g.r(13, 6, 4, 2, 0x111111); g.r(11, 6, 2, 1, 0x111111); g.d(8, 6, 0x888888); g.d(14, 6, 0x888888)
            g.r(11, 10, 3, 1, O); g.d(14, 9, O)
        case .photo:
            // 白圈 + 里面先填皮肤色占位（描边才能算对），真照片画的时候盖上去
            for x in 4..<20 { for y in 0..<14 {
                let d = pow(Double(x) - 11.5, 2) + pow(Double(y) - 6.5, 2)
                if d <= 7.6 * 7.6 { g.d(x, y, d <= 6.6 * 6.6 ? 0xf1c9a5 : 0xffffff) }
            } }
        }
    }
}

// 照片 → 14x14 小图（像素化），缓存
enum PixelPhoto {
    private static var cache: [ObjectIdentifier: UIImage] = [:]
    static func small(_ img: UIImage) -> UIImage {
        let id = ObjectIdentifier(img)
        if let s = cache[id] { return s }
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let n: CGFloat = 14
        let out = UIGraphicsImageRenderer(size: CGSize(width: n, height: n), format: fmt).image { _ in
            let s = min(img.size.width, img.size.height)
            let k = n / s
            img.draw(in: CGRect(x: -(img.size.width - s) / 2 * k, y: -(img.size.height - s) / 2 * k, width: img.size.width * k, height: img.size.height * k))
        }
        if cache.count > 60 { cache.removeAll() }
        cache[id] = out
        return out
    }
}
