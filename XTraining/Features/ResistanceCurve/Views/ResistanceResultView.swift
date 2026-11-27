import SwiftUI
import Charts

/// 结果页：结论卡 + 双曲线图（实线 = 器械阻力，虚线 = 肌肉发力能力，可拖动查看）+ 生物力学建议
struct ResistanceResultView: View {
    @ObservedObject var model: ResistanceFlowModel
    var names: [String] = []

    var body: some View {
        ScrollView {
            if let r = model.result {
                VStack(alignment: .leading, spacing: 12) {
                    conclusion(r)
                    ResistanceCurveChart(result: r, muscleTitle: model.effectiveMuscle?.title)
                        .padding(14).background(card)
                    advice(r)
                    saveSection
                }
                .padding(16)
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(.secondarySystemGroupedBackground))
    }

    // MARK: 结论

    private func conclusion(_ r: ResistanceAnalysisResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(r.curvePattern.title).font(.system(size: 26, weight: .heavy))
                Text(badge(r.curvePattern)).font(.caption.weight(.heavy)).foregroundStyle(resistanceAccent)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(resistanceAccent.opacity(0.12)))
            }
            Text(r.curvePattern.shortText).font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                stat("最吃力的位置", "\(r.peakRomPercent)%")
                stat("最轻比最重轻", "\(Int(r.dropoffPercent.rounded()))%")
                if let n = r.reps { stat("做了", "\(n) 次") }
                else { stat("方式", r.modality.title) }
            }
        }
        .padding(16).background(card)
    }

    private func badge(_ p: CurvePattern) -> String {
        switch p {
        case .descending: return "拉长位最吃力"
        case .ascending: return "缩短位最吃力"
        case .bellShaped: return "中段最吃力"
        case .flat: return "全程均匀"
        case .complex: return "有起伏"
        }
    }

    private func stat(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(k).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            Text(v).font(.system(size: 19, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.tertiarySystemFill)))
    }

    // MARK: 建议

    private func advice(_ r: ResistanceAnalysisResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("怎么练更好").font(.headline)
            if let m = r.lengthenedMatch {
                let c: Color = m >= 80 ? Color(hex: 0x2f9e44) : m >= 60 ? Color(hex: 0xf59f00) : Color(hex: 0xe03131)
                HStack {
                    Text("拉长位匹配度").font(.subheadline)
                    Spacer()
                    Text("\(Int(m.rounded())) 分").font(.subheadline.bold()).foregroundStyle(c)
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(.tertiarySystemFill))
                        Capsule().fill(c).frame(width: g.size.width * CGFloat(m / 100))
                    }
                }
                .frame(height: 6)
            }
            if let w = r.peakWarning { warning(w) }
            if let w = r.camWarning { warning(w) }
            Text(r.coachingSummary).font(.subheadline).foregroundStyle(.primary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            if let s = r.trackingStability {
                Text("追踪稳定率 \(Int((s * 100).rounded()))%").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(16).background(card)
    }

    private func warning(_ s: String) -> some View {
        Text(s).font(.footnote).foregroundStyle(Color(hex: 0x946c00))
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: 0xfff3bf)))
    }

    // MARK: 保存

    private var saveSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("存下这台器械").font(.headline)
            TextField("动作名，比如 坐姿推胸", text: $model.name)
                .textFieldStyle(.roundedBorder)
            if !names.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(names.prefix(12), id: \.self) { n in
                            Button(n) { model.name = n }
                                .font(.footnote).padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Capsule().fill(Color(.tertiarySystemFill)))
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
            TextField("座椅档位（可不填）", text: $model.seat).textFieldStyle(.roundedBorder)
            Button { model.save() } label: {
                Text(model.saved ? "已存好 ✓" : "存下来").font(.headline).frame(maxWidth: .infinity).frame(height: 50)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(model.saved ? Color(hex: 0x2f9e44) : Color.primary))
                    .foregroundStyle(Color(.systemBackground))
            }
            .buttonStyle(.plain)
            .disabled(model.name.trimmingCharacters(in: .whitespaces).isEmpty)
            Text("存下后，进步页里这个动作就按你录的曲线算拉长位 / 中段 / 缩短位").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(16).background(card)
    }
}

