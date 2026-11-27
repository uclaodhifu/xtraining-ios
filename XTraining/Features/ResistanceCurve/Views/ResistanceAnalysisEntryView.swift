import SwiftUI
import PhotosUI
import CoreGraphics

let resistanceAccent = Color(hex: 0xe8590c)

// MARK: - 流程状态

@MainActor
final class ResistanceFlowModel: ObservableObject {
    enum Step { case entry, anchors, analyzing, result }

    @Published var step: Step = .entry
    @Published var videoURL: URL?
    @Published var firstFrame: CGImage?
    @Published var gravityRoll: Double = 0

    @Published var modality: EquipmentModality = .plateLoadedLever
    @Published var exercise: FreeWeightExercise = .bicepsCurl
    @Published var cableJoint: BodyJoint = .shoulder
    @Published var muscle: MuscleProfileKind?
    @Published var machine: MachineProfile?

    // 第一帧上的锚点（Vision 坐标）
    @Published var pivot: CGPoint?
    @Published var weights: [CGPoint] = []
    @Published var loads: [Double] = []        // 0 = 没填
    @Published var pulley: CGPoint?

    @Published var recognition: EquipmentRecognitionOutcome?
    @Published var recognizing = false
    @Published var progress = 0.0
    @Published var result: ResistanceAnalysisResult?
    @Published var error: String?

    @Published var name = ""
    @Published var seat = ""
    @Published var saved = false

    let library = MachineProfileLibrary.load()
    let classifier: EquipmentClassifying = EquipmentClassifierService()
    private var task: Task<Void, Never>?

    static let maxWeights = 3

    var effectiveMuscle: MuscleProfileKind? {
        switch modality {
        case .freeWeight: return exercise.muscleProfile
        case .selectorizedCam: return machine?.muscleProfile
        default: return muscle ?? machine?.muscleProfile
        }
    }

    var canContinue: Bool {
        guard videoURL != nil || modality == .selectorizedCam else { return false }
        if modality == .selectorizedCam { return machine != nil }
        return true
    }

    var anchorsComplete: Bool {
        switch modality {
        case .plateLoadedLever: return pivot != nil && !weights.isEmpty
        case .cablePulley: return pulley != nil
        case .freeWeight, .selectorizedCam: return true
        }
    }

    func load(_ url: URL, roll: Double = 0) async {
        error = nil
        videoURL = url
        gravityRoll = roll
        pivot = nil; weights = []; loads = []; pulley = nil; recognition = nil
        firstFrame = await VideoAnchorTracker.firstFrame(url: url)
        if firstFrame == nil { error = VideoTrackingError.cannotRead.errorDescription }
    }

    func recognize() {
        guard let img = firstFrame else { error = "先录一段或从相册选一段视频"; return }
        recognizing = true
        Task {
            let outcome = await classifier.recognize(img)
            recognizing = false
            recognition = outcome
            if case .confident(let p, _) = outcome {
                machine = p
                modality = p.modality
                if name.isEmpty { name = p.name }
            }
        }
    }

    func next() {
        error = nil
        if modality == .selectorizedCam {
            guard let m = machine else { return }
            let conf: Double? = {
                if case .confident(_, let c) = recognition { return c }
                return nil
            }()
            result = ResistancePhysicsEngine.analyze(profile: m, confidence: conf)
            if name.isEmpty { name = m.name }
            saved = false
            step = .result
            return
        }
        if modality.requiredAnchors.isEmpty { run() } else { step = .anchors }
    }

    func run() {
        guard let url = videoURL else { return }
        var setup = TrackingSetup(modality: modality)
        setup.pivot = pivot
        setup.weights = weights
        setup.pulley = pulley
        setup.gravityRoll = gravityRoll
        switch modality {
        case .freeWeight:
            setup.pivotJoint = exercise.pivotJoint
            setup.weightJoint = exercise.weightJoint
        case .cablePulley:
            setup.pivotJoint = cableJoint
            setup.weightJoint = .wrist
        default: break
        }
        let muscle = effectiveMuscle
        let loads = self.loads
        let modality = self.modality
        let machineId = machine?.id
        progress = 0
        step = .analyzing
        task?.cancel()
        task = Task {
            do {
                let out = try await VideoAnchorTracker.track(url: url, setup: setup) { p in
                    Task { @MainActor in self.progress = p }
                }
                var r = try ResistancePhysicsEngine.analyze(out.physicsInput(weightLoads: loads, muscle: muscle))
                r.matchedMachineId = machineId
                if modality == .freeWeight, name.isEmpty { name = exercise.title }
                result = r
                saved = false
                step = .result
            } catch is CancellationError {
                step = .entry
            } catch {
                self.error = error.localizedDescription
                step = modality.requiredAnchors.isEmpty ? .entry : .anchors
            }
        }
    }

    func cancelAnalysis() {
        task?.cancel()
        step = modality.requiredAnchors.isEmpty ? .entry : .anchors
    }

    func back() {
        switch step {
        case .entry: break
        case .anchors: step = .entry
        case .analyzing: cancelAnalysis()
        case .result: step = modality.requiredAnchors.isEmpty ? .entry : .anchors
        }
    }

