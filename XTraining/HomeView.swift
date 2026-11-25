import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: Store
    @AppStorage("brandTitle") private var brandTitle = ""
    @State private var picked: [String]? = nil
    @State private var editing: Workout? = nil
    @State private var showCycle = false
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
                    planCard
                    FoodCard()
                    statsCard
                    historySection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .background(background)
            .navigationTitle(brandTitle.isEmpty ? "X Training" : brandTitle)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editing = newWorkout(chosen.wrappedValue) } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                }
            }
            .sheet(item: $editing) { w in EntryView(workout: w) }
            .sheet(isPresented: $showCycle) { CycleEditor() }
            .sheet(isPresented: $showWeight) { WeightView() }
        }
    }

    // 淡淡的 Ins 渐变光斑背景
    private var background: some View {
        ZStack {
            Color(.systemGroupedBackground)
            Circle().fill(Color(hex: 0xfa7e1e).opacity(0.18)).frame(width: 380).blur(radius: 90).offset(x: -160, y: -300)
            Circle().fill(Color(hex: 0xd62976).opacity(0.16)).frame(width: 420).blur(radius: 100).offset(x: 170, y: 40)
            Circle().fill(Color(hex: 0x962fbf).opacity(0.14)).frame(width: 360).blur(radius: 90).offset(x: -120, y: 420)
        }
        .ignoresSafeArea()
    }

    private func newWorkout(_ parts: [String]) -> Workout {
        var w = Workout(); w.parts = parts; return w
    }

    // MARK: 今天练什么
    @ViewBuilder private var planCard: some View {
        let today = Day.today
        let trained = !store.todays.isEmpty
        if store.restDays.contains(today) && !trained {
            VStack(spacing: 10) {
                Text("😴").font(.system(size: 44))
                Text("今天是休息日").font(.title3.bold())
                Text("肌肉是在休息的时候长起来的，好好吃、好好睡").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("还是去练一下") { store.setRest(false) }
            }
            .frame(maxWidth: .infinity).card()
        } else if store.doneDays.contains(today) && trained {
            let ws = store.todays
            VStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 44)).foregroundStyle(Brand.gradient)
                Text("今天的训练完成了").font(.title3.bold())
                Text(todayParts(ws)).foregroundStyle(.secondary)
                HStack {
                    StatTile(value: "\(ws.reduce(0) { $0 + $1.exercises.count })", label: "动作")
                    StatTile(value: "\(ws.reduce(0) { $0 + $1.setCount })", label: "组")
                    StatTile(value: "\(store.streak)", label: "连续天数")
                }
                Button("还要继续练") { store.setDone(false) }
            }
            .frame(maxWidth: .infinity).card()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("今天练什么").font(.title2.bold())
                        Text(why).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(cycleOn ? "周期" : "＋ 周期计划") { showCycle = true }
                        .font(.footnote.bold()).buttonStyle(.bordered).buttonBorderShape(.capsule)
                }
                if cycleOn { cycleRow }
                PartChips(parts: Parts.all, selected: chosen)
                restRow
                ideas
                BigButton(title: chosen.wrappedValue.isEmpty ? "开始训练" : "开始训练 · " + chosen.wrappedValue.joined(separator: " + ")) {
                    Haptic.tap(.medium); editing = newWorkout(chosen.wrappedValue)
                }
                if !trained {
                    BigButton(title: "😴 今天休息日", gradient: false) { store.setRest(true) }
                } else {
                    BigButton(title: "✓ 完成今天训练 · \(store.todays.reduce(0) { $0 + $1.setCount }) 组") { Haptic.success(); store.setDone(true) }
                }
            }
            .card()
        }
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

    // MARK: 统计
    private var statsCard: some View {
        HStack {
            StatTile(value: "\(store.streak)", label: "连续天数")
            StatTile(value: "\(store.weekCount)", label: "本周次数")
            StatTile(value: "\(store.sets7)", label: "近7天组数")
            Button { showWeight = true } label: {
                StatTile(value: store.weights.last.map { fmtNum($0.kg) } ?? "—", label: "体重 kg")
            }
            .buttonStyle(.plain)
        }
        .card()
    }

    // MARK: 我的训练
    @ViewBuilder private var historySection: some View {
        let all = store.sorted
        let found = query.trimmingCharacters(in: .whitespaces).isEmpty ? nil : all.filter { matches($0, query) }
        let list = found ?? (showAll ? all : Array(all.prefix(6)))
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("我的训练").font(.title3.bold())
                if let f = found { Text("找到 \(f.count) 条").font(.caption).foregroundStyle(.secondary) }
            }
            if !all.isEmpty {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜动作、部位、日期，如 卧推 11月", text: $query)
                    if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) } }
                }
                .padding(10)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
            }
            if all.isEmpty {
                Text("还没有训练记录。点“开始训练”记一笔。").foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 20)
            }
            ForEach(list) { w in
                Button { editing = w } label: { WorkoutCard(w: w) }.buttonStyle(.plain)
            }
            if found == nil && all.count > 6 {
                Button(showAll ? "收起" : "查看更多（还有 \(all.count - 6) 条）") { withAnimation { showAll.toggle() } }
                    .frame(maxWidth: .infinity)
            }
        }
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
