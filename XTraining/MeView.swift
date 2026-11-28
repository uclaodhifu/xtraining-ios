import SwiftUI
import UniformTypeIdentifiers

// 我：外观、标题、导入导出
struct MeView: View {
    @EnvironmentObject var store: Store
    @AppStorage("theme") private var theme = "system"
    @AppStorage(InputMode.key) private var inputMode = 0
    @AppStorage("xt.entryLandscape") private var alwaysLand = false
    @AppStorage("brandTitle") private var brandTitle = ""
    @AppStorage("skin") private var skin = "ins"
    @State private var notesImport = false
    @AppStorage(WU.key) private var unit = "kg"
    @State private var askUnit: String? = nil
    @State private var importing = false
    @State private var message: String? = nil
    @State private var syncing = false
    @State private var clearing = false

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
                    MeLifterRow()
                }
                // 组间心率和几个入口合成一张卡片。列表里只放固定高度的一行，图表在点进去的页面里
                // （图表直接放在列表里会让「我」页排版死循环闪退，第 49–52 版）
                Section {
                    NavigationLink { HeartPage() } label: { HeartRow() }
                    NavigationLink { ExerciseLibView() } label: {
                        MeLinkLabel(system: "books.vertical.fill", colors: [Color(hex: 0xffb340), Color(hex: 0xff9500)], title: "动作库", sub: "要领和练哪块肌肉")
                    }
                    NavigationLink { AnchorView() } label: {
                        MeLinkLabel(system: "scope", colors: [Color(hex: 0x7d7aff), Color(hex: 0x5e5ce6)], title: "阶段对比", sub: "增肌减脂期按锚点看升降")
                    }
                    NavigationLink { CreatorsView() } label: {
                        MeLinkLabel(system: "person.2.fill", colors: [Color(hex: 0x40a0ff), Color(hex: 0x0a84ff)], title: "健身博主", sub: "我关注的抖音主页")
                    }
                }
                Section {
                    ActivityCard()
                        .padding(.vertical, 6)
                }
                CloudSection()
                Section {
                    Picker("重量单位", selection: Binding(get: { unit }, set: { v in if v != unit { askUnit = v } })) {
                        Text("公斤 kg").tag("kg")
                        Text("磅 lb").tag("lb")
                    }
                    .pickerStyle(.segmented)
                } header: { Text("重量单位") } footer: {
                    Text("换单位会把以前所有训练的重量一起换算（比如 60kg → 132.3lb），换回来也一样。体重还是按公斤记。")
                }
                .confirmationDialog("把所有重量换成\(askUnit == "lb" ? "磅" : "公斤")？", isPresented: Binding(get: { askUnit != nil }, set: { if !$0 { askUnit = nil } }), titleVisibility: .visible) {
                    Button("换算成\(askUnit == "lb" ? "磅 lb" : "公斤 kg")") {
                        if let u = askUnit { store.switchUnit(toLb: u == "lb"); Haptic.success() }
                        askUnit = nil
                    }
                    Button("取消", role: .cancel) { askUnit = nil }
                } message: { Text("以前记的重量、挂片、目标重量都会一起换算。") }
                Section {
                    Picker("记录训练的输入方式", selection: $inputMode) {
                        Text("数字手写").tag(0)
                        Text("全部手写").tag(1)
                        Text("键盘").tag(2)
                    }
                    .pickerStyle(.segmented)
                    Toggle("记录时总是横屏", isOn: $alwaysLand)
                } header: { Text("输入方式") } footer: {
                    Text((inputMode == 0 ? "重量和次数用手指写，格子里留原样笔迹；动作名、备注用键盘。"
                         : inputMode == 1 ? "重量、次数、动作名都手写，格子里留着你写的原样笔迹，像一本电子手写笔记。数字照样会认出来，涨跌和统计不受影响。"
                         : "都用系统键盘打字。") + "\n横屏：一行一个动作、一格一组，右边手写。记录页右上角也能随时切换。")
                }
                Section {
                    BugRecordRow()
                } header: { Text("遇到问题") } footer: {
                    Text("点了以后照常操作，把出问题的步骤做一遍，再点顶上的「停止」上传。会记下点了哪里、开了哪个页面、按了哪个数字、手写认成了什么、格子里的数字变化。不录屏幕画面，不含照片和个人信息。")
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
                    Button { notesImport = true } label: { Label("从备忘录导入训练记录（自动纠错）", systemImage: "note.text.badge.plus") }
                    Button { importing = true } label: { Label("从文件导入备份", systemImage: "doc.badge.plus") }
                    Button { syncing = true } label: { Label("用同步码找回（含头像）", systemImage: "arrow.triangle.2.circlepath") }
                    Button { pasteImport() } label: { Label("粘贴备份内容", systemImage: "doc.on.clipboard") }
                    ShareLink(item: BackupFile { store.exportBackup() }, preview: SharePreview("X Training 备份.json")) {
                        Label("导出备份", systemImage: "square.and.arrow.up")
                    }
                } header: { Text("数据") } footer: {
                    Text("推荐「用同步码找回」：在网页版「我 → 同步码」点复制，回来填上网站密码就行，训练记录和头像都会搬过来。导出的 .json 备份里带着体重和手写笔迹，导回来笔迹照样显示。重复导入不会重复添加。")
                }
                Section {
                    Button(role: .destructive) { clearing = true } label: {
                        Label("一键清除训练记录", systemImage: "trash").foregroundStyle(.red)
                    }
                } footer: { Text("清除前可以先导出备份，清掉以后还能导回来。") }
                Section {
                    LabeledContent("版本", value: "测试版 1.0")
                }
            }
            .sheet(isPresented: $notesImport) { NotesImportView() }
            .sheet(isPresented: $clearing) { ClearDataView().presentationDetents([.medium, .large]) }
            .navigationTitle("我")
            .sheet(isPresented: $syncing) { SyncRestoreView() }
            .sheet(isPresented: $importing) {
                DocPicker { url in
                    importing = false
                    guard let url else { return }
                    do { run(try Data(contentsOf: url)) }
                    catch { message = "文件打不开：\(error.localizedDescription)" }
                }
                .ignoresSafeArea()
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
    let make: @MainActor () -> Data     // 点分享时才打包（里面有手写笔迹，别每次刷新页面都打一遍）
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { await $0.make() }
            .suggestedFileName("XTraining-backup.json")
    }
}

