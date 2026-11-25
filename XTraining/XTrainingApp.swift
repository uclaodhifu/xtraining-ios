import SwiftUI
import UIKit

// iPhone 平时锁竖屏，只有训练日志全屏时转横屏；iPad 随便转
final class AppDelegate: NSObject, UIApplicationDelegate {
    static var lock: UIInterfaceOrientationMask = .portrait
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        UIDevice.current.userInterfaceIdiom == .pad ? .all : AppDelegate.lock
    }
}

enum Orientation {
    static func set(_ mask: UIInterfaceOrientationMask) {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        AppDelegate.lock = mask
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        scene.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
    }
}

@main
struct XTrainingApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = Store()
    @AppStorage("theme") private var theme = "system"
    @AppStorage("skin") private var skin = "ins"

    var body: some Scene {
        WindowGroup {
            SplashHost()
                .environmentObject(store)
                .preferredColorScheme(theme == "light" ? .light : theme == "dark" ? .dark : nil)
                .tint(Brand.pink)
                .fontDesign(.rounded)
                .id(skin)
        }
    }
}
