import SwiftUI
import PhotosUI

// MARK: - 「我自己」打卡小人：用自己的照片当头

@MainActor
final class AvatarCache: ObservableObject {
    static let shared = AvatarCache()
    @Published private var imgs: [String: UIImage] = [:]
    @Published private(set) var mine: UIImage? = nil
    private var loading = Set<String>()
    private let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("my-avatar.jpg")

    init() { if let d = try? Data(contentsOf: file) { mine = UIImage(data: d) } }

    var mineJPG: Data? { try? Data(contentsOf: file) }
    func setMine(_ jpg: Data) {
        try? jpg.write(to: file, options: .atomic)
        mine = UIImage(data: jpg)
    }

    // 地球上某个人的头：自己用本机的照片（审核前也看得到），别人用审核通过的照片
    func face(_ p: GymPerson, me: String) -> UIImage? {
        if p.uid == me { return LifterChar.mine == .photo ? mine : nil }
        guard p.a == LifterChar.photo.rawValue, let u = p.p else { return nil }
        return image(u)
    }

    func image(_ url: String) -> UIImage? {
        if let i = imgs[url] { return i }
        if !loading.contains(url), let u = URL(string: url) {
            loading.insert(url)
            Task {
                if let (d, r) = try? await URLSession.shared.data(from: u), (r as? HTTPURLResponse)?.statusCode == 200, let img = UIImage(data: d) {
                    imgs[url] = img
                } else {
                    try? await Task.sleep(nanoseconds: 30_000_000_000)
                    loading.remove(url)
                }
            }
        }
        return nil
    }
}

// 选好照片后：双指缩放、拖动，把脸放进圆圈里
struct AvatarCropper: View {
    let image: UIImage
    var done: (Data) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var side: CGFloat = 300

    private func base(_ side: CGFloat) -> CGFloat { max(side / max(1, image.size.width), side / max(1, image.size.height)) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                GeometryReader { geo in
                    let sd = min(geo.size.width - 32, 340)
                    let k = base(sd) * scale
                    ZStack {
                        Image(uiImage: image).resizable()
                            .frame(width: image.size.width * k, height: image.size.height * k)
                            .offset(offset)
                        Rectangle().fill(.black.opacity(0.55))
                            .mask(ZStack { Rectangle(); Circle().frame(width: sd, height: sd).blendMode(.destinationOut) }.compositingGroup())
                            .allowsHitTesting(false)
                        Circle().strokeBorder(.white, lineWidth: 2).frame(width: sd, height: sd).allowsHitTesting(false)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture()
                            .onChanged { v in offset = clamp(CGSize(width: lastOffset.width + v.translation.width, height: lastOffset.height + v.translation.height), sd) }
                            .onEnded { _ in lastOffset = offset }
                            .simultaneously(with: MagnificationGesture()
                                .onChanged { m in scale = min(6, max(1, lastScale * m)); offset = clamp(offset, sd) }
                                .onEnded { _ in lastScale = scale; lastOffset = offset })
                    )
                    .onAppear { side = sd }
                    .onChange(of: geo.size) { _, s in side = min(s.width - 32, 340) }
                }
                .frame(height: 400)
                Text("双指缩放、拖动，把脸放进圆圈里").font(.footnote).foregroundStyle(.secondary)
                Text("照片会公开显示在打卡地球上，审核通过后别人才看得到。关掉「公开到打卡地球」就不显示。")
                    .font(.caption).foregroundStyle(.orange).multilineTextAlignment(.center).padding(.horizontal, 24)
                Spacer()
            }
            .padding(.top, 20)
            .background(Color.black.ignoresSafeArea())
            .preferredColorScheme(.dark)
            .navigationTitle("移动和缩放").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("使用") { if let d = crop() { done(d) }; dismiss() }.bold()
                }
            }
        }
    }

    // 图片不能拖出圆圈
    private func clamp(_ o: CGSize, _ sd: CGFloat) -> CGSize {
        let k = base(sd) * scale
        let mx = max(0, (image.size.width * k - sd) / 2), my = max(0, (image.size.height * k - sd) / 2)
        return CGSize(width: min(mx, max(-mx, o.width)), height: min(my, max(-my, o.height)))
    }

    // 按圆圈裁成 400×400 的正方形
    private func crop() -> Data? {
        let k = base(side) * scale
        let dw = image.size.width * k, dh = image.size.height * k
        let x = (dw / 2 - offset.width - side / 2) / k, y = (dh / 2 - offset.height - side / 2) / k, s = side / k
        let out: CGFloat = 400
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: out, height: out), format: fmt).image { _ in
            let f = out / s
            image.draw(in: CGRect(x: -x * f, y: -y * f, width: image.size.width * f, height: image.size.height * f))
        }
        return img.jpegData(compressionQuality: 0.8)
    }
}

// 打卡小人页的「换照片」格子：选照片 → 裁剪 → 存本机 + 上传
struct AvatarPickCell<Label: View>: View {
    var onDone: () -> Void
    @ViewBuilder var label: () -> Label
    @State private var item: PhotosPickerItem? = nil
    @State private var picked: UIImage? = nil
    var body: some View {
        PhotosPicker(selection: $item, matching: .images) { label() }
            .buttonStyle(PressScale())
            .onChange(of: item) { _, it in
                guard let it else { return }
                Task {
                    if let d = try? await it.loadTransferable(type: Data.self), let img = UIImage(data: d) { picked = img }
                    item = nil
                }
            }
            .fullScreenCover(item: Binding(get: { picked.map { IdentImage(img: $0) } }, set: { if $0 == nil { picked = nil } })) { x in
                AvatarCropper(image: x.img) { jpg in
                    AvatarCache.shared.setMine(jpg)
                    LifterChar.mine = .photo
                    GymStore.shared.setChar(.photo)
                    GymStore.shared.uploadAvatar(jpg)
                    onDone()
                }
            }
    }
}

struct IdentImage: Identifiable { let id = UUID(); let img: UIImage }