    /// 存进“你录过的”，进步页的拉长位 / 中段 / 缩短位按这个算
    func save() {
        guard let r = result else { return }
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        let method: CurveMethod = modality == .freeWeight ? .inHand : .plate
        var c = SavedCurve(name: n, values: r.points.map { $0.resistancePct / 100 }, method: method)
        c.seat = seat.isEmpty ? nil : seat
        c.pattern = r.curvePattern.rawValue
        CurveStore.shared.save(c)
        saved = true
    }
}

// MARK: - 整个流程（sheet）

struct ResistanceCurveFlow: View {
    var names: [String] = []
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = ResistanceFlowModel()

    var body: some View {
        NavigationStack {
            Group {
                switch model.step {
                case .entry: ResistanceAnalysisEntryView(model: model, names: names)
                case .anchors: AnchorSelectionView(model: model)
                case .analyzing: analyzing
                case .result: ResistanceResultView(model: model, names: names)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(model.step == .entry ? "关闭" : "返回") {
                        if model.step == .entry { dismiss() } else { model.back() }
                    }
                }
                if model.step == .result {
                    ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
                }
            }
        }
    }

    private var title: String {
        switch model.step {
        case .entry: return "阻力曲线"
        case .anchors: return "在第一帧上标点"
        case .analyzing: return "正在分析"
        case .result: return "分析结果"
        }
    }

