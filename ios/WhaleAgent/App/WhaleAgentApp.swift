import SwiftUI
import UIKit

@main
@MainActor
struct WhaleAgentApp: App {
    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(WhaleTheme.chrome)
        appearance.shadowColor = UIColor(WhaleTheme.glassStroke)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
