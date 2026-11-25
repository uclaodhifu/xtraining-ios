import SwiftUI

// 底部三个页面：首页 / 进步 / 我
struct RootView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("首页", systemImage: "house.fill") }
            ProgressPage()
                .tabItem { Label("进步", systemImage: "chart.line.uptrend.xyaxis") }
            MeView()
                .tabItem { Label("我", systemImage: "person.crop.circle") }
        }
    }
}
