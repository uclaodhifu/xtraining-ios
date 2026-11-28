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

// 地球上标的城市名：1 = 默认就显示，2 = 双指放大后才显示（坐标用国内地图坐标，和健身房一致）
enum GlobeCities {
    static let all: [(name: String, lon: Double, lat: Double, tier: Int)] = [
        ("北京", 116.40, 39.90, 1), ("上海", 121.47, 31.23, 1), ("广州", 113.26, 23.13, 1), ("深圳", 114.06, 22.54, 2),
        ("成都", 104.07, 30.67, 1), ("重庆", 106.55, 29.56, 2), ("西安", 108.94, 34.34, 1), ("武汉", 114.31, 30.59, 1),
        ("哈尔滨", 126.63, 45.75, 1), ("沈阳", 123.43, 41.80, 2), ("长春", 125.32, 43.82, 2), ("乌鲁木齐", 87.62, 43.83, 1),
        ("拉萨", 91.11, 29.65, 1), ("昆明", 102.83, 24.88, 1), ("大理", 100.23, 25.61, 2), ("南宁", 108.37, 22.82, 2),
        ("贵阳", 106.63, 26.65, 2), ("长沙", 112.94, 28.23, 2), ("南昌", 115.86, 28.68, 2), ("杭州", 120.16, 30.27, 2),
        ("南京", 118.80, 32.06, 2), ("合肥", 117.23, 31.82, 2), ("福州", 119.30, 26.08, 2), ("厦门", 118.09, 24.48, 2),
        ("郑州", 113.63, 34.75, 2), ("济南", 117.00, 36.67, 2), ("青岛", 120.38, 36.07, 2), ("天津", 117.20, 39.13, 2),
        ("石家庄", 114.51, 38.04, 2), ("太原", 112.55, 37.87, 2), ("呼和浩特", 111.75, 40.84, 2), ("兰州", 103.83, 36.06, 2),
        ("西宁", 101.78, 36.62, 2), ("银川", 106.23, 38.49, 2), ("海口", 110.35, 20.02, 2), ("三亚", 109.51, 18.25, 2),
        ("台北", 121.56, 25.04, 1), ("香港", 114.17, 22.32, 1), ("澳门", 113.54, 22.19, 2), ("大连", 121.61, 38.91, 2),
        ("苏州", 120.59, 31.30, 2), ("宁波", 121.55, 29.87, 2), ("东莞", 113.75, 23.02, 2), ("佛山", 113.12, 23.02, 2),
        ("东京", 139.69, 35.69, 1), ("首尔", 126.98, 37.57, 1), ("新加坡", 103.82, 1.35, 1), ("曼谷", 100.50, 13.76, 1),
        ("乌兰巴托", 106.91, 47.92, 1), ("大阪", 135.50, 34.69, 2), ("河内", 105.85, 21.03, 2), ("马尼拉", 120.98, 14.60, 2),
        ("吉隆坡", 101.69, 3.14, 2), ("新德里", 77.21, 28.61, 1), ("迪拜", 55.27, 25.20, 1), ("莫斯科", 37.62, 55.75, 1),
        ("伦敦", -0.13, 51.51, 1), ("巴黎", 2.35, 48.86, 1), ("柏林", 13.40, 52.52, 2), ("罗马", 12.50, 41.90, 2),
        ("纽约", -74.01, 40.71, 1), ("洛杉矶", -118.24, 34.05, 1), ("旧金山", -122.42, 37.77, 2), ("温哥华", -123.12, 49.28, 2),
        ("多伦多", -79.38, 43.65, 2), ("悉尼", 151.21, -33.87, 1), ("墨尔本", 144.96, -37.81, 2), ("圣保罗", -46.63, -23.55, 1),
    ]
    // 健身房名字下面显示的城市：优先用表里的城市名，没有就去掉“市/自治州”等后缀
    static func short(_ g: GymInfo) -> String {
        if let c = all.first(where: { !g.city.isEmpty && g.city.hasPrefix($0.name) }) { return c.name }
        if let c = all.min(by: { hypot($0.lon - g.lon, $0.lat - g.lat) < hypot($1.lon - g.lon, $1.lat - g.lat) }),
           hypot(c.lon - g.lon, c.lat - g.lat) < 0.6 { return c.name }
        var s = g.city
        for suf in ["白族自治州", "自治州", "地区", "盟", "市"] where s.hasSuffix(suf) && s.count > suf.count + 1 { s = String(s.dropLast(suf.count)); break }
        return s
    }
}

