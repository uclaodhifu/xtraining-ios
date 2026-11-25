import SwiftUI
import PhotosUI

// 头像：存在本机
struct AvatarView: View {
    @EnvironmentObject var store: Store
    var size: CGFloat = 40
    var body: some View {
        Group {
            if let d = store.avatar, let img = UIImage(data: d) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                ZStack {
                    Circle().fill(Brand.gradient)
                    Text(store.nickname.first.map(String.init) ?? "X")
                        .font(.system(size: size * 0.45, weight: .black)).italic().foregroundStyle(Brand.ink)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Brand.gradient, lineWidth: size > 50 ? 3 : 2).padding(-3))
    }
}

// 选头像（相册），裁成正方形缩到 400px
struct AvatarPicker: View {
    @EnvironmentObject var store: Store
    @State private var item: PhotosPickerItem? = nil
    var body: some View {
        PhotosPicker(selection: $item, matching: .images) {
            ZStack(alignment: .bottomTrailing) {
                AvatarView(size: 72)
                Image(systemName: "camera.circle.fill").font(.title2)
                    .symbolRenderingMode(.palette).foregroundStyle(.white, Brand.pink)
                    .offset(x: 4, y: 4)
            }
        }
        .buttonStyle(.plain)
        .onChange(of: item) { _, new in
            guard let new else { return }
            Task {
                if let d = try? await new.loadTransferable(type: Data.self), let img = UIImage(data: d) {
                    withAnimation(.spring) { store.avatar = squareJPEG(img) }
                    Haptic.success()
                }
                item = nil
            }
        }
    }
}

func squareJPEG(_ img: UIImage, side: CGFloat = 400) -> Data? {
    let s = min(img.size.width, img.size.height)
    let rect = CGRect(x: (img.size.width - s) / 2, y: (img.size.height - s) / 2, width: s, height: s)
    let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
    let out = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: fmt).image { _ in
        img.draw(in: CGRect(x: -rect.minX * side / s, y: -rect.minY * side / s, width: img.size.width * side / s, height: img.size.height * side / s))
    }
    return out.jpegData(compressionQuality: 0.85)
}

// 用网页版的同步码找回记录和头像（要网站访问密码）
struct SyncRestoreView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var code = ""
    @State private var busy = false
    @State private var result: String? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("网站访问密码", text: $password)
                    TextField("同步码", text: $code).textInputAutocapitalization(.never).autocorrectionDisabled()
                } footer: {
                    Text("同步码在网页版「我 → 同步码」里，点一下就能复制。密码只用来登录你自己的网站，不会保存。")
                }
                Section {
                    Button {
                        Task { await restore() }
                    } label: {
                        HStack { Text(busy ? "正在找回…" : "找回记录和头像"); if busy { Spacer(); ProgressView() } }
                    }
                    .disabled(busy || password.isEmpty || code.filter(\.isLetter).count + code.filter(\.isNumber).count < 16)
                }
                if let r = result { Section { Text(r) } }
            }
            .navigationTitle("用同步码找回").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
            .onAppear {
                if let s = UIPasteboard.general.string, s.filter({ $0.isLetter || $0.isNumber }).count >= 16, s.count < 60 { code = s }
            }
        }
    }

    private func restore() async {
        busy = true; defer { busy = false }
        let base = URL(string: "https://fitnote-nine.vercel.app")!
        do {
            // 1. 登录网站
            var login = URLRequest(url: base.appendingPathComponent("api/login"))
            login.httpMethod = "POST"
            login.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            let pw = password.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
            login.httpBody = "password=\(pw)&next=%2F".data(using: .utf8)
            let (_, lr) = try await URLSession.shared.data(for: login)
            if let u = (lr as? HTTPURLResponse)?.url, u.path == "/login" { result = "密码不对"; return }
            // 2. 用同步码找回
            var req = URLRequest(url: base.appendingPathComponent("api/restore"))
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: ["key": code])
            let (data, resp) = try await URLSession.shared.data(for: req)
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
                result = (obj["error"] as? String) ?? "找回失败，检查一下网络（国内可能要开 VPN）"; return
            }
            let (n, _) = try store.importBackup(data)
            if let name = obj["name"] as? String, !name.isEmpty { store.nickname = name }
            if let a = obj["avatar"] as? String, let comma = a.firstIndex(of: ","), let d = Data(base64Encoded: String(a[a.index(after: comma)...])) {
                store.avatar = d
            }
            result = "找回好了：新加 \(n) 次训练" + (store.avatar != nil ? "，头像也换好了" : "")
            password = ""
            Haptic.success()
        } catch {
            result = "连不上网站：\(error.localizedDescription)\n国内访问 vercel.app 不稳定，可以开 VPN 再试。"
        }
    }
}