/// 双曲线图：器械阻力（实线 + 渐变）+ 肌肉发力能力（虚线），手指拖动看每个位置
struct ResistanceCurveChart: View {
    let result: ResistanceAnalysisResult
    var muscleTitle: String?
    @State private var selected: Double?

    private let machineSeries = "器械阻力"
    private let muscleSeries = "肌肉发力"

    var body: some View {
        let pts = result.points
        let hasMuscle = pts.contains { $0.muscleForcePct != nil }
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("阻力曲线").font(.headline)
                Spacer()
                Text("拖动看每个位置").font(.caption).foregroundStyle(.secondary)
            }
            Chart {
                ForEach(pts) { p in
                    AreaMark(x: .value("动作进度", p.romPercent), y: .value("阻力", p.resistancePct))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(LinearGradient(colors: [resistanceAccent.opacity(0.28), resistanceAccent.opacity(0)],
                                                        startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("动作进度", p.romPercent), y: .value("阻力", p.resistancePct),
                             series: .value("曲线", machineSeries))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(resistanceAccent)
                        .lineStyle(StrokeStyle(lineWidth: 3.5, lineCap: .round))
                }
                if hasMuscle {
                    ForEach(pts) { p in
                        if let m = p.muscleForcePct {
                            LineMark(x: .value("动作进度", p.romPercent), y: .value("阻力", m),
                                     series: .value("曲线", muscleSeries))
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(Color(.systemGray))
                                .lineStyle(StrokeStyle(lineWidth: 2.2, dash: [6, 5]))
                        }
                    }
                }
                if let s = selected, let p = point(at: s) {
                    RuleMark(x: .value("动作进度", p.romPercent))
                        .foregroundStyle(Color(.systemGray3))
                        .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            Text(tooltip(p)).font(.caption.bold()).foregroundStyle(.white)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color(white: 0.12)))
                        }
                    PointMark(x: .value("动作进度", p.romPercent), y: .value("阻力", p.resistancePct))
                        .foregroundStyle(resistanceAccent).symbolSize(70)
                    if let m = p.muscleForcePct {
                        PointMark(x: .value("动作进度", p.romPercent), y: .value("阻力", m))
                            .foregroundStyle(Color(.systemGray)).symbolSize(45)
                    }
                }
            }
            .chartXScale(domain: 0...100)
            .chartYScale(domain: 0...110)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: [0, 50, 100]) { v in
                    AxisGridLine()
                    AxisValueLabel {
                        if let x = v.as(Double.self) {
                            Text(x == 0 ? "0% 拉长位" : x == 100 ? "100% 缩短位" : "50%").font(.caption2)
                        }
                    }
                }
            }
            .chartLegend(.hidden)
            .chartOverlay { proxy in
                GeometryReader { g in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { v in
                                    guard let frame = proxy.plotFrame else { return }
                                    let x = v.location.x - g[frame].origin.x
                                    if let rom: Double = proxy.value(atX: x) {
                                        selected = min(100, max(0, (rom / 5).rounded() * 5))
                                    }
                                }
                                .onEnded { _ in }
                        )
                }
            }
            .frame(height: 200)
            .padding(.top, 18)
            HStack(spacing: 14) {
                legend(color: resistanceAccent, dashed: false, text: machineSeries)
                if hasMuscle { legend(color: Color(.systemGray), dashed: true, text: (muscleTitle ?? "肌肉") + "发力能力") }
            }
        }
    }

    private func point(at rom: Double) -> ResistancePoint? {
        result.points.min { abs($0.romPercent - rom) < abs($1.romPercent - rom) }
    }

    private func tooltip(_ p: ResistancePoint) -> String {
        var s = "\(Int(p.romPercent))% · 阻力 \(Int(p.resistancePct.rounded()))"
        if let m = p.muscleForcePct { s += " · 肌肉 \(Int(m.rounded()))" }
        return s
    }

    private func legend(color: Color, dashed: Bool, text: String) -> some View {
        HStack(spacing: 5) {
            Path { p in p.move(to: CGPoint(x: 0, y: 2)); p.addLine(to: CGPoint(x: 18, y: 2)) }
                .stroke(color, style: StrokeStyle(lineWidth: dashed ? 2 : 3, dash: dashed ? [4, 3] : []))
                .frame(width: 18, height: 4)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }
}
