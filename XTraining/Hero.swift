import SwiftUI
import PhotosUI

// MARK: 首页顶部大卡片（像 Apple TV 主页那样左右滑），可以自定义
struct HeroItem: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var kind: String          // plan 今天练什么 / pr 个人纪录 / race 下一场比赛 / custom 自己的卡片
    var title = ""
    var sub = ""
    var img: Data? = nil
    var on = true

    static let defaults: [HeroItem] = [
        HeroItem(kind: "plan"), HeroItem(kind: "pr"), HeroItem(kind: "race"),
        HeroItem(kind: "custom", title: "练就完事了", sub: "点右上角铅笔，换成你自己的照片和口号"),
    ]
    var kindName: String {
        switch kind { case "plan": return "今天练什么"; case "pr": return "个人纪录"; case "race": return "下一场比赛"; default: return title.isEmpty ? "我的卡片" : title }
    }
}

func heroJPEG(_ img: UIImage, width: CGFloat = 900) -> Data? {
    let scale = min(1, width / max(img.size.width, 1))
    let size = CGSize(width: img.size.width * scale, height: img.size.height * scale)
    let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
    return UIGraphicsImageRenderer(size: size, format: fmt).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
        .jpegData(compressionQuality: 0.75)
}

struct HeroCarousel: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var feed = RaceFeed.shared
    let planTitle: String
    let planSub: String
    let partColor: Color
    var onStart: () -> Void
    @State private var page = 0
    @State private var editing = false

    private var items: [HeroItem] { store.hero.filter(\.on) }

    var body: some View {
        let list = items
        VStack(spacing: 10) {
            TabView(selection: $page) {
                ForEach(Array(list.enumerated()), id: \.element.id) { i, h in
                    card(h).tag(i).padding(.horizontal, 2)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 400)
            // 页码点：当前页拉长
            HStack(spacing: 6) {
                ForEach(list.indices, id: \.self) { i in
                    Capsule().fill(i == page ? Color.primary : Color.primary.opacity(0.25))
                        .frame(width: i == page ? 22 : 7, height: 7)
                }
            }
            .animation(.snappy, value: page)
        }
        .overlay(alignment: .topTrailing) {
            Button { editing = true } label: {
                Image(systemName: "pencil").font(.footnote.bold()).foregroundStyle(.white)
                    .frame(width: 34, height: 34).background(.ultraThinMaterial, in: Circle())
            }
            .padding(14)
        }
        .sheet(isPresented: $editing) { HeroEditor() }
        .task(id: list.count) {
            // 自动轮播（减弱动态效果时不动）
            guard !Motion.calm, list.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(6))
                withAnimation(.easeInOut(duration: 0.6)) { page = (page + 1) % max(list.count, 1) }
            }
        }
        .onChange(of: list.count) { _, n in if page >= n { page = 0 } }
    }

    @ViewBuilder private func card(_ h: HeroItem) -> some View {
        switch h.kind {
        case "plan":
            shell(h, tint: partColor, tag: "今日训练", title: planTitle, sub: planSub, button: "开始训练", action: onStart)
        case "pr":
            let pr = latestPR()
            shell(h, tint: Color(hex: 0xb8860b), tag: "个人纪录",
                  title: pr.map { "\($0.0) \(fmtNum($0.1))\(WU.s)" } ?? "还没有纪录",
                  sub: pr.map { $0.2.isEmpty ? "目前最重的一次" : "\(slashDate($0.2)) 破纪录，继续冲" } ?? "练几次，这里会显示你最新的突破",
                  button: nil, action: {})
        case "race":
            let r = nextRace()
            shell(h, tint: r.map { $0.poster.1 } ?? Color(hex: 0x3b5bdb), tag: "下一场比赛",
                  title: r?.name ?? "暂无比赛",
                  sub: r.map { e in
                      let n = e.date.map { Day.between(Day.today, $0) } ?? 0
                      return (n <= 0 ? "今天开赛" : "还有 \(n) 天") + " · " + e.timeText
                  } ?? "去“追赛”里追几场比赛",
                  button: nil, action: {})
        default:
            shell(h, tint: Brand.pink, tag: nil, title: h.title, sub: h.sub, button: nil, action: {})
        }
    }

    private func shell(_ h: HeroItem, tint: Color, tag: String?, title: String, sub: String, button: String?, action: @escaping () -> Void) -> some View {
        ZStack(alignment: .bottomLeading) {
            // 背景：自己的照片，没有就用深色渐变
            Group {
                if let d = h.img, let ui = UIImage(data: d) {
                    Image(uiImage: ui).resizable().scaledToFill()
                } else {
                    ZStack {
                        Color(hex: 0x111114)
                        RadialGradient(colors: [tint.opacity(0.85), .clear], center: .topTrailing, startRadius: 10, endRadius: 420)
                        RadialGradient(colors: [tint.opacity(0.35), .clear], center: .bottomLeading, startRadius: 10, endRadius: 360)
                        Text("X").font(.system(size: 300, weight: .black)).italic()
                            .foregroundStyle(.white.opacity(0.06)).offset(x: 90, y: -40)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 8) {
                if let tag { Text(tag).font(.caption.bold()).foregroundStyle(.white.opacity(0.75)).textCase(.uppercase) }
                Text(title.isEmpty ? " " : (h.kind == "custom" ? title : (h.title.isEmpty ? title : h.title)))
                    .font(.system(size: 38, weight: .heavy)).foregroundStyle(.white)
                    .lineLimit(2).minimumScaleFactor(0.6)
                Text(h.kind != "custom" && !h.sub.isEmpty ? h.sub : sub)
                    .font(.subheadline).foregroundStyle(.white.opacity(0.85)).lineLimit(2)
                if let button {
                    Button(action: action) {
                        Label(button, systemImage: "play.fill").font(.headline).foregroundStyle(.black)
                            .padding(.horizontal, 26).padding(.vertical, 12)
                            .background(Capsule().fill(.white))
                    }
                    .buttonStyle(PressScale()).padding(.top, 6)
                }
            }
            .padding(22)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 14, y: 8)
    }

    private func latestPR() -> (String, Double, String)? {
        var best: [String: Double] = [:]; var last: (String, Double, String)? = nil
        for w in store.workouts.sorted(by: { $0.date < $1.date }) {
            for x in w.exercises where !x.isCardio && x.best > 0 {
                if let o = best[x.name] { if x.best > o { last = (x.name, x.best, w.date); best[x.name] = x.best } }
                else { best[x.name] = x.best }
            }
        }
        if last == nil, let m = best.max(by: { $0.value < $1.value }) { return (m.key, m.value, "") }
        return last
    }
    private func nextRace() -> Race? {
        let up = Race.upcoming().filter { $0.date != nil }
        return up.first { store.follow.contains($0.id) } ?? up.first
    }
}

// 编辑卡片：开关、排序、换照片、改文字、加自己的卡片
struct HeroEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var editingID: String? = nil

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach($store.hero) { $h in
                        HStack(spacing: 12) {
                            thumb(h)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(h.kindName).font(.subheadline.bold())
                                Text(h.kind == "custom" ? (h.sub.isEmpty ? "自己的卡片" : h.sub) : "自动显示").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Toggle("", isOn: $h.on).labelsHidden()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { editingID = h.id }
                    }
                    .onMove { store.hero.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { idx in store.hero.remove(atOffsets: idx) }
                } footer: {
                    Text("点一张卡片可以换背景照片、改标题。按住右边拖动可以排序，左滑删除。")
                }
                Section {
                    Button { let h = HeroItem(kind: "custom", title: "新卡片"); store.hero.append(h); editingID = h.id } label: {
                        Label("加一张自己的卡片", systemImage: "plus.circle.fill")
                    }
                    Button("恢复默认", role: .destructive) { store.hero = HeroItem.defaults }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("首页大卡片").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() }.bold() } }
            .sheet(item: Binding(get: { editingID.map(StrID.init) }, set: { editingID = $0?.id })) { s in
                if let i = store.hero.firstIndex(where: { $0.id == s.id }) { HeroCardEditor(item: $store.hero[i]) }
            }
        }
    }

    private func thumb(_ h: HeroItem) -> some View {
        Group {
            if let d = h.img, let ui = UIImage(data: d) { Image(uiImage: ui).resizable().scaledToFill() }
            else { LinearGradient(colors: [Color(hex: 0x2c2c2e), Color(hex: 0x111114)], startPoint: .top, endPoint: .bottom) }
        }
        .frame(width: 44, height: 56).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct HeroCardEditor: View {
    @Binding var item: HeroItem
    @Environment(\.dismiss) private var dismiss
    @State private var pick: PhotosPickerItem? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section("背景照片") {
                    PhotosPicker(selection: $pick, matching: .images) {
                        Label(item.img == nil ? "选一张照片" : "换一张照片", systemImage: "photo")
                    }
                    if item.img != nil { Button("去掉照片", role: .destructive) { item.img = nil } }
                }
                Section {
                    TextField(item.kind == "custom" ? "标题" : "标题（不填就自动显示）", text: $item.title)
                    TextField(item.kind == "custom" ? "一句话" : "小字（不填就自动显示）", text: $item.sub)
                } header: { Text("文字") }
            }
            .navigationTitle(item.kindName).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() }.bold() } }
            .onChange(of: pick) { _, p in
                Task {
                    if let d = try? await p?.loadTransferable(type: Data.self), let ui = UIImage(data: d) { item.img = heroJPEG(ui) }
                }
            }
        }
    }
}
