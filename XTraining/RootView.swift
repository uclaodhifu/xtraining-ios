import SwiftUI

// 底部四个页面：首页 / 追赛 / 进步 / 我（iOS 26 以上是液态玻璃底栏，往下滑会自动收起）
struct RootView: View {
    @State private var tab = 0
    var body: some View {
        let tv = TabView(selection: $tab) {
            HomeView()
                .tabItem { Label("首页", systemImage: "house.fill") }.tag(0)
            RacesView()
                .tabItem { Label("追赛", systemImage: "trophy.fill") }.tag(1)
            ProgressPage()
                .tabItem { Label("进步", systemImage: "chart.line.uptrend.xyaxis") }.tag(2)
            MeView()
                .tabItem { Label("我", systemImage: "person.crop.circle") }.tag(3)
        }
        .sensoryFeedback(.selection, trigger: tab)
        if #available(iOS 26.0, *) {
            tv.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            tv
        }
    }
}
