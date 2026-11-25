import SwiftUI

@main
struct XTrainingApp: App {
    @StateObject private var store = Store()
    @AppStorage("theme") private var theme = "system"

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(theme == "light" ? .light : theme == "dark" ? .dark : nil)
                .tint(Brand.pink)
        }
    }
}
