import SwiftUI
import PhotosUI

// 备赛体态照：按日期存在本机（App 文档目录），不上传；选两张左右或拖动对比
struct BodyPhoto: Codable, Identifiable, Hashable {
    var id = UUID()
    var date = Day.today
    var pose = "正面"
    var note = ""
}

@MainActor
final class PhotoStore: ObservableObject {
    static let shared = PhotoStore()
    static let poses = ["正面", "侧面", "背面", "规定动作"]
    @Published var list: [BodyPhoto] = UserDefaults.standard.data(forKey: "xt.bodyPhotos")
        .flatMap { try? JSONDecoder().decode([BodyPhoto].self, from: $0) } ?? [] {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(list), forKey: "xt.bodyPhotos") }
    }
    private var dir: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("physique", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    func url(_ p: BodyPhoto) -> URL { dir.appendingPathComponent(p.id.uuidString + ".jpg") }
    func image(_ p: BodyPhoto) -> UIImage? { UIImage(contentsOfFile: url(p).path) }

    func add(_ data: Data, date: String, pose: String) {
        guard let ui = UIImage(data: data) else { return }
        // 长边缩到 1600，省空间
        let k = min(1, 1600 / max(ui.size.width, ui.size.height))
        let size = CGSize(width: ui.size.width * k, height: ui.size.height * k)
        let small = UIGraphicsImageRenderer(size: size).image { _ in ui.draw(in: CGRect(origin: .zero, size: size)) }
        let p = BodyPhoto(date: date, pose: pose)
        try? small.jpegData(compressionQuality: 0.85)?.write(to: url(p))
        list.append(p)
    }
    func delete(_ p: BodyPhoto) {
        try? FileManager.default.removeItem(at: url(p))
        list.removeAll { $0.id == p.id }
    }
}

struct PhysiqueView: View {
    @ObservedObject private var st = PhotoStore.shared
    @ObservedObject private var ps = PrepStore.shared
    @State private var picks: [PhotosPickerItem] = []
    @State private var addDate = Date()
    @State private var addPose = "正面"
    @State private var pose = "全部"
    @State private var selected: [UUID] = []
    @State private var comparing = false
    @State private var viewing: BodyPhoto? = nil

    private var shown: [BodyPhoto] {
        st.list.filter { pose == "全部" || $0.pose == pose }.sorted { $0.date > $1.date }
    }
    private var groups: [(String, [BodyPhoto])] {
        Dictionary(grouping: shown, by: \.date).sorted { $0.key > $1.key }.map { ($0.key, $0.value) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // 加照片
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        DatePicker("拍摄日期", selection: $addDate, in: ...Date(), displayedComponents: .date)
                    }
                    Picker("姿势", selection: $addPose) { ForEach(PhotoStore.poses, id: \.self) { Text($0).tag($0) } }
                        .pickerStyle(.segmented)
                    PhotosPicker(selection: $picks, maxSelectionCount: 6, matching: .images) {
                        Label("从相册加照片", systemImage: "photo.badge.plus").font(.subheadline.bold())
                            .frame(maxWidth: .infinity, minHeight: 42).foregroundStyle(.white)
                            .background(Capsule().fill(Brand.gradient))
                    }
                    Text("照片只存在这台手机上，不会上传。").font(.caption2).foregroundStyle(.secondary)
                }
                .card()

