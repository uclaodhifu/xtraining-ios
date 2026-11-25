import SwiftUI
import UniformTypeIdentifiers

// 我：外观、标题、导入导出
struct MeView: View {
    @EnvironmentObject var store: Store
    @AppStorage("theme") private var theme = "system"
    @AppStorage("brandTitle") private var brandTitle = ""
    @AppStorage("skin") private var skin = "ins"
    @State private var importing = false
    @State private var message: String? = nil
    @State private var syncing = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        AvatarPicker()
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("你的昵称", text: $store.nickname).font(.title3.bold())
                            Text("\(store.workouts.count) 次训练 · 连续 \(store.streak) 天").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                    if store.avatar != nil {
                        Button("删掉头像", role: .destructive) { withAnimation { store.avatar = nil } }
                    }
                }
                Section("主题配色") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                        ForEach(Skin.allCases) { s in
                            Button { withAnimation(.snappy) { skin = s.rawValue }; Haptic.tap() } label: {
                                VStack(spacing: 6) {
                                    Circle().fill(s.swatch).frame(width: 40, height: 40)
                                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.15)))
                                    Text(s.name).font(.caption.bold())
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                                .background(RoundedRectangle(cornerRadius: 14).fill(Color(.tertiarySystemFill)))
                                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(skin == s.rawValue ? s.accent : .clear, lineWidth: 2))
                                .scaleEffect(skin == s.rawValue ? 1.04 : 1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("外观") {
                    Picker("白天 / 夜间", selection: $theme) {
                        Text("跟随系统").tag("system")
                        Text("白天").tag("light")
                        Text("夜间").tag("dark")
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Button { importing = true } label: { Label("从文件导入备份", systemImage: "doc.badge.plus") }
                    Button { syncing = true } label: { Label("用同步码找回（含头像）", systemImage: "arrow.triangle.2.circlepath") }
                    Button { pasteImport() } label: { Label("粘贴备份内容", systemImage: "doc.on.clipboard") }
                    ShareLink(item: BackupFile(data: store.exportBackup()), preview: SharePreview("X Training 备份.json")) {
                        Label("导出备份", systemImage: "square.and.arrow.up")
                    }
                } header: { Text("数据") } footer: {
                    Text("推荐「用同步码找回」：在网页版「我 → 同步码」点复制，回来填上网站密码就行，训练记录和头像都会搬过来。体重记录要用导出的 .json 文件导入。重复导入不会重复添加。")
                }
                Section {
                    LabeledContent("版本", value: "测试版 1.0")
                }
            }
            .navigationTitle("我")
            .sheet(isPresented: $syncing) { SyncRestoreView() }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .plainText, .data]) { result in
                switch result {
                case .success(let url):
                    let ok = url.startAccessingSecurityScopedResource()
                    defer { if ok { url.stopAccessingSecurityScopedResource() } }
                    do {
                        let data = try Data(contentsOf: url)
                        run(data)
                    } catch {
                        message = "文件打不开：\(error.localizedDescription)\n如果文件在 iCloud 里，先在「文件」App 里点一下让它下载好再导入。"
                    }
                case .failure:
                    message = "没能打开文件"
                }
            }
            .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("好") { message = nil }
            }
        }
    }
}

extension MeView {
    func run(_ data: Data) {
        do {
            let (n, w) = try store.importBackup(data)
            message = "导入好了：新加 \(n) 次训练、\(w) 条体重"
            Haptic.success()
        } catch {
            message = "导入失败：\(error.localizedDescription)"
        }
    }
    func pasteImport() {
        guard let s = UIPasteboard.general.string, !s.isEmpty else {
            message = "剪贴板是空的。先把备份 .json 文件的内容复制下来，再回来点这里。"
            return
        }
        // 复制的是同步码：走同步码找回
        if s.count < 60, s.filter({ $0.isLetter || $0.isNumber }).count >= 16, !s.contains("{") { syncing = true; return }
        run(Data(s.utf8))
    }
}

struct BackupFile: Transferable {
    let data: Data
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { $0.data }
            .suggestedFileName("XTraining-backup.json")
    }
}
