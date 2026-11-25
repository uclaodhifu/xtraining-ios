import SwiftUI

// 首页最上面“今天练什么”大卡片的背景（自己生成的 8 张图，可在卡片右上角换）
enum HeroBG {
    static let names = ["墨夜光晕", "极光", "石墨速度线", "日落", "深海同心圆", "X 纹", "等高线", "浅色薄雾"]
    static func image(_ i: Int) -> Image { Image("HeroBG\(min(max(i, 1), names.count))") }
}

struct HeroBanner<Trailing: View>: View {
    @AppStorage("heroBg") private var bg = 1
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
        ZStack(alignment: .bottomLeading) {
            HeroBG.image(bg).resizable().scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 6) {
                Text(tag).font(.footnote.bold()).foregroundStyle(.white.opacity(0.8))
                Text(title).font(.system(size: 36, weight: .heavy)).foregroundStyle(.white)
                    .lineLimit(2).minimumScaleFactor(0.6)
                Text(sub).font(.subheadline).foregroundStyle(.white.opacity(0.85)).lineLimit(2)
                if let button {
                    Button(action: action) {
                        Label(button, systemImage: "play.fill").font(.headline).foregroundStyle(.black)
                            .padding(.horizontal, 26).padding(.vertical, 12)
                            .background(Capsule().fill(.white))
                    }
                    .buttonStyle(PressScale()).padding(.top, 6)
                }
            }
            .padding(20)
        }
        .frame(height: button == nil ? 220 : 280)
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
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
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