                // 筛选
                Picker("姿势", selection: $pose) {
                    Text("全部").tag("全部")
                    ForEach(PhotoStore.poses, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)

                if st.list.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "figure.arms.open").font(.largeTitle).foregroundStyle(Brand.gradient)
                        Text("每周同一时间、同样光线拍一组，备赛进度一眼看清").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 30).card()
                } else {
                    Text(selected.count == 2 ? "已选两张，点下面「对比」" : "点两张照片选中，就可以对比").font(.caption).foregroundStyle(.secondary)
                }

                ForEach(groups, id: \.0) { d, ps in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(Day.label(d)).font(.headline)
                            if let c = contestLeft(d) { Text(c).font(.caption.bold()).foregroundStyle(Brand.pink) }
                        }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                            ForEach(ps) { p in thumb(p) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 90)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("体态对比")
        .safeAreaInset(edge: .bottom) {
            if selected.count == 2 {
                Button { comparing = true } label: {
                    Label("对比这两张", systemImage: "rectangle.split.2x1").font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50).foregroundStyle(.white)
                        .background(Capsule().fill(Brand.gradient))
                }
                .padding(.horizontal, 16).padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: selected.count)
        .onChange(of: picks) { _, items in
            guard !items.isEmpty else { return }
            Task {
                for it in items {
                    if let d = try? await it.loadTransferable(type: Data.self) { st.add(d, date: Day.str(addDate), pose: addPose) }
                }
                picks = []
                Haptic.success()
            }
        }
        .fullScreenCover(isPresented: $comparing) {
            let two = selected.compactMap { id in st.list.first { $0.id == id } }.sorted { $0.date < $1.date }
            if two.count == 2 { PhotoCompare(a: two[0], b: two[1]) }
        }
        .fullScreenCover(item: $viewing) { p in PhotoViewer(p: p) }
    }

    private func contestLeft(_ d: String) -> String? {
        guard !ps.plan.contest.isEmpty else { return nil }
        let n = Day.between(d, ps.plan.contest)
        return n > 0 ? "赛前 \(n) 天" : n == 0 ? "比赛当天" : nil
    }

    private func thumb(_ p: BodyPhoto) -> some View {
        let on = selected.contains(p.id)
        return Button {
            Haptic.tap()
            if on { selected.removeAll { $0 == p.id } }
            else { selected.append(p.id); if selected.count > 2 { selected.removeFirst() } }
        } label: {
            Color.clear.aspectRatio(3 / 4, contentMode: .fit)
                .overlay {
                    if let ui = st.image(p) { Image(uiImage: ui).resizable().scaledToFill() } else { Color.gray.opacity(0.2) }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    Text(p.pose).font(.caption2.bold()).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 3).background(Capsule().fill(.black.opacity(0.45))).padding(6)
                }
                .overlay(alignment: .topTrailing) {
                    Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.title3)
                        .foregroundStyle(on ? Brand.pink : .white).shadow(radius: 2).padding(6)
                }
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(on ? Brand.pink : .clear, lineWidth: 3))
        }
        .buttonStyle(PressScale())
        .contextMenu {
            Button("查看大图") { viewing = p }
            Menu("改姿势") { ForEach(PhotoStore.poses, id: \.self) { o in Button(o) { if let i = st.list.firstIndex(where: { $0.id == p.id }) { st.list[i].pose = o } } } }
            Button("删除", role: .destructive) { selected.removeAll { $0 == p.id }; st.delete(p) }
        }
    }
}

// 两张对比：拖动中间的线左右看，或者并排看
struct PhotoCompare: View {
    @Environment(\.dismiss) private var dismiss
    let a: BodyPhoto, b: BodyPhoto
    @State private var split: CGFloat = 0.5
    @State private var sideBySide = false

    var body: some View {
        let ia = PhotoStore.shared.image(a), ib = PhotoStore.shared.image(b)
        NavigationStack {
            VStack(spacing: 14) {
                Picker("方式", selection: $sideBySide) {
                    Text("拖动对比").tag(false)
                    Text("并排").tag(true)
                }
                .pickerStyle(.segmented).padding(.horizontal)
                if sideBySide {
                    HStack(spacing: 6) {
                        pane(ia, a)
                        pane(ib, b)
                    }
                    .padding(.horizontal, 8)
                } else {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            img(ib).frame(width: g.size.width, height: g.size.height)
                            img(ia).frame(width: g.size.width, height: g.size.height)
                                .mask(alignment: .leading) { Rectangle().frame(width: g.size.width * split) }
                            Rectangle().fill(.white).frame(width: 3).shadow(radius: 3)
                                .offset(x: g.size.width * split - 1.5)
                            Image(systemName: "arrow.left.and.right.circle.fill").font(.system(size: 40))
                                .foregroundStyle(.white, Brand.pink).shadow(radius: 4)
                                .offset(x: g.size.width * split - 20)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(alignment: .topLeading) { tag(a) }
                        .overlay(alignment: .topTrailing) { tag(b) }
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                            split = min(1, max(0, v.location.x / g.size.width))
                        })
                    }
                    .padding(.horizontal, 12)
                }
                Text("相隔 \(Day.between(a.date, b.date)) 天").font(.headline).foregroundStyle(Brand.gradient)
                    .padding(.bottom, 8)
            }
            .navigationTitle("体态对比").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }

    private func img(_ ui: UIImage?) -> some View {
        Group { if let ui { Image(uiImage: ui).resizable().scaledToFill() } else { Color.gray.opacity(0.2) } }
            .clipped()
    }
    private func pane(_ ui: UIImage?, _ p: BodyPhoto) -> some View {
        Color.clear.overlay { img(ui) }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .topLeading) { tag(p) }
    }
    private func tag(_ p: BodyPhoto) -> some View {
        Text("\(slashDate(p.date)) \(p.pose)").font(.caption.bold()).foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(.black.opacity(0.5))).padding(10)
    }
}

struct PhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    let p: BodyPhoto
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let ui = PhotoStore.shared.image(p) { Image(uiImage: ui).resizable().scaledToFit() }
            Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.title).foregroundStyle(.white.opacity(0.8)) }
                .padding()
        }
    }
}