// 放大到城市后显示的区县名（大致中心点，国内地图坐标）
enum GlobeDistricts {
    static let all: [(name: String, lon: Double, lat: Double)] = [
        // 北京
        ("东城区", 116.42, 39.93), ("西城区", 116.37, 39.91), ("朝阳区", 116.49, 39.95), ("海淀区", 116.30, 39.96), ("丰台区", 116.29, 39.86),
        ("石景山区", 116.22, 39.91), ("通州区", 116.66, 39.91), ("顺义区", 116.65, 40.13), ("昌平区", 116.23, 40.22), ("大兴区", 116.34, 39.73),
        ("房山区", 116.14, 39.75), ("门头沟区", 116.10, 39.94), ("怀柔区", 116.63, 40.32), ("平谷区", 117.12, 40.14), ("密云区", 116.84, 40.38), ("延庆区", 115.97, 40.46),
        // 上海
        ("黄浦区", 121.49, 31.23), ("徐汇区", 121.44, 31.19), ("长宁区", 121.42, 31.22), ("静安区", 121.45, 31.24), ("普陀区", 121.40, 31.25),
        ("虹口区", 121.50, 31.26), ("杨浦区", 121.53, 31.26), ("浦东新区", 121.57, 31.22), ("闵行区", 121.38, 31.11), ("宝山区", 121.49, 31.40),
        ("嘉定区", 121.27, 31.38), ("松江区", 121.23, 31.03), ("青浦区", 121.12, 31.15), ("奉贤区", 121.47, 30.92), ("金山区", 121.34, 30.74),
        // 广州
        ("越秀区", 113.27, 23.13), ("天河区", 113.36, 23.12), ("海珠区", 113.32, 23.08), ("荔湾区", 113.24, 23.11), ("白云区", 113.27, 23.18),
        ("番禺区", 113.38, 22.94), ("黄埔区", 113.46, 23.11), ("花都区", 113.22, 23.40), ("南沙区", 113.53, 22.80), ("增城区", 113.81, 23.26),
        // 深圳
        ("福田区", 114.05, 22.54), ("罗湖区", 114.13, 22.55), ("南山区", 113.93, 22.53), ("宝安区", 113.88, 22.56), ("龙岗区", 114.25, 22.72),
        ("龙华区", 114.04, 22.69), ("盐田区", 114.24, 22.56), ("光明区", 113.94, 22.75), ("坪山区", 114.35, 22.69),
        // 长沙
        ("岳麓区", 112.93, 28.23), ("芙蓉区", 113.03, 28.19), ("天心区", 112.99, 28.11), ("开福区", 112.99, 28.26), ("雨花区", 113.04, 28.13),
        ("望城区", 112.82, 28.35), ("长沙县", 113.08, 28.25),
        // 厦门
        ("思明区", 118.08, 24.45), ("湖里区", 118.15, 24.51), ("集美区", 118.10, 24.58), ("海沧区", 118.03, 24.48), ("同安区", 118.15, 24.72), ("翔安区", 118.25, 24.62),
        // 成都
        ("锦江区", 104.08, 30.66), ("青羊区", 104.06, 30.67), ("金牛区", 104.05, 30.69), ("武侯区", 104.04, 30.64), ("成华区", 104.10, 30.66),
        ("双流区", 103.92, 30.57), ("郫都区", 103.90, 30.80), ("温江区", 103.84, 30.69), ("龙泉驿区", 104.27, 30.56), ("新都区", 104.16, 30.82),
        // 杭州
        ("上城区", 120.17, 30.25), ("拱墅区", 120.14, 30.32), ("西湖区", 120.13, 30.26), ("滨江区", 120.21, 30.21), ("萧山区", 120.26, 30.18),
        ("余杭区", 120.30, 30.42), ("钱塘区", 120.49, 30.30),
        // 武汉
        ("江岸区", 114.31, 30.60), ("江汉区", 114.27, 30.60), ("硚口区", 114.21, 30.58), ("汉阳区", 114.22, 30.55), ("武昌区", 114.32, 30.55),
        ("洪山区", 114.34, 30.50), ("青山区", 114.39, 30.63), ("东西湖区", 114.14, 30.62), ("江夏区", 114.32, 30.38), ("黄陂区", 114.38, 30.88),
        // 南京
        ("玄武区", 118.80, 32.05), ("秦淮区", 118.79, 32.03), ("鼓楼区", 118.77, 32.07), ("建邺区", 118.73, 32.00), ("栖霞区", 118.88, 32.10),
        ("雨花台区", 118.78, 31.99), ("江宁区", 118.84, 31.95), ("浦口区", 118.63, 32.06),
        // 西安
        ("新城区", 108.96, 34.27), ("碑林区", 108.94, 34.25), ("莲湖区", 108.93, 34.27), ("雁塔区", 108.95, 34.22), ("未央区", 108.95, 34.31),
        ("灞桥区", 109.06, 34.27), ("长安区", 108.91, 34.16),
        // 重庆
        ("渝中区", 106.57, 29.55), ("江北区", 106.57, 29.61), ("南岸区", 106.56, 29.52), ("沙坪坝区", 106.46, 29.54), ("九龙坡区", 106.51, 29.50),
        ("渝北区", 106.63, 29.72), ("大渡口区", 106.48, 29.48), ("巴南区", 106.54, 29.40), ("北碚区", 106.40, 29.81),
        // 天津
        ("和平区", 117.20, 39.12), ("河西区", 117.22, 39.10), ("南开区", 117.15, 39.14), ("河东区", 117.25, 39.13), ("河北区", 117.20, 39.15),
        ("红桥区", 117.15, 39.17), ("滨海新区", 117.70, 39.03), ("西青区", 117.01, 39.14), ("津南区", 117.36, 38.94), ("东丽区", 117.31, 39.09), ("北辰区", 117.13, 39.22),
        // 郑州
        ("金水区", 113.66, 34.80), ("中原区", 113.61, 34.75), ("二七区", 113.64, 34.73), ("管城区", 113.68, 34.75), ("惠济区", 113.62, 34.87), ("郑东新区", 113.73, 34.77),
        // 苏州
        ("姑苏区", 120.62, 31.31), ("工业园区", 120.72, 31.32), ("虎丘区", 120.57, 31.30), ("吴中区", 120.63, 31.26), ("相城区", 120.64, 31.37), ("吴江区", 120.64, 31.16),
        // 青岛
        ("市南区", 120.41, 36.07), ("市北区", 120.37, 36.09), ("李沧区", 120.43, 36.15), ("崂山区", 120.47, 36.11), ("黄岛区", 120.20, 35.96), ("城阳区", 120.40, 36.31),
        // 哈尔滨
        ("道里区", 126.62, 45.76), ("南岗区", 126.67, 45.76), ("道外区", 126.65, 45.79), ("香坊区", 126.68, 45.71), ("松北区", 126.56, 45.81),
        ("平房区", 126.64, 45.60), ("呼兰区", 126.59, 45.89),
        // 大理、衢州、濮阳
        ("下关", 100.24, 25.59), ("大理古城", 100.16, 25.69),
        ("柯城区", 118.87, 28.94), ("衢江区", 118.96, 28.98), ("常山县", 118.51, 28.90), ("江山市", 118.63, 28.74), ("龙游县", 119.17, 29.03),
        ("华龙区", 115.07, 35.78), ("濮阳县", 115.03, 35.71),
    ]
}

