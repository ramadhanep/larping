import SwiftData
import SwiftUI

struct ActivitiesListView: View {
    @Query(sort: \CDActivity.startedAt, order: .reverse) private var activities: [CDActivity]
    @State private var showImport = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Activities")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Image("LogoHorizontal")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 20)
                            .foregroundStyle(.primary)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showImport = true
                        } label: {
                            Label("Import GPX", systemImage: "square.and.arrow.down")
                        }
                    }
                }
                .sheet(isPresented: $showImport) {
                    ImportGPXView()
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if activities.isEmpty {
            ContentUnavailableView(
                "No activities yet",
                systemImage: "figure.run",
                description: Text("Record your first run, ride, or hike from the Record tab.")
            )
        } else {
            List(activities) { activity in
                NavigationLink(value: activity.id) {
                    ActivityRow(activity: activity)
                }
            }
            .listStyle(.plain)
            .navigationDestination(for: UUID.self) { id in
                if let activity = activities.first(where: { $0.id == id }) {
                    ActivityDetailView(activity: activity)
                }
            }
        }
    }
}

private struct ActivityRow: View {
    let activity: CDActivity

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: activity.sportType.symbolName)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(activity.sportType.label)
                    .font(.headline)
                Text(Formatters.displayDate(date: activity.startedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(Formatters.distance(meters: activity.distanceMeters.map(Double.init)))
                    .font(.subheadline.monospacedDigit())
                Text("\(Formatters.duration(seconds: activity.durationSeconds)) · \(Formatters.paceOrSpeed(sportType: activity.sportType, averagePaceSecondsPerKm: activity.averagePaceSecondsPerKm, averageSpeedMps: activity.averageSpeedMps))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}