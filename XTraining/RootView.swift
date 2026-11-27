import SwiftUI

// 底部四个页面：首页 / 赛事 / 进步 / 我（iOS 26 以上是液态玻璃底栏，往下滑会自动收起）
struct RootView: View {
    @EnvironmentObject var store: Store
    @Environment(\.scenePhase) private var phase
    @State private var tab = 0
    var body: some View {
        let tv = TabView(selection: $tab) {
            HomeView()
                .tabItem { Label("首页", systemImage: "house.fill") }.tag(0)
            RacesView()
                .tabItem { Label("赛事", systemImage: "trophy.fill") }.tag(1)
            ProgressPage()
                .tabItem { Label("进步", systemImage: "chart.line.uptrend.xyaxis") }.tag(2)
            MeView()
                .tabItem { Label("我", systemImage: "person.crop.circle") }.tag(3)
        }
        .sensoryFeedback(.selection, trigger: tab)
        .onChange(of: tab) { _, t in logTab(t) }
        .onChange(of: phase) { _, p in logPhase(p) }
        // 每次打开/回到 App 都拉一下最新比赛清单
        .task(id: phase) {
            if phase == .active { await RaceFeed.shared.refresh(follow: store.follow) }
        }
        if #available(iOS 26.0, *) {
            tv.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            tv
        }
    }
    private func logTab(_ t: Int) {
        let names: [String] = ["首页", "赛事", "进步", "我"]
        BugLog.add("页面 " + names[min(t, 3)])
    }
    private func logPhase(_ p: ScenePhase) {
        let s: String
        switch p {
        case .active: s = "回到 App"
        case .background: s = "切到后台"
        default: s = "App 不在前台"
        }
        BugLog.add(s)
    }
}