// 城市名图层：白色小字，转到边缘淡出，和健身房、其他城市名挤在一起时自动让开
struct GlobeCityLabels: View {
    var proj: GlobeProj
    var zoom: Double
    var avoid: [CGRect]              // 健身房头像和名字占的地方
    var skip: [(Double, Double)]     // 有健身房的地方（城市名已写在健身房名字下面）
    var body: some View {
        Canvas { ctx, size in
            var used = avoid
            for c in GlobeCities.all where c.tier == 1 || zoom > 1.8 {
                if skip.contains(where: { hypot($0.0 - c.lon, $0.1 - c.lat) < 0.6 }) { continue }
                let dep = proj.depth(c.lon, c.lat)
                if dep < 0.2 { continue }
                let pt = proj.p(c.lon, c.lat).0
                let fs: CGFloat = c.tier == 1 ? 11 : 10
                let box = CGRect(x: pt.x - 2, y: pt.y - fs / 2 - 2, width: CGFloat(c.name.count) * fs + 10, height: fs + 4)
                if used.contains(where: { $0.intersects(box) }) { continue }
                used.append(box)
                var l = ctx
                l.opacity = min(1, (dep - 0.2) * 3)
                l.fill(Path(ellipseIn: CGRect(x: pt.x - 1.8, y: pt.y - 1.8, width: 3.6, height: 3.6)), with: .color(Color(hex: 0xe8ebff)))
                let txt = Text(c.name).font(.system(size: fs, weight: .semibold)).foregroundColor(Color(hex: 0xdfe3ff).opacity(0.85))
                var sh = l
                sh.addFilter(.shadow(color: Color(hex: 0x0b0f33).opacity(0.9), radius: 1.5))
                sh.draw(txt, at: CGPoint(x: pt.x + 5, y: pt.y), anchor: .leading)
            }
            // 放大到城市：标出各个区
            guard zoom > GlobeScreen.districtZoom else { return }
            for d in GlobeDistricts.all {
                let dep = proj.depth(d.lon, d.lat)
                if dep < 0.5 { continue }
                let pt = proj.p(d.lon, d.lat).0
                if pt.x < -60 || pt.y < -20 || pt.x > size.width + 20 || pt.y > size.height + 20 { continue }
                let fs: CGFloat = 11
                let w = CGFloat(d.name.count) * fs + 8
                let box = CGRect(x: pt.x - w / 2, y: pt.y - fs / 2 - 2, width: w, height: fs + 4)
                if used.contains(where: { $0.intersects(box) }) { continue }
                used.append(box)
                var l = ctx
                l.opacity = min(1, (zoom - GlobeScreen.districtZoom) / 20)
                l.addFilter(.shadow(color: Color(hex: 0x0b0f33).opacity(0.9), radius: 1.5))
                l.draw(Text(d.name).font(.system(size: fs, weight: .medium)).foregroundColor(Color(hex: 0xc9cffc).opacity(0.75)), at: pt, anchor: .center)
            }
        }
        .allowsHitTesting(false)
    }
}