    private var analyzing: some View {
        VStack(spacing: 18) {
            Spacer()
            ProgressView(value: model.progress).tint(resistanceAccent).frame(maxWidth: 260)
            Text("正在一帧一帧看 \(Int(model.progress * 100))%").font(.headline)
            Text(model.modality == .plateLoadedLever ? "追踪挂片的位置，按力臂算阻力" : "认人体关节，按力臂算阻力")
                .font(.subheadline).foregroundStyle(.secondary)
            Button("取消") { model.cancelAnalysis() }.padding(.top, 8)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - 入口：选视频 + 选器械类型

struct ResistanceAnalysisEntryView: View {
    @ObservedObject var model: ResistanceFlowModel
    var names: [String] = []
    @StateObject private var level = LevelMonitor()
    @State private var pick: PhotosPickerItem?
    @State private var camera = false
    @State private var showMachines = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("全部在手机上算，视频不上传").font(.subheadline).foregroundStyle(.secondary)
                videoSection
                if model.videoURL == nil { LevelIndicator(level: level) }
                Text("这是什么器械？").font(.headline).padding(.top, 4)
                ForEach(EquipmentModality.allCases) { m in modeRow(m) }
                recognizeRow
                options
                if let e = model.error {
                    Text(e).font(.footnote).foregroundStyle(.red)
                }
                Button { model.next() } label: {
                    Text(model.modality.requiredAnchors.isEmpty ? (model.modality == .selectorizedCam ? "查看曲线" : "开始分析") : "下一步：标点")
                        .font(.headline).frame(maxWidth: .infinity).frame(height: 50)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(model.canContinue ? Color.primary : Color(.systemGray4)))
                        .foregroundStyle(Color(.systemBackground))
                }
                .buttonStyle(.plain)
                .disabled(!model.canContinue)
                Text("第一帧 = 动作开始。手机放稳，从侧面拍，录完整的 2~3 次。")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .onAppear { level.start() }
        .onDisappear { level.stop() }
        .onChange(of: pick) { _, item in
            guard let item else { return }
            Task {
                if let m = try? await item.loadTransferable(type: PickedMovie.self) { await model.load(m.url, roll: 0) }
                else { model.error = "视频读不出来，换一段试试" }
                pick = nil
            }
        }
        .fullScreenCover(isPresented: $camera) {
            VideoCamera { url in
                let roll = level.endRecording()
                camera = false
                if let url { Task { await model.load(url, roll: roll) } }
            }
            .ignoresSafeArea()
            .onAppear { level.beginRecording() }
        }
        .sheet(isPresented: $showMachines) { machinePicker }
    }

    // 视频
    @ViewBuilder private var videoSection: some View {
        if let img = model.firstFrame {
            HStack(spacing: 12) {
                Image(decorative: img, scale: 1).resizable().scaledToFill()
                    .frame(width: 72, height: 96).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text("视频已选好").font(.subheadline.bold())
                    Text(model.gravityRoll != 0 ? "录的时候歪了 \(Int(abs(model.gravityRoll * 180 / .pi).rounded()))°，会自动校正" : "第一帧会作为动作开始")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 14) {
                        Button("重录") { camera = true }
                        PhotosPicker("换一段", selection: $pick, matching: .videos)
                    }
                    .font(.caption.bold()).tint(resistanceAccent)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        } else {
            HStack(spacing: 10) {
                Button { camera = true } label: {
                    Label("录一段", systemImage: "video.fill").font(.headline).frame(maxWidth: .infinity).frame(height: 50)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary))
                        .foregroundStyle(Color(.systemBackground))
                }
                .buttonStyle(.plain)
                .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                PhotosPicker(selection: $pick, matching: .videos) {
                    Label("从相册选", systemImage: "photo.on.rectangle").font(.headline).frame(maxWidth: .infinity).frame(height: 50)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
                        .foregroundStyle(Color.primary)
                }
            }
        }
    }

    private func icon(_ m: EquipmentModality) -> String {
        switch m {
        case .plateLoadedLever: return "gearshape.2.fill"
        case .cablePulley: return "point.topleft.down.to.point.bottomright.curvepath"
        case .freeWeight: return "dumbbell.fill"
        case .selectorizedCam: return "square.stack.3d.up.fill"
        }
    }

    private func modeRow(_ m: EquipmentModality) -> some View {
        let on = model.modality == m
        return Button { withAnimation(.easeOut(duration: 0.15)) { model.modality = m } } label: {
            HStack(spacing: 12) {
                Image(systemName: icon(m)).font(.system(size: 17)).frame(width: 38, height: 38)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color(.tertiarySystemFill)))
                    .foregroundStyle(on ? resistanceAccent : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.title).font(.subheadline.bold()).foregroundStyle(.primary)
                    Text(m.subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if on { Image(systemName: "checkmark").font(.subheadline.bold()).foregroundStyle(resistanceAccent) }
            }
            .padding(11)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(on ? resistanceAccent : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    // 自动识别
    @ViewBuilder private var recognizeRow: some View {
        HStack(spacing: 6) {
            Text("不确定？").font(.caption).foregroundStyle(.secondary)
            Button(model.recognizing ? "正在认…" : "用第一帧自动认") { model.recognize() }
                .font(.caption.bold()).tint(resistanceAccent)
                .disabled(model.firstFrame == nil || model.recognizing)
        }
        .frame(maxWidth: .infinity)
        if let r = model.recognition {
            switch r {
            case .confident(let p, let c):
                note("认出来是「\(p.name)」（\(Int(c * 100))% 把握），已经帮你选好了")
            case .needsManualPick(let cands):
                VStack(alignment: .leading, spacing: 6) {
                    note(cands.isEmpty ? "没认出来，请手动选器械类型" : "不太确定，是下面哪个？")
                    chips(cands.compactMap(\.profile), title: { p in p.name }, selected: model.machine) { p in
                        model.machine = p; model.modality = p.modality
                        if model.name.isEmpty { model.name = p.name }
                    }
                }
            case .unavailable:
                note("器械识别模型还没装进 App，先手动选上面的类型。挂片和绳索器械点几下就能算")
            }
        }
    }

    private func note(_ s: String) -> some View {
        Text(s).font(.caption).foregroundStyle(.secondary)
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.tertiarySystemFill)))
    }

    // 各模式的补充选项
    @ViewBuilder private var options: some View {
        switch model.modality {
        case .freeWeight:
            section("做的什么动作") {
                chips(FreeWeightExercise.allCases, title: { $0.title }, selected: model.exercise) { model.exercise = $0 }
            }
            Text("按\(model.exercise.pivotJoint.title)和手腕自动认，不用点").font(.caption).foregroundStyle(.secondary)
        case .cablePulley:
            section("绕哪个关节转") {
                chips([BodyJoint.shoulder, .elbow, .hip, .knee], title: { $0.title }, selected: model.cableJoint) { model.cableJoint = $0 }
            }
            muscleSection
        case .plateLoadedLever:
            muscleSection
        case .selectorizedCam:
            section("哪台器械") {
                Button { showMachines = true } label: {
                    HStack {
                        Text(model.machine?.name ?? "选一台器械").font(.subheadline.bold())
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
                }
                .buttonStyle(.plain)
            }
            Text("插片器械不用视频，按型号查本地曲线库").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var muscleSection: some View {
        section("主要练哪块肌肉（选了会画出肌肉发力曲线）") {
            chips(MuscleProfileKind.allCases, title: { $0.title }, selected: model.muscle) { k in
                model.muscle = model.muscle == k ? nil : k
            }
        }
    }

    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.footnote.bold()).foregroundStyle(.secondary)
            content()
        }
    }

    private func chips<T: Hashable>(_ items: [T], title: @escaping (T) -> String, selected: T?, tap: @escaping (T) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(items, id: \.self) { it in
                    let on = it == selected
                    Button { tap(it) } label: {
                        Text(title(it)).font(.footnote.weight(on ? .bold : .regular))
                            .padding(.horizontal, 11).padding(.vertical, 7)
                            .background(Capsule().fill(on ? Color.primary : Color(.secondarySystemGroupedBackground)))
                            .foregroundStyle(on ? Color(.systemBackground) : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var machinePicker: some View {
        NavigationStack {
            List(model.library.profiles) { p in
                Button {
                    model.machine = p
                    if model.name.isEmpty { model.name = p.name }
                    showMachines = false
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name).font(.body.bold()).foregroundStyle(.primary)
                            Text(p.modality.title + " · " + p.muscleProfile.title).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(ResistancePhysicsEngine.classify(p.defaultCurve).pattern.title).font(.caption).foregroundStyle(resistanceAccent)
                    }
                }
            }
            .navigationTitle("选器械")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { showMachines = false } } }
        }
    }
}
