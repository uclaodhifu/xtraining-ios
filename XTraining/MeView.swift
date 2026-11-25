import SwiftUI
import UniformTypeIdentifiers

// 我：外观、标题、导入导出
struct MeView: View {
    @EnvironmentObject var store: Store
    @AppStorage("theme") private var theme = "system"
    @AppStorage("brandTitle") private var brandTitle = ""
    @State private var importing = false
    @State private var message: String? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().fill(Brand.gradient).frame(width: 60, height: 60)
                            Text("X").font(.system(size: 30, weight: .black)).italic().foregroundStyle(.white)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(brandTitle.isEmpty ? "X Training" : brandTitle).font(.title3.bold())
                            Text("\(store.workouts.count) 次训练 · 连续 \(store.streak) 天").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }
                Section("外观") {
                    Picker("白天 / 夜间", selection: $theme) {
                        Text("跟随系统").tag("system")
                        Text("白天").tag("light")
                        Text("夜间").tag("dark")
                    }
                    .pickerStyle(.segmented)
                    TextField("首页标题", text: $brandTitle, prompt: Text("X Training"))
                }
                Section {
                    Button { importing = true } label: { Label("导入网页版备份", systemImage: "square.and.arrow.down") }
                    ShareLink(item: BackupFile(data: store.exportBackup()), preview: SharePreview("X Training 备份.json")) {
                        Label("导出备份", systemImage: "square.and.arrow.up")
                    }
                } header: { Text("数据") } footer: {
                    Text("在网页版“我 → 导出备份”存下 .json 文件，再在这里导入，训练和体重都会搬过来。数据只存在这台设备上。")
                }
                Section {
                    LabeledContent("版本", value: "测试版 1.0")
                }
            }
            .navigationTitle("我")
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .plainText, .data]) { result in
                switch result {
                case .success(let url):
                    let ok = url.startAccessingSecurityScopedResource()
                    defer { if ok { url.stopAccessingSecurityScopedResource() } }
                    do {
                        let data = try Data(contentsOf: url)
                        let n = try store.importBackup(data)
                        message = "导入好了，新加了 \(n) 次训练"
                        Haptic.success()
                    } catch {
                        message = "这个文件读不了，请选网页版导出的备份 .json"
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

struct BackupFile: Transferable {
    let data: Data
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { $0.data }
            .suggestedFileName("XTraining-backup.json")
    }
}
