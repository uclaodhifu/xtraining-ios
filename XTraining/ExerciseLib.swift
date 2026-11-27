import SwiftUI

// MARK: 动作库：要领是自己写的，肌肉图用 App 自己画的人体图（不用来源不明的图片）
struct LibEx: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let part: String
    let assist: [String]     // 辅助发力的部位
    let equip: String
    let steps: [String]
    let tips: [String]
}

enum ExerciseLib {
    static func find(_ name: String) -> LibEx? {
        all.first { $0.name == name } ?? all.first { name.contains($0.name) || $0.name.contains(name) }
    }
    static let all: [LibEx] = [
        // 胸
        LibEx(name: "卧推", part: "胸", assist: ["肩", "手臂"], equip: "杠铃 · 平凳",
              steps: ["躺平，眼睛在杠下方，双脚踩实地面", "握距比肩宽一拳，肩胛骨往后下收紧，胸挺起", "吸气，杠慢慢落到乳头下沿，小臂保持垂直", "脚蹬地，呼气把杠推回起点"],
              tips: ["手肘和身体大约 45°，别完全打开", "臀部不要离开凳子"]),
        LibEx(name: "上斜卧推", part: "胸", assist: ["肩", "手臂"], equip: "杠铃/哑铃 · 上斜凳 30°",
              steps: ["凳子调到 30° 左右", "肩胛收紧，杠落在锁骨下方", "向上推到手臂接近伸直"],
              tips: ["角度太高会变成练肩", "下放控制 2 秒"]),
        LibEx(name: "哑铃卧推", part: "胸", assist: ["肩", "手臂"], equip: "哑铃 · 平凳",
              steps: ["哑铃放大腿上，躺下时顺势送到胸前", "掌心朝前，下放到胸两侧有拉伸感", "向上推并稍微向内合拢"],
              tips: ["比杠铃行程更大，重量先轻一点"]),
        LibEx(name: "蝴蝶机夹胸", part: "胸", assist: ["肩"], equip: "蝴蝶机",
              steps: ["座椅调到把手与胸同高", "手肘微屈固定，像抱大树一样向内合拢", "顶峰停 1 秒，慢慢打开"],
              tips: ["打开时别超过身体平面太多，保护肩"]),
        LibEx(name: "双杠臂屈伸", part: "胸", assist: ["手臂", "肩"], equip: "双杠",
              steps: ["撑起身体，手臂伸直", "身体略前倾，屈肘下放到大臂与地面平行", "推回起点"],
              tips: ["身体越前倾越练胸，越直越练三头", "肩不舒服就别放太深"]),
        LibEx(name: "绳索夹胸", part: "胸", assist: ["肩"], equip: "龙门架",
              steps: ["滑轮调到高位，一手一个把手，向前一步", "手肘微屈，向前下方合拢到腹前", "慢慢回到胸部打开"],
              tips: ["上身稳定，别靠身体前后晃"]),
        LibEx(name: "俯卧撑", part: "胸", assist: ["手臂", "肩"], equip: "徒手",
              steps: ["双手略宽于肩，身体从头到脚一条直线", "屈肘下放到胸接近地面", "推回起点"],
              tips: ["收紧腹部和臀部，别塌腰"]),
        // 肩
        LibEx(name: "推举", part: "肩", assist: ["手臂"], equip: "杠铃",
              steps: ["站立，杠放在锁骨前，握距略宽于肩", "收紧腹部和臀部", "把杠垂直推过头顶，头从两臂间穿出", "控制着放回锁骨"],
              tips: ["别后仰借力"]),
        LibEx(name: "哑铃推举", part: "肩", assist: ["手臂"], equip: "哑铃 · 凳子",
              steps: ["坐直，哑铃举到耳朵两侧", "向上推到手臂接近伸直", "慢慢放回耳侧"],
              tips: ["背靠稳，腰不要过度反弓"]),
        LibEx(name: "侧平举", part: "肩", assist: [], equip: "哑铃",
              steps: ["站立，哑铃垂在身体两侧，手肘微屈", "向两侧抬起到与肩同高", "顶峰停一下，慢慢放下"],
              tips: ["想象用手肘带动，不是用手", "重量轻一点，别耸肩"]),
        LibEx(name: "面拉", part: "肩", assist: ["背"], equip: "绳索",
              steps: ["滑轮调到脸的高度，双手反握绳子", "向脸部拉，手肘高于手腕，向两边分开", "顶峰时肩胛收紧，再慢慢回放"],
              tips: ["练后束和肩袖，对肩健康很好"]),
        LibEx(name: "反向飞鸟", part: "肩", assist: ["背"], equip: "哑铃/蝴蝶机",
              steps: ["俯身或坐在蝴蝶机上面朝机器", "手肘微屈，向两侧打开到与身体平齐", "慢慢回到起点"],
              tips: ["别用背去夹，感受肩后侧"]),
        LibEx(name: "前平举", part: "肩", assist: [], equip: "哑铃/杠铃片",
              steps: ["站立，重量放在大腿前", "手臂微屈向前抬到与肩同高", "慢慢放下"],
              tips: ["推类动作多的话，这个可以少练"]),
        // 背
        LibEx(name: "引体向上", part: "背", assist: ["手臂"], equip: "单杠",
              steps: ["握距比肩宽，悬挂时肩胛先往下沉", "用背把身体拉起，下巴过杠", "控制着下放到手臂伸直"],
              tips: ["拉不起来先用助力带或助力器械", "别荡身体"]),
        LibEx(name: "高位下拉", part: "背", assist: ["手臂"], equip: "下拉器械",
              steps: ["坐好压住大腿，握距比肩宽", "胸挺起，把杆拉到锁骨附近", "慢慢放回，感受背部拉长"],
              tips: ["手只是钩子，用手肘往下往后带"]),
        LibEx(name: "杠铃划船", part: "背", assist: ["手臂"], equip: "杠铃",
              steps: ["俯身约 45°，背挺直，膝盖微屈", "把杠拉向肚脐方向", "顶峰挤压背部，再慢慢放下"],
              tips: ["腰要保持中立，别弓背"]),
        LibEx(name: "坐姿划船", part: "背", assist: ["手臂"], equip: "划船器械",
              steps: ["坐直，双脚踩稳，抓住把手", "把把手拉向腹部，肩胛向后夹", "慢慢伸直手臂回去"],
              tips: ["上身别前后摇"]),
        LibEx(name: "硬拉", part: "背", assist: ["腿"], equip: "杠铃",
              steps: ["双脚与髋同宽，杠贴着小腿", "屈髋屈膝抓杠，背挺直，胸挺起", "脚蹬地，杠贴着腿往上拉到站直", "屈髋把杠沿着腿放回地面"],
              tips: ["全程背部中立，宁可轻一点", "不要在顶端后仰"]),
        LibEx(name: "单臂哑铃划船", part: "背", assist: ["手臂"], equip: "哑铃 · 平凳",
              steps: ["一手一膝撑在凳上，背平", "另一只手把哑铃拉向髋部", "慢慢放下到手臂伸直"],
              tips: ["往髋的方向拉，比往胸拉更练背阔"]),
        LibEx(name: "单臂下拉", part: "背", assist: ["手臂"], equip: "绳索",
              steps: ["单手握把手，身体侧对或面对器械", "手肘往下往身体侧边拉", "慢慢放回，背部充分拉伸"],
              tips: ["适合找背阔发力的感觉"]),
        LibEx(name: "T杠划船", part: "背", assist: ["手臂"], equip: "T 杠",
              steps: ["跨在杠两侧，俯身背挺直", "把杠拉向胸腹之间", "慢慢放下"],
              tips: ["窄握偏中背，宽握偏上背"]),
        // 腿
        LibEx(name: "深蹲", part: "腿", assist: ["背"], equip: "杠铃 · 深蹲架",
              steps: ["杠放在斜方肌上，双脚略宽于肩，脚尖微向外", "吸气收紧腹部，屈髋屈膝往下坐", "蹲到大腿至少与地面平行", "脚掌发力站起来"],
              tips: ["膝盖跟脚尖同一方向", "全程脚跟不离地"]),
        LibEx(name: "腿举", part: "腿", assist: [], equip: "腿举机",
              steps: ["背和臀贴紧靠垫，脚放在踏板中间", "放下到膝盖接近 90°", "蹬回去，膝盖别锁死"],
              tips: ["脚放高偏臀腿后侧，放低偏股四头"]),
        LibEx(name: "罗马尼亚硬拉", part: "腿", assist: ["背"], equip: "杠铃/哑铃",
              steps: ["站立持杠，膝盖微屈", "屈髋把臀往后送，杠沿着腿下滑", "大腿后侧有明显拉伸时，夹臀站起"],
              tips: ["练的是腘绳肌和臀，不是腰"]),
        LibEx(name: "臀推", part: "腿", assist: [], equip: "杠铃 · 平凳",
              steps: ["上背靠在凳边，杠放在髋部（垫个垫子）", "脚踩实，用臀把髋推起到身体成一条直线", "顶峰夹臀 1 秒，慢慢放下"],
              tips: ["下巴微收，别过度挺腰"]),
        LibEx(name: "腿弯举", part: "腿", assist: [], equip: "腿弯举机",
              steps: ["趴或坐在器械上，垫子压在脚踝上方", "屈膝把垫子勾向臀部", "慢慢放回"],
              tips: ["放回时控制速度"]),
        LibEx(name: "腿屈伸", part: "腿", assist: [], equip: "腿屈伸机",
              steps: ["坐好，垫子在脚踝前侧", "伸膝把腿抬直", "顶峰停 1 秒，慢慢放下"],
              tips: ["膝盖不舒服就减重、减小幅度"]),
        LibEx(name: "保加利亚分腿蹲", part: "腿", assist: [], equip: "哑铃 · 凳子",
              steps: ["后脚脚背放在凳子上，前脚向前一大步", "身体下沉到前腿大腿接近水平", "前脚发力站起"],
              tips: ["身体前倾多练臀，直立多练股四头"]),
        LibEx(name: "提踵", part: "腿", assist: [], equip: "器械/台阶",
              steps: ["前脚掌站在台阶边缘", "脚跟尽量往下放", "踮到最高，停 1 秒"],
              tips: ["小腿要全程幅度才有效"]),
        // 手臂
        LibEx(name: "二头弯举", part: "手臂", assist: [], equip: "杠铃/哑铃",
              steps: ["站立，掌心向前，大臂贴紧身体", "屈肘把重量举到肩前", "慢慢放下到手臂伸直"],
              tips: ["别甩身体，大臂别往前跑"]),
        LibEx(name: "锤式弯举", part: "手臂", assist: [], equip: "哑铃",
              steps: ["掌心相对握哑铃", "屈肘举到肩前", "慢慢放下"],
              tips: ["顺便练到小臂和肱肌，手臂看起来更粗"]),
        LibEx(name: "三头下压", part: "手臂", assist: [], equip: "绳索",
              steps: ["面对龙门架，大臂贴紧身体", "伸肘把把手压到大腿前", "慢慢回到小臂与地面平行"],
              tips: ["只动小臂，大臂不动"]),
        LibEx(name: "窄距卧推", part: "手臂", assist: ["胸"], equip: "杠铃 · 平凳",
              steps: ["握距与肩同宽", "杠落到胸下方，手肘贴近身体", "推起"],
              tips: ["握得太窄会伤手腕"]),
        LibEx(name: "过头臂屈伸", part: "手臂", assist: [], equip: "哑铃/绳索",
              steps: ["双手握哑铃举过头顶", "屈肘把哑铃放到脑后", "伸肘推回头顶"],
              tips: ["拉伸位练三头长头，效果好"]),
        // 腹肌
        LibEx(name: "卷腹", part: "腹肌", assist: [], equip: "徒手 · 垫子",
              steps: ["仰卧屈膝，双手放耳侧", "腹部发力把肩胛抬离地面", "停 1 秒，慢慢放下"],
              tips: ["别用手拉脖子，下巴和胸口留一拳"]),
        LibEx(name: "悬垂举腿", part: "腹肌", assist: [], equip: "单杠",
              steps: ["双手抓杠悬垂", "收腹把腿举到水平或更高", "慢慢放下，别晃"],
              tips: ["骨盆往上卷才练到下腹，只抬腿主要是髂腰肌"]),
        LibEx(name: "平板支撑", part: "腹肌", assist: ["肩"], equip: "徒手 · 垫子",
              steps: ["小臂撑地，肘在肩正下方", "身体从头到脚一条直线", "收紧腹部和臀部，保持"],
              tips: ["塌腰或撅屁股就停，质量比时间重要"]),
        LibEx(name: "健腹轮", part: "腹肌", assist: ["背", "肩"], equip: "健腹轮",
              steps: ["跪姿双手握轮", "腹部收紧慢慢往前推", "推到能控制的最远处，再收回来"],
              tips: ["腰不要塌，刚开始推短一点"]),
        LibEx(name: "绳索卷腹", part: "腹肌", assist: [], equip: "绳索",
              steps: ["跪在龙门架前，双手握绳放头两侧", "卷腹把手肘往大腿方向带", "慢慢回到起始"],
              tips: ["是脊柱往下卷，不是屁股往后坐"]),
        LibEx(name: "俄罗斯转体", part: "腹肌", assist: [], equip: "徒手/哑铃",
              steps: ["坐姿，身体稍后仰，双脚离地或踩地", "上身左右转动，手跟着到身体两侧", "左右算一次"],
              tips: ["转的是胸口，不只是甩手"]),
    ]
}

