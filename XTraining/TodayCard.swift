import SwiftUI
import PhotosUI

// 首页最上面“今天练什么”大卡片的背景（自己生成的 8 张图，可在卡片右上角换）
enum HeroBG {
    static let names = ["墨夜光晕", "极光", "石墨速度线", "日落", "深海同心圆", "X 纹", "等高线", "浅色薄雾"]
    static func image(_ i: Int) -> Image { Image("HeroBG\(min(max(i, 1), names.count))") }
    // 0 = 自己的照片（存在 heroPhoto 里），没有照片就退回 1 号
    static func image(_ i: Int, photo: Data) -> Image {
        if i == 0, let ui = UIImage(data: photo) { return Image(uiImage: ui) }
        return image(i == 0 ? 1 : i)
    }
}

struct HeroBanner<Trailing: View>: View {
    @AppStorage("heroBg") private var bg = 1
    @AppStorage("heroPhoto") private var photo = Data()
    @State private var picking = false
    let tag: String
    let title: String
    let sub: String
    let button: String?
    let action: () -> Void
    let trailing: () -> Trailing

    init(tag: String, title: String, sub: String, button: String? = nil, action: @escaping () -> Void = {},
         @ViewBuilder trailing: @escaping () -> Trailing) {
        self.tag = tag; self.title = title; self.sub = sub; self.button = button; self.action = action; self.trailing = trailing
    }

    var body: some View {
        // 文字决定高度，背景图铺在后面并裁掉多余部分，避免压到下面的内容
        VStack(alignment: .leading, spacing: 6) {
            Text(tag).font(.footnote.bold()).foregroundStyle(.white.opacity(0.8))
            Text(title).font(.system(size: 36, weight: .heavy)).foregroundStyle(.white)
                .lineLimit(2).minimumScaleFactor(0.6)
            Text(sub).font(.subheadline).foregroundStyle(.white.opacity(0.85)).lineLimit(2)
            if let button {
                Button(action: action) {
                    Label(button, systemImage: "play.fill").font(.headline).foregroundStyle(.black)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .padding(.horizontal, 26).padding(.vertical, 12)
                        .background(Capsule().fill(.white))
                }
                .buttonStyle(PressScale()).padding(.top, 6)
            }
        }
        .padding(.horizontal, 20).padding(.top, 64).padding(.bottom, 20)
        .frame(maxWidth: .infinity, minHeight: button == nil ? 220 : 280, alignment: .bottomLeading)
        .background {
            ZStack {
                HeroBG.image(bg, photo: photo).resizable().scaledToFill()
                    .modifier(KenBurns())
                LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
                ShineSweep()
            }
        }
        .clipped()
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 8) {
                trailing()
                Button { picking = true } label: {
                    Image(systemName: "photo.on.rectangle").font(.footnote.bold()).foregroundStyle(.white)
                        .frame(width: 34, height: 34).background(.ultraThinMaterial, in: Circle())
                }
            }
            .padding(14)
        }
        .sheet(isPresented: $picking) { HeroBGPicker() }
    }
}

extension HeroBanner where Trailing == EmptyView {
    init(tag: String, title: String, sub: String, button: String? = nil, action: @escaping () -> Void = {}) {
        self.init(tag: tag, title: title, sub: sub, button: button, action: action) { EmptyView() }
    }
}

struct HeroBGPicker: View {
    @AppStorage("heroBg") private var bg = 1
    @AppStorage("heroPhoto") private var photo = Data()
    @Environment(\.dismiss) private var dismiss
    @State private var pick: PhotosPickerItem? = nil
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                    // 自定义：从相册选一张
                    PhotosPicker(selection: $pick, matching: .images) {
                        ZStack {
                            if let ui = UIImage(data: photo) {
                                Image(uiImage: ui).resizable().scaledToFill()
                            } else {
                                Color(.tertiarySystemFill)
                            }
                            VStack(spacing: 4) {
                                Image(systemName: photo.isEmpty ? "plus" : "photo.badge.plus").font(.title3.bold())
                                Text(photo.isEmpty ? "用自己的照片" : "换一张").font(.caption.bold())
                            }
                            .foregroundStyle(photo.isEmpty ? Color.primary : .white)
                            .padding(8).background(photo.isEmpty ? Color.clear : Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .frame(height: 120).frame(maxWidth: .infinity).clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay {
                            if bg == 0 && !photo.isEmpty {
                                RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.primary, lineWidth: 3)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    ForEach(1...HeroBG.names.count, id: \.self) { i in
                        Button { Haptic.tap(); bg = i; dismiss() } label: {
                            HeroBG.image(i).resizable().scaledToFill()
                                .frame(height: 120).frame(maxWidth: .infinity).clipped()
                                .overlay(alignment: .bottomLeading) {
                                    Text(HeroBG.names[i - 1]).font(.caption.bold()).foregroundStyle(.white)
                                        .padding(.horizontal, 8).padding(.vertical, 4)
                                        .background(.black.opacity(0.4), in: Capsule()).padding(8)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay {
                                    if bg == i {
                                        RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.primary, lineWidth: 3)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .onChange(of: pick) { _, p in
                Task {
                    if let d = try? await p?.loadTransferable(type: Data.self), let ui = UIImage(data: d), let j = heroJPEG(ui, width: 1200) {
                        photo = j; bg = 0; Haptic.tap(); dismiss()
                    }
                }
            }
            .navigationTitle("换背景")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

// 大卡片外壳：上面是背景图横幅，下面是内容
struct BigCard<Content: View>: View {
    let content: () -> Content
    init(@ViewBuilder content: @escaping () -> Content) { self.content = content }
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        VStack(alignment: .leading, spacing: 0) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: shape)
            .clipShape(shape)
            .shadow(color: .black.opacity(0.12), radius: 14, y: 8)
    }
}