// 地球本体（海 + 陆地 + 经纬线 + 大气光）
struct GlobeBall: View {
    var proj: GlobeProj
    var dots: [(Double, Double)] = []
    var small = false
    var flat = false      // 放大到城市时：粗略的海岸线会画歪，干脆整块当陆地
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
            if flat {
                ctx.fill(disk, with: .color(Color(hex: 0x4f5fb8)))
                ctx.fill(disk, with: .radialGradient(Gradient(colors: [.clear, .clear, .black.opacity(0.35)]), center: c, startRadius: 0, endRadius: r))
                return
            }
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

// 放大到城市后的背景：满屏小圆点，健身房附近（练的人越多范围越大）点变亮变粉
struct CityDots: View {
    var proj: GlobeProj
    var heat: [(CGPoint, Double)]   // 健身房屏幕位置 + 人数
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: 0x0b0d24)))
            let step: CGFloat = 13
            // 点阵跟着地图走：以一个固定经纬度为锚点对齐
            let a = proj.p(112, 28).0
            let ox = a.x.truncatingRemainder(dividingBy: step), oy = a.y.truncatingRemainder(dividingBy: step)
            var y = oy - step
            while y < size.height + step {
                var x = ox - step
                while x < size.width + step {
                    var h = 0.0
                    for (p, c) in heat {
                        let d = Double(hypot(p.x - x, p.y - y))
                        h += max(0, 1 - d / (70 + c * 30)) * (0.6 + c * 0.3)
                    }
                    h = min(1, h)
                    let r = 1.1 + h * 1.6
                    let col = h > 0.05 ? Color(red: (90 + 165 * h) / 255, green: 100 / 255, blue: (200 - 40 * h) / 255) : Color(hex: 0x2a2f66)
                    ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(col.opacity(0.55 + h * 0.45)))
                    x += step
                }
                y += step
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 打卡地球页面
// 挤在一起的健身房合成一个泡泡（圈里是练过人最多那家的照片），点泡泡或点城市名就转过去放大
struct GymCluster: Identifiable {
    var gyms: [GymInfo]
    var pt: CGPoint
    var lon: Double
    var lat: Double
    var dep: Double
    var id: String { gyms.map(\.id).sorted().joined(separator: ",") }
}