// 动作库列表
struct ExerciseLibView: View {
    @State private var q = ""
    var body: some View {
        List {
            ForEach(Parts.strength, id: \.self) { p in
                let xs = ExerciseLib.all.filter { $0.part == p && (q.isEmpty || $0.name.contains(q)) }
                if !xs.isEmpty {
                    Section {
                        ForEach(xs) { x in
                            NavigationLink { ExerciseDetail(ex: x) } label: {
                                HStack(spacing: 10) {
                                    Circle().fill(Parts.color(p)).frame(width: 8, height: 8)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(x.name).font(.subheadline.bold())
                                        Text(x.equip).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    } header: { Text(p) }
                }
            }
        }
        .searchable(text: $q, prompt: "搜动作")
        .navigationTitle("动作库")
    }
}

// 动作详情：练哪块（人体图高亮）、要领、注意、我的记录、看视频
struct ExerciseDetail: View {
    @EnvironmentObject var store: Store
    @Environment(\.openURL) private var openURL
    let ex: LibEx

    private var mine: [(String, Exercise)] {
        store.sorted.compactMap { w in w.exercises.first { $0.name == ex.name }.map { (w.date, $0) } }
    }

    var body: some View {
        let lv: (String) -> Double = { p in p == ex.part ? 1 : (ex.assist.contains(p) ? 0.35 : 0) }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // 肌肉图
                HStack(spacing: 18) {
                    VStack(spacing: 4) { BodyFigure(back: false, level: lv).frame(width: 100, height: 200); Text("正面").font(.caption2).foregroundStyle(.secondary) }
                    VStack(spacing: 4) { BodyFigure(back: true, level: lv).frame(width: 100, height: 200); Text("背面").font(.caption2).foregroundStyle(.secondary) }
                    VStack(alignment: .leading, spacing: 10) {
                        tag("主练", ex.part, Parts.color(ex.part))
                        if !ex.assist.isEmpty { tag("辅助", ex.assist.joined(separator: "、"), .secondary) }
                        tag("器械", ex.equip, .secondary)
                    }
                }
                .frame(maxWidth: .infinity).card()

                VStack(alignment: .leading, spacing: 10) {
                    Text("动作要领").font(.title3.bold())
                    ForEach(Array(ex.steps.enumerated()), id: \.offset) { i, s in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(i + 1)").font(.caption.bold()).foregroundStyle(.white)
                                .frame(width: 22, height: 22).background(Circle().fill(Parts.color(ex.part)))
                            Text(s).font(.subheadline)
                        }
                    }
                    if !ex.tips.isEmpty {
                        Divider()
                        ForEach(ex.tips, id: \.self) { t in
                            Label(t, systemImage: "exclamationmark.triangle.fill").font(.subheadline)
                                .symbolRenderingMode(.multicolor)
                        }
                    }
                }
                .card()

                VStack(alignment: .leading, spacing: 10) {
                    Text("我的记录").font(.title3.bold())
                    if mine.isEmpty {
                        Text("还没练过这个动作").font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        let best = mine.map { $0.1.best }.max() ?? 0
                        HStack {
                            StatTile(value: fmtNum(best) + WU.s, label: "最好成绩")
                            StatTile(value: "\(mine.count)", label: "练过次数")
                            StatTile(value: slashDate(mine[0].0), label: "上次")
                        }
                        ForEach(mine.prefix(3), id: \.0) { d, x in
                            HStack {
                                Text(slashDate(d)).font(.subheadline.bold()).monospacedDigit().frame(width: 56, alignment: .leading)
                                Text(setsText(x)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                }
                .card()

                VStack(alignment: .leading, spacing: 10) {
                    Text("看视频").font(.title3.bold())
                    Text("跳到抖音或 B 站搜这个动作的教学视频").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        videoButton("抖音", "play.rectangle.fill", .black,
                                    app: "snssdk1128://search?keyword=", web: "https://www.douyin.com/search/")
                        videoButton("B 站", "tv.fill", Color(hex: 0xfb7299),
                                    app: "bilibili://search?keyword=", web: "https://search.bilibili.com/all?keyword=")
                    }
                }
                .card()
            }
            .padding(16)
            .frame(maxWidth: 720).frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(ex.name)
    }

    private func tag(_ k: String, _ v: String, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(k).font(.caption2).foregroundStyle(.secondary)
            Text(v).font(.subheadline.bold()).foregroundStyle(c)
        }
    }

    private func videoButton(_ t: String, _ icon: String, _ c: Color, app: String, web: String) -> some View {
        Button {
            let q = (ex.name + " 教学").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            if let u = URL(string: app + q) {
                openURL(u) { ok in if !ok, let w = URL(string: web + q) { openURL(w) } }
            }
        } label: {
            Label(t, systemImage: icon).font(.subheadline.bold()).foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 40).background(Capsule().fill(c))
        }
        .buttonStyle(PressScale())
    }
}

// 从训练页点 ⓘ 打开
struct ExerciseInfoSheet: View {
    let ex: LibEx
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ExerciseDetail(ex: ex)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("好") { dismiss() }.bold() } }
        }
    }
}
