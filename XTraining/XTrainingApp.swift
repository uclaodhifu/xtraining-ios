import SwiftUI

@main
struct XTrainingApp: App {
    @StateObject private var store = Store()
    @AppStorage("theme") private var theme = "system"
    @AppStorage("skin") private var skin = "ins"

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(theme == "light" ? .light : theme == "dark" ? .dark : nil)
                .tint(Brand.pink)
                .fontDesign(.rounded)
                .id(skin)
        }
    }
}