struct GlobeScreen: View {
    static let maxZoom = 400.0
    static let districtZoom = 40.0
    static let flatZoom = 20.0

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
    @State private var fly: Fly? = nil
    @State private var focus: (name: String, lon: Double, lat: Double)? = nil
    @State private var stack: [GymInfo]? = nil        // 放到最大还叠在一起的（同一个位置），列出来选
    @State private var size = CGSize(width: 390, height: 700)

    struct Fly { var from: (Double, Double, Double); var to: (Double, Double, Double); var start: Date; var dur: Double }

    // 所有健身房都上地球（后台新建、还没人打卡的也显示头像），有人打卡的才站小人
    private var gyms: [GymInfo] { gs.world?.gyms ?? [] }
    private var baseR: Double { min(size.width * 0.6, size.height * 0.5) }
    private var center: CGPoint { CGPoint(x: size.width / 2, y: size.height * 0.52) }

    // 现在实际看到的角度和缩放（飞行动画中途用插值）
    private func cam(at now: Date) -> (Double, Double, Double) {
        guard let f = fly, !Motion.calm else { return (lon0, lat0, zoom) }
        let p = min(1, max(0, now.timeIntervalSince(f.start) / f.dur))
        let e = p < 0.5 ? 4 * p * p * p : 1 - pow(-2 * p + 2, 3) / 2
        return (f.from.0 + (f.to.0 - f.from.0) * e, f.from.1 + (f.to.1 - f.from.1) * e, exp(log(f.from.2) + (log(f.to.2) - log(f.from.2)) * e))
    }
    private func spinning(_ now: Date) -> Bool { now.timeIntervalSince(lastTouch) > 4 && selected == nil && !Motion.calm && zoom < 1.5 && fly == nil }
    private func projection(_ now: Date) -> GlobeProj {
        let v = cam(at: now)
        let spin = spinning(now) ? now.timeIntervalSince(max(spinBase, lastTouch.addingTimeInterval(4))) * 2.5 : 0
        return GlobeProj(lon0: v.0 - spin, lat0: v.1, r: baseR * v.2, c: center)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                TimelineView(.animation(minimumInterval: 1 / 30, paused: Motion.calm)) { tl in
                    let now = tl.date
                    let proj = projection(now)
                    let z = proj.r / baseR
                    let t = now.timeIntervalSinceReferenceDate
                    let clusters = Self.cluster(gyms, proj: proj)
                    let singles = clusters.filter { $0.gyms.count == 1 }.map { $0.gyms[0] }
                    let figures = Set(singles.filter { $0.count(range) > 0 }.sorted { $0.count(range) > $1.count(range) }.prefix(z > 1.8 ? 16 : 8).map(\.id))
                    ZStack {
                        GlobeBall(proj: proj, flat: z > Self.flatZoom)
                        if z > Self.flatZoom {
                            CityDots(proj: proj, heat: clusters.flatMap { c in c.gyms.map { (proj.p($0.lon, $0.lat).0, Double(min(6, $0.count(range)))) } })
                                .opacity(min(1, (z - Self.flatZoom) / 15))
                        }
                        GlobeCityLabels(proj: proj, zoom: z,
                                        avoid: clusters.map { c -> CGRect in
                                            let tall = c.gyms.count > 1 || figures.contains(c.gyms[0].id)
                                            let hgt: CGFloat = tall ? 124 : 80
                                            return CGRect(x: c.pt.x - 52, y: c.pt.y - 30 - hgt / 2, width: 104, height: hgt)
                                        },
                                        skip: clusters.map { ($0.lon, $0.lat) })
                        ForEach(clusters.sorted { $0.dep < $1.dep }) { c in
                            Group {
                                if c.gyms.count == 1 {
                                    pin(c.gyms[0], figure: figures.contains(c.gyms[0].id), t: t + Double(abs(c.gyms[0].id.hashValue % 100)) / 10)
                                } else {
                                    bubble(c, t: t)
                                }
                            }
                            .scaleEffect(0.7 + 0.3 * c.dep, anchor: .bottom)
                            .opacity(min(1, (c.dep - 0.15) * 4))
                            .position(x: c.pt.x, y: c.pt.y - 30)
                        }
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { v in
                            if dragStart == nil { grab(); dragStart = (lon0, lat0) }
                            let k = 180 / (.pi * baseR * zoom)
                            lon0 = dragStart!.0 - v.translation.width * k
                            lat0 = min(80, max(-80, dragStart!.1 + v.translation.height * k))
                            lastTouch = Date()
                        }
                        .onEnded { _ in dragStart = nil; lastTouch = Date() }
                        .simultaneously(with: MagnificationGesture()
                            .onChanged { m in
                                if zoomStart == nil { grab(); zoomStart = zoom }
                                zoom = min(Self.maxZoom, max(0.7, zoomStart! * m)); lastTouch = Date()
                                if zoom < 1.3 { focus = nil }
                            }
                            .onEnded { _ in zoomStart = nil; lastTouch = Date() })
                )
                .onTapGesture(coordinateSpace: .local) { loc in tapMap(loc) }
                .onAppear { size = geo.size }
                .onChange(of: geo.size) { _, s in size = s }
            }
            .ignoresSafeArea(edges: .bottom)
            .background(
                ZStack {
                    RadialGradient(colors: [Color(hex: 0x1b1f3b), Color(hex: 0x05060f)], center: UnitPoint(x: 0.5, y: 0.3), startRadius: 0, endRadius: 600)
                    Stars()
                }.ignoresSafeArea()
            )
            .safeAreaInset(edge: .top) { header }
            .overlay(alignment: .bottom) {
                if let list = stack { stackCard(list).padding(.horizontal, 14).padding(.bottom, 20).transition(.move(edge: .bottom).combined(with: .opacity)) }
                else if let g = selected { card(g).padding(.horizontal, 14).padding(.bottom, 20).transition(.move(edge: .bottom).combined(with: .opacity)) }
            }
            .overlay(alignment: .bottomLeading) {
                if zoom > 1.5 {
                    Button { Haptic.tap(); flyTo(lon: lon0, lat: lat0, zoom: 1); focus = nil } label: {
                        Label("回到整个地球", systemImage: "arrow.counterclockwise").font(.footnote.bold()).foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 9).background(.ultraThinMaterial, in: Capsule())
                    }
                    .padding(.leading, 18).padding(.bottom, selected != nil || stack != nil ? 110 : 24)
                    .transition(.opacity)
                }
            }
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

