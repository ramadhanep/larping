import SwiftData
import SwiftUI

@main
struct larpingApp: App {
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .preferredColorScheme(appearanceMode.colorScheme)
        }
        .modelContainer(for: [CDActivity.self, CDTrackPoint.self])
    }
}