// 系统的“选文件”窗口（复制一份到 App 里再读，iCloud 里的文件也能选）
struct DocPicker: UIViewControllerRepresentable {
    let done: (URL?) -> Void
    func makeCoordinator() -> Coord { Coord(done: done) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let p = UIDocumentPickerViewController(forOpeningContentTypes: [.json, .text, .data, .item], asCopy: true)
        p.allowsMultipleSelection = false
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}
    final class Coord: NSObject, UIDocumentPickerDelegate {
        let done: (URL?) -> Void
        init(done: @escaping (URL?) -> Void) { self.done = done }
        func documentPicker(_ c: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { done(urls.first) }
        func documentPickerWasCancelled(_ c: UIDocumentPickerViewController) { done(nil) }
    }
}


// 一键清除：选清哪些 → 可先导出备份 → 再确认一次；清完马上可以撤销
struct ClearDataView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var workouts = true
    @State private var weights = false
    @State private var days = false
    @State private var confirm = false
    @State private var undo: Snap? = nil
    struct Snap { var w: [Workout]; var kg: [WeightRow]; var rest: [String]; var done: [String] }

    var body: some View {
        NavigationStack {
            Form {
                if let undo {
                    Section {
                        Label("已清除", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        Button {
                            withAnimation {
                                CloudSync.shared.forgive(undo.w.map(\.id))
                                store.workouts = undo.w; store.weights = undo.kg
                                store.restDays = undo.rest; store.doneDays = undo.done
                            }
                            self.undo = nil
                            Haptic.success()
                        } label: { Label("撤销，恢复刚才的记录", systemImage: "arrow.uturn.backward") }
                    } footer: { Text("关掉这个页面后就不能撤销了。") }
                } else {
                    Section {
                        Toggle("训练记录（\(store.workouts.count) 次）", isOn: $workouts)
                        Toggle("体重记录（\(store.weights.count) 条）", isOn: $weights)
                        Toggle("打卡和休息日", isOn: $days)
                    } header: { Text("要清除哪些") }
                    Section {
                        ShareLink(item: BackupFile { store.exportBackup() }, preview: SharePreview("X Training 备份.json")) {
                            Label("先导出备份（推荐）", systemImage: "square.and.arrow.up")
                        }
                    } footer: { Text("备份文件可以在「我 → 从文件导入备份」导回来。") }
                    Section {
                        Button(role: .destructive) { confirm = true } label: {
                            Text("清除").bold().frame(maxWidth: .infinity)
                        }
                        .disabled(!workouts && !weights && !days)
                    }
                }
            }
            .navigationTitle("清除训练记录").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(undo == nil ? "取消" : "完成") { dismiss() } } }
            .alert("确定清除？", isPresented: $confirm) {
                Button("清除", role: .destructive) { clear() }
                Button("取消", role: .cancel) {}
            } message: { Text("清除后这台手机上的这些记录就没有了。") }
        }
    }

    private func clear() {
        undo = Snap(w: store.workouts, kg: store.weights, rest: store.restDays, done: store.doneDays)
        withAnimation {
            if workouts { CloudSync.shared.noteDelete(store.workouts.map(\.id)); store.workouts = [] }
            if weights { store.weights = [] }
            if days { store.restDays = []; store.doneDays = [] }
        }
        Haptic.success()
    }
}
