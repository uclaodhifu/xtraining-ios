import SwiftUI
import CoreGraphics

/// 第一帧上标点：支点 / 挂片（1~3 个，可填公斤）/ 滑轮。按住圆点能拖动微调，拖的时候出放大镜。
struct AnchorSelectionView: View {
    @ObservedObject var model: ResistanceFlowModel

    private enum Handle: Equatable { case pivot, weight(Int), pulley }

    @State private var dragging: Handle?
    @State private var dragPoint: CGPoint?       // 界面坐标（放大镜位置）
    @State private var selectedWeight = 0

    private let loadOptions: [Double] = [0, 5, 10, 15, 20, 25]
    private let hitRadius: CGFloat = 30
    private let loupeSize: CGFloat = 110
    private let zoom: CGFloat = 2.5

    var body: some View {
        VStack(spacing: 0) {
            header
            GeometryReader { geo in
                if let img = model.firstFrame {
                    canvas(img, size: geo.size)
                } else {
                    Text("第一帧读不出来").foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            controls
        }
        .background(Color(hex: 0x15171a).ignoresSafeArea())
        .environment(\.colorScheme, .dark)
    }

    // MARK: 顶部提示 + 进度

    private var steps: [String] {
        model.modality == .plateLoadedLever ? ["支点", "挂片", "分析"] : ["滑轮", "分析"]
    }

    private var stepIndex: Int {
        switch model.modality {
        case .plateLoadedLever: return model.pivot == nil ? 0 : (model.weights.isEmpty ? 1 : 2)
        default: return model.pulley == nil ? 0 : 1
        }
    }

    private var hint: String {
        switch model.modality {
        case .plateLoadedLever:
            if model.pivot == nil { return AnchorRole.pivot.hint }
            if model.weights.isEmpty { return "点挂片的位置，有几个点几个" }
            return model.weights.count < ResistanceFlowModel.maxWeights ? "还有挂片可以继续点，没有就开始分析" : "挂片点好了，可以开始分析"
        default:
            return model.pulley == nil ? AnchorRole.pulley.hint : "点好了，可以开始分析"
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("第 \(stepIndex + 1) 步 / 共 \(steps.count) 步").font(.headline).foregroundStyle(.white)
            Text(hint).font(.subheadline.bold()).foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(Capsule().fill(.white.opacity(0.16)))
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.2))
                    Capsule().fill(resistanceAccent).frame(width: g.size.width * CGFloat(stepIndex + 1) / CGFloat(steps.count))
                }
            }
            .frame(width: 160, height: 4)
            .animation(.easeOut(duration: 0.2), value: stepIndex)
        }
        .padding(.top, 10).padding(.bottom, 12)
    }

    // MARK: 画面 + 标点

    private func canvas(_ img: CGImage, size: CGSize) -> some View {
        let conv = VideoCoordinateConverter(uprightSize: CGSize(width: img.width, height: img.height))
        let rect = conv.imageRect(in: size)
        return ZStack(alignment: .topLeading) {
            Image(decorative: img, scale: 1).resizable().aspectRatio(contentMode: .fit)
                .frame(width: size.width, height: size.height)
            // 挂片到支点的连线
            if let p = model.pivot {
                ForEach(model.weights.indices, id: \.self) { i in
                    Path { path in
                        path.move(to: conv.visionToView(p, viewSize: size))
                        path.addLine(to: conv.visionToView(model.weights[i], viewSize: size))
                    }
                    .stroke(.white.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                }
            }
            if let p = model.pivot { marker(conv.visionToView(p, viewSize: size), color: Color(hex: 0x4dabf7), label: AnchorRole.pivot.title) }
            if let p = model.pulley { marker(conv.visionToView(p, viewSize: size), color: Color(hex: 0x4dabf7), label: AnchorRole.pulley.title) }
            ForEach(model.weights.indices, id: \.self) { i in
                marker(conv.visionToView(model.weights[i], viewSize: size), color: resistanceAccent, label: weightLabel(i),
                       selected: model.weights.count > 1 && i == selectedWeight)
            }
            if let d = dragPoint, dragging != nil {
                loupe(img, at: d, rect: rect)
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { v in
                    if dragging == nil {
                        dragging = hit(v.startLocation, conv: conv, size: size)
                        if case .weight(let i) = dragging { selectedWeight = i }
                    }
                    guard let h = dragging else { return }
                    let p = clamp(v.location, to: rect)
                    dragPoint = p
                    if let vp = conv.viewToVision(p, viewSize: size) { set(h, vp) }
                }
                .onEnded { v in
                    defer { dragging = nil; dragPoint = nil }
                    if dragging == nil, hypot(v.translation.width, v.translation.height) < 10,
                       let vp = conv.viewToVision(v.location, viewSize: size) {
                        place(vp)
                    }
                }
        )
    }

    private func weightLabel(_ i: Int) -> String {
        let kg = i < model.loads.count ? model.loads[i] : 0
        let base = model.weights.count > 1 ? "挂片 \(i + 1)" : "挂片"
        return kg > 0 ? "\(base) · \(Int(kg))kg" : base
    }

    private func marker(_ p: CGPoint, color: Color, label: String, selected: Bool = false) -> some View {
        ZStack {
            Circle().fill(color).frame(width: 20, height: 20)
                .overlay(Circle().stroke(.white, lineWidth: 3))
            if selected { Circle().stroke(.white, lineWidth: 2).frame(width: 34, height: 34) }
            Text(label).font(.caption.bold()).foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(.black.opacity(0.55)))
                .fixedSize()
                .offset(y: -24)
        }
        .position(p)
        .allowsHitTesting(false)
    }

    /// 放大镜：显示手指下方的画面放大 2.5 倍，放在手指上方，免得被手指挡住
    private func loupe(_ img: CGImage, at p: CGPoint, rect: CGRect) -> some View {
        let L = loupeSize
        let w = rect.width * zoom, h = rect.height * zoom
        let cx = L / 2 - (p.x - rect.minX) * zoom + w / 2
        let cy = L / 2 - (p.y - rect.minY) * zoom + h / 2
        let above = p.y - L / 2 - 50
        let y = above > L / 2 ? above : p.y + L / 2 + 50
        return ZStack {
            Color.black
            Image(decorative: img, scale: 1).resizable().frame(width: w, height: h).position(x: cx, y: cy)
            Path { path in
                path.move(to: CGPoint(x: L / 2, y: L / 2 - 14)); path.addLine(to: CGPoint(x: L / 2, y: L / 2 + 14))
                path.move(to: CGPoint(x: L / 2 - 14, y: L / 2)); path.addLine(to: CGPoint(x: L / 2 + 14, y: L / 2))
            }
            .stroke(.white, lineWidth: 1.5)
        }
        .frame(width: L, height: L)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white, lineWidth: 3))
        .shadow(radius: 6)
        .position(x: p.x, y: y)
        .allowsHitTesting(false)
    }

    // MARK: 点的增删改

    private func hit(_ p: CGPoint, conv: VideoCoordinateConverter, size: CGSize) -> Handle? {
        var best: (Handle, CGFloat)?
        func consider(_ h: Handle, _ v: CGPoint?) {
            guard let v else { return }
            let q = conv.visionToView(v, viewSize: size)
            let d = hypot(q.x - p.x, q.y - p.y)
            if d < hitRadius && (best == nil || d < best!.1) { best = (h, d) }
        }
        consider(.pivot, model.pivot)
        consider(.pulley, model.pulley)
        for i in model.weights.indices { consider(.weight(i), model.weights[i]) }
        return best?.0
    }

    private func set(_ h: Handle, _ v: CGPoint) {
        switch h {
        case .pivot: model.pivot = v
        case .pulley: model.pulley = v
        case .weight(let i): if i < model.weights.count { model.weights[i] = v }
        }
    }

    private func place(_ v: CGPoint) {
        switch model.modality {
        case .plateLoadedLever:
            if model.pivot == nil {
                model.pivot = v
            } else if model.weights.count < ResistanceFlowModel.maxWeights {
                model.weights.append(v)
                model.loads.append(0)
                selectedWeight = model.weights.count - 1
            }
        case .cablePulley:
            model.pulley = v
        default: break
        }
    }

    private func undo() {
        switch model.modality {
        case .plateLoadedLever:
            if !model.weights.isEmpty {
                model.weights.removeLast()
                if !model.loads.isEmpty { model.loads.removeLast() }
                selectedWeight = max(0, model.weights.count - 1)
            } else {
                model.pivot = nil
            }
        default:
            model.pulley = nil
        }
    }

    private func clamp(_ p: CGPoint, to r: CGRect) -> CGPoint {
        CGPoint(x: min(max(p.x, r.minX + 0.5), r.maxX - 0.5), y: min(max(p.y, r.minY + 0.5), r.maxY - 0.5))
    }

    // MARK: 底部

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.modality == .plateLoadedLever, !model.weights.isEmpty, selectedWeight < model.weights.count {
                HStack(spacing: 6) {
                    Text(model.weights.count > 1 ? "挂片 \(selectedWeight + 1) 挂了多少" : "挂了多少").font(.footnote).foregroundStyle(.white)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 5) {
                            ForEach(loadOptions, id: \.self) { kg in
                                let on = selectedWeight < model.loads.count && model.loads[selectedWeight] == kg
                                Button {
                                    while model.loads.count < model.weights.count { model.loads.append(0) }
                                    model.loads[selectedWeight] = kg
                                } label: {
                                    Text(kg == 0 ? "不填" : "\(Int(kg))").font(.footnote.weight(on ? .bold : .regular))
                                        .padding(.horizontal, 10).padding(.vertical, 5)
                                        .background(Capsule().fill(on ? resistanceAccent : .white.opacity(0.14)))
                                        .foregroundStyle(.white)
                                }
                                .buttonStyle(.plain)
                            }
                            Text("kg").font(.footnote).foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }
                if model.weights.count > 1 {
                    Text("点一下挂片可以切换；不填就当每个挂片一样重").font(.caption).foregroundStyle(.white.opacity(0.6))
                }
            }
            Text("按住圆点可以拖动微调，会出现放大镜").font(.caption).foregroundStyle(.white.opacity(0.6))
            if let e = model.error { Text(e).font(.footnote).foregroundStyle(Color(hex: 0xffa94d)) }
            HStack(spacing: 8) {
                Button { undo() } label: {
                    Text("撤销").font(.subheadline.bold()).frame(maxWidth: .infinity).frame(height: 48)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.16)))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(model.pivot == nil && model.weights.isEmpty && model.pulley == nil)
                Button { model.run() } label: {
                    Text("开始分析").font(.headline).frame(maxWidth: .infinity).frame(height: 48)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(model.anchorsComplete ? resistanceAccent : .white.opacity(0.1)))
                        .foregroundStyle(.white.opacity(model.anchorsComplete ? 1 : 0.4))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .layoutPriority(1)
                .disabled(!model.anchorsComplete)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.1)))
        .padding(.horizontal, 16).padding(.bottom, 12)
    }
}