    // 屏幕上离得近（会叠在一起）的健身房连成一组
    static func cluster(_ gyms: [GymInfo], proj: GlobeProj) -> [GymCluster] {
        let vis = gyms.compactMap { g -> (GymInfo, CGPoint, Double)? in
            let d = proj.depth(g.lon, g.lat)
            guard d > 0.15 else { return nil }
            return (g, proj.p(g.lon, g.lat).0, d)
        }
        let n = vis.count
        var parent = Array(0..<n)
        func find(_ i: Int) -> Int { var i = i; while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }; return i }
        for i in 0..<n { for j in (i + 1)..<max(i + 1, n) where hypot(vis[i].1.x - vis[j].1.x, vis[i].1.y - vis[j].1.y) < 70 { parent[find(i)] = find(j) } }
        var groups: [Int: [Int]] = [:]
        for i in 0..<n { groups[find(i), default: []].append(i) }
        return groups.values.map { idx in
            let k = Double(idx.count)
            return GymCluster(gyms: idx.map { vis[$0].0 },
                              pt: CGPoint(x: idx.reduce(0) { $0 + vis[$1].1.x } / k, y: idx.reduce(0) { $0 + vis[$1].1.y } / k),
                              lon: idx.reduce(0) { $0 + vis[$1].0.lon } / k, lat: idx.reduce(0) { $0 + vis[$1].0.lat } / k,
                              dep: idx.map { vis[$0].2 }.max() ?? 1)
        }
    }

    // 手一碰就停下自动旋转/飞行，把当前看到的角度存下来，不会跳
    private func grab() {
        let now = Date()
        if fly != nil { let v = cam(at: now); lon0 = v.0; lat0 = v.1; zoom = v.2; fly = nil }
        else if spinning(now) { lon0 -= now.timeIntervalSince(max(spinBase, lastTouch.addingTimeInterval(4))) * 2.5 }
        spinBase = now
        lastTouch = now
    }

    private func flyTo(lon: Double, lat: Double, zoom z: Double) {
        grab()
        var tl = lon
        while tl - lon0 > 180 { tl -= 360 }
        while tl - lon0 < -180 { tl += 360 }
        let to = (tl, max(-80, min(80, lat)), min(Self.maxZoom, max(0.7, z)))
        fly = Fly(from: (lon0, lat0, zoom), to: to, start: Date(), dur: 0.9)
        lon0 = to.0; lat0 = to.1; zoom = to.2
        lastTouch = Date()
    }

    // 点空白处：点到城市名就飞过去，否则收起卡片
    private func tapMap(_ loc: CGPoint) {
        let proj = projection(Date()), z = proj.r / baseR
        var best: (name: String, lon: Double, lat: Double, d: CGFloat)? = nil
        for c in GlobeCities.all where (c.tier == 1 || z > 1.8) && proj.depth(c.lon, c.lat) > 0.2 {
            let pt = proj.p(c.lon, c.lat).0
            let box = CGRect(x: pt.x - 14, y: pt.y - 16, width: CGFloat(c.name.count) * 11 + 28, height: 32)
            guard box.contains(loc) else { continue }
            let d = hypot(loc.x - pt.x, loc.y - pt.y)
            if best == nil || d < best!.d { best = (c.name, c.lon, c.lat, d) }
        }
        if let b = best {
            Haptic.tap()
            withAnimation(.snappy) { selected = nil; stack = nil }
            focus = (b.name, b.lon, b.lat)
            flyTo(lon: b.lon, lat: b.lat, zoom: max(zoom * 1.5, 110))
        } else {
            withAnimation(.snappy) { selected = nil; stack = nil }
        }
    }

    // 点泡泡：放大到这几家刚好分得开；已经放到最大还分不开（同一个位置）就列出来选
    private func tapCluster(_ c: GymCluster) {
        Haptic.tap()
        let m = cos(c.lat * .pi / 180)
        var spread = 0.0
        for a in c.gyms { for b in c.gyms { spread = max(spread, hypot((a.lon - b.lon) * m, a.lat - b.lat)) } }
        let need = spread > 0 ? 150 / (spread * .pi / 180) / baseR : .infinity
        if need > Self.maxZoom * 0.98 && zoom > Self.maxZoom * 0.5 || spread < 0.0005 {
            withAnimation(.snappy) { selected = nil; stack = c.gyms.sorted { $0.count(range) > $1.count(range) } }
            if spread < 0.0005 && zoom < 60 { flyTo(lon: c.lon, lat: c.lat, zoom: max(zoom * 1.5, 110)) }
            return
        }
        withAnimation(.snappy) { selected = nil; stack = nil }
        let cities = Set(c.gyms.map { GlobeCities.short($0) }).filter { !$0.isEmpty }
        if cities.count == 1, let name = cities.first { focus = (name, c.lon, c.lat) }
        flyTo(lon: c.lon, lat: c.lat, zoom: max(zoom * 1.8, min(need, Self.maxZoom)))
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
        if let f = focus, zoom > 1.5 {
            let n = w.gyms.filter { hypot($0.lon - f.lon, $0.lat - f.lat) < 0.8 }.count
            return n > 0 ? "\(f.name) · \(n) 家健身房" : "\(f.name) · 还没有健身房"
        }
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
            let city = GlobeCities.short(g)
            if !city.isEmpty && zoom < Self.districtZoom {
                Text(city).font(.system(size: 12, weight: .heavy)).foregroundStyle(Color(hex: 0xffd1e6))
                    .shadow(color: Color(hex: 0x0b0f33).opacity(0.9), radius: 1.5)
            }
        }
        .foregroundStyle(.white)
        .onTapGesture { Haptic.tap(); lastTouch = Date(); withAnimation(.snappy) { stack = nil; selected = g } }
    }

    // 泡泡：圈里是这一片练过人最多那家的照片，角上写几家，头顶站最近打卡的 3 个小人
    private func bubble(_ c: GymCluster, t: Double) -> some View {
        let top = c.gyms.max { ($0.count(range), $0.checkins) < ($1.count(range), $1.checkins) } ?? c.gyms[0]
        let ppl = c.gyms.reduce(0) { $0 + $1.count(range) }
        var seen = Set<String>()
        let people = c.gyms.flatMap { g in g.recent.map { (g, $0) } }.sorted { $0.1.t > $1.1.t }.filter { seen.insert($0.1.uid).inserted }.prefix(3)
        let cities = Array(Set(c.gyms.map { GlobeCities.short($0) }).filter { !$0.isEmpty }).sorted()
        return VStack(spacing: 2) {
            if ppl > 0 && !people.isEmpty {
                HStack(alignment: .bottom, spacing: -8) {
                    ForEach(Array(people.enumerated()), id: \.offset) { i, x in
                        Lifter(kind: .of(x.1.parts.first ?? x.0.top.first), char: x.1.uid == gs.uid ? .mine : .from(x.1.a), t: t + Double(i) * 0.7, size: 30)
                    }
                    if ppl > people.count {
                        Text("+\(ppl - people.count)").font(.system(size: 11, weight: .heavy)).foregroundStyle(Color(hex: 0xffd1e6)).padding(.leading, 10).padding(.bottom, 14)
                    }
                }
            }
            ZStack(alignment: .topTrailing) {
                Circle().fill(Color(hex: 0xdd2a7b).opacity(0.22)).frame(width: 56, height: 56)
                GymAvatar(url: top.cover, seed: top.id, size: 44, ring: true).frame(width: 56, height: 56)
                Text("\(c.gyms.count)").font(.system(size: 12, weight: .heavy)).foregroundStyle(.white)
                    .padding(.horizontal, 5).frame(minWidth: 22, minHeight: 22)
                    .background(Capsule().fill(Color(hex: 0xdd2a7b))).overlay(Capsule().strokeBorder(.white, lineWidth: 1.5))
                    .offset(x: 6, y: -4)
            }
            Text("\(c.gyms.count) 家 · \(ppl) 人练过").font(.system(size: 10, weight: .bold)).lineLimit(1)
                .padding(.horizontal, 7).padding(.vertical, 2).background(Capsule().fill(.black.opacity(0.55)))
            if !cities.isEmpty && zoom < Self.districtZoom {
                Text(cities.count > 2 ? cities.prefix(2).joined(separator: "·") + " 等" : cities.joined(separator: "·"))
                    .font(.system(size: 12, weight: .heavy)).foregroundStyle(Color(hex: 0xffd1e6)).lineLimit(1)
                    .shadow(color: Color(hex: 0x0b0f33).opacity(0.9), radius: 1.5)
            }
        }
        .foregroundStyle(.white)
        .contentShape(Rectangle())
        .onTapGesture { tapCluster(c) }
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

    // 同一个位置的几家健身房：列出来点
    private func stackCard(_ list: [GymInfo]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("这里有 \(list.count) 家健身房").font(.subheadline.bold()).foregroundStyle(Color(hex: 0xa5a8c2)).padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 4)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(list) { g in
                        Button { open = g } label: {
                            HStack(spacing: 10) {
                                GymAvatar(url: g.cover, seed: g.id, size: 36, ring: true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(g.name).font(.subheadline.bold()).lineLimit(1)
                                    Text("\(["本周", "本月", "一共"][range]) \(g.count(range)) 人练过").font(.caption).foregroundStyle(Color(hex: 0xa5a8c2))
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary)
                            }
                            .foregroundStyle(.white).padding(.horizontal, 14).padding(.vertical, 8).contentShape(Rectangle())
                        }
                        .buttonStyle(PressScale())
                    }
                }
            }
            .frame(maxHeight: 220)
        }
        .padding(.bottom, 6)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.12)))
        .fixedSize(horizontal: false, vertical: true)
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
        MeNav {
            LifterPicker().onDisappear { tick += 1 }
        } label: {
            HStack {
                Label("我的打卡小人", systemImage: "figure.strengthtraining.traditional")
                Spacer()
                Lifter(kind: .squat, char: LifterChar.mine, t: 0.6, size: 24).id(tick)
                Text(LifterChar.mine.name).foregroundStyle(.secondary)
            }
        }
        MeDivider()
        Toggle(isOn: Binding(get: { gs.isPublic }, set: { gs.isPublic = $0 })) {
            Label("公开到打卡地球", systemImage: "globe.asia.australia.fill")
        }
        .tint(.green)
        .meRow()
    }
}
