import SwiftData
import SwiftUI

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var activitiesStore: ActivitiesStore?

    var body: some View {
        Group {
            if let activitiesStore {
                TabView {
                    Tab("Activities", systemImage: "list.bullet") {
                        ActivitiesListView()
                    }
                    Tab("Record", systemImage: "record.circle") {
                        RecordView()
                    }
                    Tab("Stats", systemImage: "chart.bar.fill") {
                        StatsView()
                    }
                    Tab("Profile", systemImage: "person.crop.circle") {
                        ProfileView()
                    }
                }
                .environment(activitiesStore)
            } else {
                ProgressView()
            }
        }
        .task {
            if activitiesStore == nil {
                SeedData.seedIfNeeded(context: modelContext)
                let store = ActivitiesStore(modelContext: modelContext)
                activitiesStore = store
                store.refresh()
            }
        }
    }
}