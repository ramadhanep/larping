import SwiftData
import SwiftUI

struct ActivitiesListView: View {
    @Query(sort: \CDActivity.startedAt, order: .reverse) private var activities: [CDActivity]
    @State private var showImport = false

    private var lastWeek: [CDActivity] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: Date()))!
        return activities.filter { $0.startedAt >= cutoff }
    }

    private var monthSections: [(month: String, activities: [CDActivity])] {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        let groups = Dictionary(grouping: activities) { formatter.string(from: $0.startedAt) }
        return groups
            .sorted { ($0.value.first?.startedAt ?? .distantPast) > ($1.value.first?.startedAt ?? .distantPast) }
            .map { (month: $0.key, activities: $0.value) }
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Image("LogoHorizontal")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 22)
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
            List {
                Section {
                    HStack {
                        WeekStatColumn(title: "Distance", value: Formatters.distance(meters: lastWeek.reduce(0.0) { $0 + Double($1.distanceMeters ?? 0) }))
                        WeekStatColumn(title: "Time", value: Formatters.duration(seconds: lastWeek.reduce(0) { $0 + ($1.durationSeconds ?? 0) }))
                        WeekStatColumn(title: "Activities", value: "\(lastWeek.count)")
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("This week")
                }

                ForEach(monthSections, id: \.month) { section in
                    Section(section.month) {
                        ForEach(section.activities) { activity in
                            NavigationLink(value: activity.id) {
                                ActivityRow(activity: activity)
                            }
                        }
                    }
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

private struct WeekStatColumn: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.subheadline.monospacedDigit().bold())
            Text(title.uppercased()).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ActivityRow: View {
    let activity: CDActivity

    private var title: String {
        let trimmed = activity.eventName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? activity.sportType.label : trimmed
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: activity.sportType.symbolName)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
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