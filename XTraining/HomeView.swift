import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: Store
    @AppStorage("brandTitle") private var brandTitle = ""
    @AppStorage("brandEmo") private var brandEmo = ""
    @State private var editTitle = false
    @State private var celebrate = false
    @State private var picked: [String]? = nil
    @State private var editing: Workout? = nil
    @State private var hasDraft = EntryDraft.load() != nil
    @State private var showCycle = false
    @State private var showPrep = false
    @ObservedObject private var prep = PrepStore.shared
    @State private var showWeight = false
    @State private var showAll = false
    @State private var query = ""

    private var cycleOn: Bool { store.cycle.on && !store.cycle.start.isEmpty }
    private var cycleIndex: Int { store.cycle.index() }
    private var cycleStep: [String] { cycleOn && cycleIndex < store.cycle.steps.count ? store.cycle.steps[cycleIndex] : [] }
    private var chosen: Binding<[String]> {
        Binding(get: { picked ?? (cycleOn ? cycleStep : []) }, set: { picked = $0 })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    header.rise(0)
                    planCard.rise(1)
                    RaceAlert().rise(2)
                    DataWall { showWeight = true }.rise(3)
                    historySection.rise(4)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .background(background)
            .toolbar(.hidden, for: .navigationBar)
            .overlay { if celebrate && !Motion.reduce { Confetti() } }
            .sheet(isPresented: $editTitle) { TitleEditor() }
            .sheet(item: $editing, onDismiss: { hasDraft = EntryDraft.load() != nil }) { w in EntryView(workout: w) }
            .onAppear { hasDraft = EntryDraft.load() != nil }
            .sheet(isPresented: $showCycle) { CycleEditor() }
            .sheet(isPresented: $showPrep) { PrepView() }
            .sheet(isPresented: $showWeight) { WeightView() }
        }
    }

    // 顶部：大标题（点一下改字、换动画）+ 记一笔
    private var header: some View {
        HStack(spacing: 8) {
            Button { editTitle = true } label: {
                HStack(spacing: 6) {
                    if brandTitle.isEmpty { XLogo() } else { Text(brandTitle).font(.system(size: 32, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.6) }
                    if !brandEmo.isEmpty { BadgeView(id: brandEmo, size: 24) }
                }
            }
            .buttonStyle(.plain)
            Spacer()
            AvatarView(size: 38)
            Button { Haptic.tap(.medium); editing = newWorkout(chosen.wrappedValue) } label: {
                Image(systemName: "plus").font(.title3.bold()).foregroundStyle(Brand.ink)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Brand.gradient))
                    .shadow(color: Brand.pink.opacity(0.35), radius: 8, y: 4)
            }
            .buttonStyle(PressScale())
        }
        .padding(.top, 8)
    }

    // 淡淡的渐变光斑背景，跟着主题变色，慢慢飘
    private var background: some View {
        let b = Skin.current.blobs
        return TimelineView(.animation(minimumInterval: 1 / 20, paused: Motion.calm)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            ZStack {
                Color(.systemGroupedBackground)
                Circle().fill(b[0].opacity(0.18)).frame(width: 380).blur(radius: 90).offset(x: -160 + sin(t / 6) * 30, y: -300 + cos(t / 7) * 20)
                Circle().fill(b[1].opacity(0.16)).frame(width: 420).blur(radius: 100).offset(x: 170 + cos(t / 8) * 30, y: 40 + sin(t / 5) * 30)
                Circle().fill(b[2].opacity(0.14)).frame(width: 360).blur(radius: 90).offset(x: -120 + sin(t / 9) * 25, y: 420 + cos(t / 6) * 25)
            }
        }
        .ignoresSafeArea()
    }

    private func newWorkout(_ parts: [String]) -> Workout {
        // 有今天没保存的草稿，就接着记
        if let d = EntryDraft.load(), !store.workouts.contains(where: { $0.id == d.id }) { return d }
        var w = Workout(); w.parts = parts; return w
    }

    // MARK: 今天练什么
    @ViewBuilder private var planCard: some View {
        let today = Day.today
        let trained = !store.todays.isEmpty
        if store.restDays.contains(today) && !trained {
            BigCard {
                HeroBanner(tag: "今天练什么", title: "今天是休息日 😴", sub: "肌肉是在休息的时候长起来的，好好吃、好好睡")
                Button("还是去练一下") { store.setRest(false) }
                    .font(.subheadline.bold()).frame(maxWidth: .infinity).padding(16)
            }
        } else if store.doneDays.contains(today) && trained {
            let ws = store.todays
            BigCard {
                HeroBanner(tag: "今天练什么", title: "今天练完了 ✓", sub: todayParts(ws))
                VStack(spacing: 10) {
                HStack {
                    StatTile(value: "\(ws.reduce(0) { $0 + $1.exercises.count })", label: "动作")
                    StatTile(value: "\(ws.reduce(0) { $0 + $1.setCount })", label: "组")
                    StatTile(value: "\(store.streak)", label: "连续天数")
                }
                Button("还要继续练") { store.setDone(false) }
                }
                .frame(maxWidth: .infinity).padding(16)
            }
        } else {
            BigCard {
                HeroBanner(tag: "今天练什么", title: heroTitle, sub: why,
                           button: hasDraft ? "继续训练" : (chosen.wrappedValue.isEmpty ? "开始训练" : "开始训练 · " + chosen.wrappedValue.joined(separator: " + ")),
                           action: { Haptic.tap(.medium); editing = newWorkout(chosen.wrappedValue) }) {
                    HStack(spacing: 8) {
                        Button { showCycle = true } label: {
                            Text(cycleOn ? "周期" : "＋ 周期").font(.footnote.bold()).foregroundStyle(.white)
                                .padding(.horizontal, 12).frame(height: 34).background(.ultraThinMaterial, in: Capsule())
                        }
                        Button { showPrep = true } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "trophy.fill").font(.caption2)
                                Text(prep.daysLeft.map { $0 >= 0 ? "备赛 \($0)天" : "备赛" } ?? (prep.active ? "备赛" : "＋ 备赛"))
                            }
                            .font(.footnote.bold()).foregroundStyle(.white)
                            .padding(.horizontal, 12).frame(height: 34).background(.ultraThinMaterial, in: Capsule())
                        }
                    }
                }
            VStack(alignment: .leading, spacing: 12) {
                if cycleOn { cycleRow }
                PartChips(parts: Parts.all, selected: chosen)
                restRow
                ideas
                if !trained {
                    // 次要操作做小一点，不跟“开始训练”抢视线
                    Button { Haptic.tap(); store.setRest(true) } label: {
                        Label("今天休息", systemImage: "moon.zzz.fill").font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(Capsule().fill(Color(.tertiarySystemFill)))
                    }
                    .buttonStyle(PressScale())
                    .frame(maxWidth: .infinity)
                } else {
                    BigButton(title: "✓ 完成今天训练 · \(store.todays.reduce(0) { $0 + $1.setCount }) 组") { Haptic.success(); withAnimation(.spring) { store.setDone(true) }; celebrate = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { celebrate = false } }
                }
            }
            .padding(16)
            }
        }
    }

    private var heroTitle: String {
        let c = chosen.wrappedValue
        if store.restDays.contains(Day.today) && store.todays.isEmpty { return "今天休息" }
        if store.doneDays.contains(Day.today) { return "今天练完了" }
        return c.isEmpty ? "今天练什么？" : "今天练" + c.joined(separator: " + ")
    }

    private func todayParts(_ ws: [Workout]) -> String {
        let set = Set(ws.flatMap { $0.parts })
        return Parts.all.filter { set.contains($0) }.joined(separator: " + ")
    }

    private var why: String {
        if cycleOn {
            let n = store.cycle.steps.count
            return cycleStep.isEmpty ? "周期第 \(cycleIndex + 1)/\(n) 天 · 按计划今天休息" : "周期第 \(cycleIndex + 1)/\(n) 天 · " + Cycle.name(cycleStep)
        }
        if store.workouts.isEmpty { return "还没有记录，先从一个部位开始吧" }
        let rest = Parts.all.map { p in (p, store.lastTrained(p).map { Day.between($0, Day.today) }) }
        guard let top = rest.max(by: { ($0.1 ?? 99) < ($1.1 ?? 99) }) else { return "" }
        if top.1 == nil { return "\(top.0)还没练过" }
        if top.1 == 0 { return "今天都练过了，休息一下也不错" }
        return "\(top.0)已经 \(top.1!) 天没练了"
    }

    private var cycleRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(store.cycle.steps.enumerated()), id: \.offset) { k, s in
                    let on = k == cycleIndex
                    Button {
                        if !on { store.cycle.start = Cycle.startFor(k); picked = nil }
                    } label: {
                        HStack(spacing: 4) {
                            Text("\(k + 1)").font(.caption2).opacity(0.7)
                            Text(Cycle.name(s)).font(.footnote.bold())
                        }
                        .padding(.horizontal, 11).padding(.vertical, 6)
                        .foregroundStyle(on ? Color.white : (s.isEmpty ? Color.secondary : Color.primary))
                        .background(on ? (s.first.map(Parts.color) ?? Color.primary) : Color(.tertiarySystemFill), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var restRow: some View {
        let items = Parts.all.map { p -> (String, String) in
            guard let d = store.lastTrained(p) else { return (p, "未练") }
            let n = Day.between(d, Day.today)
            return (p, n == 0 ? "今天" : "\(n)天")
        }
        return FlowRow(items: items)
    }

    @ViewBuilder private var ideas: some View {
        let names = chosen.wrappedValue.flatMap { (Parts.library[$0] ?? []).prefix(2) }
        if !names.isEmpty {
            VStack(spacing: 6) {
                ForEach(names, id: \.self) { n in
                    HStack {
                        Text(n).font(.subheadline.bold())
                        Spacer()
                        if let s = store.lastSet(n) {
                            Text("上次 \(s.w.isEmpty ? "0" : s.w)kg × \(s.r.isEmpty ? "0" : s.r)").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("还没练过").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                }
            }
        }
    }

    // MARK: 训练日志（替换原来的“我的训练”）
    private var historySection: some View {
        HomeLog { w in editing = w }
    }

    private func matches(_ w: Workout, _ q: String) -> Bool {
        let hay = ([w.date, Day.label(w.date), w.title, w.note] + w.parts + w.exercises.map(\.name)).joined(separator: " ").lowercased()
        return q.lowercased().split(separator: " ").allSatisfy { hay.contains($0) }
    }
}

// 每个部位多久没练：小圆点 + 文字，自动换行
struct FlowRow: View {
    let items: [(String, String)]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 6, alignment: .leading)], alignment: .leading, spacing: 4) {
            ForEach(items, id: \.0) { p, t in
                HStack(spacing: 5) {
                    Circle().fill(Parts.color(p)).frame(width: 7, height: 7)
                    Text("\(p) \(t)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// 按下去缩一下
struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// 改首页标题 + 选后面的小动画
struct TitleEditor: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("brandTitle") private var brandTitle = ""
    @AppStorage("brandEmo") private var brandEmo = ""
    @State private var t = ""
    @State private var emo = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 6) {
                        if t.trimmingCharacters(in: .whitespaces).isEmpty { XLogo() } else { Text(t).font(.system(size: 30, weight: .heavy)) }
                        if !emo.isEmpty { BadgeView(id: emo, size: 24) }
                    }
                    .frame(maxWidth: .infinity, minHeight: 60)
                }
                Section("标题") {
                    TextField("不填就用 X TRAINING", text: $t)
                }
                Section("标题后面的动画") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 10)], spacing: 10) {
                        Button { emo = "" } label: { cell(Text("无").font(.headline).foregroundStyle(.secondary), "不要", emo.isEmpty) }
                            .buttonStyle(.plain)
                        ForEach(Badges.all) { b in
                            Button { emo = b.id; Haptic.tap() } label: { cell(BadgeView(id: b.id, size: 26), b.label, emo == b.id) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .navigationTitle("首页标题").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        brandTitle = String(t.trimmingCharacters(in: .whitespaces).prefix(16)); brandEmo = emo; dismiss()
                    }.bold()
                }
            }
            .onAppear { t = brandTitle; emo = brandEmo }
        }
    }

    private func cell<V: View>(_ v: V, _ label: String, _ on: Bool) -> some View {
        VStack(spacing: 4) {
            v.frame(height: 32)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(RoundedRectangle(cornerRadius: 12).fill(on ? Brand.pink.opacity(0.15) : Color(.tertiarySystemFill)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(on ? Brand.pink : .clear, lineWidth: 2))
    }
}
