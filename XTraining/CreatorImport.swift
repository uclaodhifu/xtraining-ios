import SwiftUI
import PhotosUI
import Vision

// 批量导入博主：① 关注列表截图，手机本地识别名字（不上传）② 一次粘贴多行
struct CreatorImportView: View {
    @ObservedObject private var cs = CreatorStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var mode = 0
    @State private var picks: [PhotosPickerItem] = []
    @State private var text = ""
    @State private var found: [Cand] = []
    @State private var busy = false

    struct Cand: Identifiable, Hashable { let id = UUID(); var name: String; var link: String; var on: Bool; var avatar: Data? = nil }

    var body: some View {
        NavigationStack {
            Form {
                Picker("", selection: $mode) {
                    Text("截图识别").tag(0)
                    Text("粘贴多行").tag(1)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)

                if mode == 0 {
                    Section {
                        PhotosPicker(selection: $picks, maxSelectionCount: 20, matching: .images) {
                            Label("选关注列表截图（可多张）", systemImage: "photo.stack")
                        }
                        if busy { HStack { ProgressView(); Text("识别中…").foregroundStyle(.secondary) } }
                    } footer: {
                        Text("在抖音打开“我 → 关注”，往下滑一屏截一张。识别在手机上完成，图片不会上传。")
                    }
                } else {
                    Section {
                        TextField("每行一个：名字 抖音号或链接", text: $text, axis: .vertical).lineLimit(5...12)
                        Button("识别这些行") { found = merge(parseLines(text)) }
                            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    } footer: {
                        Text("例：张三 zhangsan123。也可以把多段抖音分享文字一起粘进来。只写名字也行，会按名字搜。")
                    }
                }

                if !found.isEmpty {
                    Section {
                        ForEach($found) { $c in
                            HStack {
                                Image(systemName: c.on ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(c.on ? Brand.pink : .secondary)
                                    .onTapGesture { c.on.toggle() }
                                CreatorAvatar(c: Creator(name: c.name, link: c.link, avatar: c.avatar), size: 34)
                                TextField("名字", text: $c.name)
                                if c.link != c.name {
                                    Text(c.link.hasPrefix("http") ? "链接" : c.link).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Text("识别到 \(found.count) 个，勾选要导入的")
                            Spacer()
                            Button(found.allSatisfy(\.on) ? "全不选" : "全选") {
                                let v = !found.allSatisfy(\.on); for i in found.indices { found[i].on = v }
                            }
                            .font(.caption.bold()).textCase(nil)
                        }
                    }
                }
            }
            .navigationTitle("批量导入博主")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("导入 \(found.filter(\.on).count) 个") { save() }.bold()
                        .disabled(!found.contains(where: \.on))
                }
            }
            .onChange(of: picks) { _, items in Task { await recognize(items) } }
        }
    }

    private func save() {
        var have = Set(cs.list.map(\.name))
        for c in found where c.on {
            let n = c.name.trimmingCharacters(in: .whitespaces)
            guard !n.isEmpty, !have.contains(n) else { continue }
            cs.list.append(Creator(name: n, link: c.link.isEmpty ? n : c.link, avatar: c.avatar)); have.insert(n)
        }
        Haptic.success(); dismiss()
    }

    // 合并去重，已经在列表里的不再出现
    private func merge(_ new: [Cand]) -> [Cand] {
        var seen = Set(cs.list.map(\.name)).union(found.map(\.name))
        var out = found
        for c in new where !seen.contains(c.name) { out.append(c); seen.insert(c.name) }
        return out
    }

    private func parseLines(_ t: String) -> [Cand] {
        t.components(separatedBy: .newlines).compactMap { line in
            let l = line.trimmingCharacters(in: .whitespaces)
            guard !l.isEmpty else { return nil }
            let p = CreatorStore.parse(l)
            if let link = p.link {
                let n = p.name ?? l.components(separatedBy: "http").first?.trimmingCharacters(in: .whitespaces) ?? ""
                return Cand(name: n.isEmpty || n.count > 20 ? "未命名" : n, link: link, on: true)
            }
            let parts = l.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "," || $0 == "，" }).map(String.init)
            guard let n = parts.first else { return nil }
            return Cand(name: n, link: parts.count > 1 ? parts[1] : n, on: true)
        }
    }

    // 截图文字识别：只留像名字的行（每条关注里字最大的那一行）
    private func recognize(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        busy = true; defer { busy = false; picks = [] }
        var all: [Cand] = []
        for it in items {
            guard let d = try? await it.loadTransferable(type: Data.self), let cg = UIImage(data: d)?.cgImage else { continue }
            let names = await Task.detached { Self.ocrNames(cg) }.value
            all += names.map { Cand(name: $0.0, link: $0.0, on: true, avatar: $0.1) }
        }
        found = merge(all)
    }

    // 返回 (名字, 头像 JPEG)。名字是每一行最上面那行字；紧贴在下面的是简介，跳过
    nonisolated static func ocrNames(_ cg: CGImage) -> [(String, Data?)] {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.recognitionLanguages = ["zh-Hans", "en-US"]
        req.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: cg).perform([req])
        let obs = (req.results ?? []).compactMap { o -> (String, CGRect)? in
            guard let s = o.topCandidates(1).first?.string else { return nil }
            return (s.trimmingCharacters(in: .whitespaces), o.boundingBox)
        }
        // 只看头像右边那一列文字（去掉标题、按钮、底部提示）
        let col = obs.filter { _, b in b.minX > 0.1 && b.minX < 0.3 && b.maxY < 0.88 && b.minY > 0.03 }
            .sorted { $0.1.maxY > $1.1.maxY }            // 从上往下
        let skip = ["已关注", "互相关注", "回关", "暂时没有更多"]
        let W = CGFloat(cg.width), H = CGFloat(cg.height)
        var out: [(String, Data?)] = []
        var prevBottom: CGFloat = 2
        for (i, (s, b)) in col.enumerated() {
            let gap = prevBottom - b.maxY
            prevBottom = b.minY
            if gap < 0.02 { continue }                    // 紧贴上一行 = 简介
            guard s.count >= 1, s.count <= 30, !skip.contains(where: { s.contains($0) }) else { continue }
            // 头像中心：名字和简介中间；没有简介就往下挪一点
            var cy = b.midY - b.height * 0.8
            if i + 1 < col.count, b.minY - col[i + 1].1.maxY < 0.02 { cy = (b.midY + col[i + 1].1.midY) / 2 }
            let side = W * 0.11
            let cx = b.minX * W - W * 0.083
            let rect = CGRect(x: cx - side / 2, y: (1 - cy) * H - side / 2, width: side, height: side).integral
            var avatar: Data? = nil
            if rect.minX >= 0, rect.minY >= 0, rect.maxX <= W, rect.maxY <= H, let crop = cg.cropping(to: rect) {
                avatar = heroJPEG(UIImage(cgImage: crop), width: 160)
            }
            out.append((s, avatar))
        }
        return out
    }
}
