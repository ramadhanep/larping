import SwiftData
import SwiftUI

@main
struct larpingApp: App {
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootTabView()
                    .preferredColorScheme(appearanceMode.colorScheme)
                if showSplash {
                    SplashView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .task {
                try? await Task.sleep(for: .seconds(1.4))
                withAnimation(.easeOut(duration: 0.4)) { showSplash = false }
            }
        }
        .modelContainer(for: [CDActivity.self, CDTrackPoint.self])
    }
}
