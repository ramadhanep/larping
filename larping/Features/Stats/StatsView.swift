import Charts
import SwiftUI

struct StatsView: View {
    @Environment(ActivitiesStore.self) private var store

    private var lastWeek: [CDActivity] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: Date()))!
        return store.activities.filter { $0.startedAt >= cutoff }
    }

    private var dailyDistance: [DayTotal] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let days = (0..<7).map { calendar.date(byAdding: .day, value: -$0, to: today)! }.reversed()
        return days.map { day in
            let total = lastWeek
                .filter { calendar.isDate($0.startedAt, inSameDayAs: day) }
                .reduce(0.0) { $0 + Double($1.distanceMeters ?? 0) }
            return DayTotal(day: day, distanceMeters: total)
        }
    }

    private var bySport: [SportTotal] {
        Dictionary(grouping: lastWeek, by: \.sportType)
            .map { sport, activities in
                SportTotal(
                    sport: sport,
                    distanceMeters: activities.reduce(0.0) { $0 + Double($1.distanceMeters ?? 0) },
                    durationSeconds: activities.reduce(0) { $0 + ($1.durationSeconds ?? 0) },
                    count: activities.count
                )
            }
            .sorted { $0.distanceMeters > $1.distanceMeters }
    }

    private var totalDistance: Double { lastWeek.reduce(0.0) { $0 + Double($1.distanceMeters ?? 0) } }
    private var totalDuration: Int { lastWeek.reduce(0) { $0 + ($1.durationSeconds ?? 0) } }

    private var allTimeDistance: Double { store.activities.reduce(0.0) { $0 + Double($1.distanceMeters ?? 0) } }
    private var allTimeDuration: Int { store.activities.reduce(0) { $0 + ($1.durationSeconds ?? 0) } }

    private var longestDistanceActivity: CDActivity? {
        store.activities.max { ($0.distanceMeters ?? 0) < ($1.distanceMeters ?? 0) }
    }

    private var longestDurationActivity: CDActivity? {
        store.activities.max { ($0.durationSeconds ?? 0) < ($1.durationSeconds ?? 0) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        StatColumn(title: "Distance", value: Formatters.distance(meters: totalDistance))
                        StatColumn(title: "Time", value: Formatters.duration(seconds: totalDuration))
                        StatColumn(title: "Activities", value: "\(lastWeek.count)")
                    }
                    .listRowBackground(Color.clear)
                }

                Section("Daily distance") {
                    Chart(dailyDistance) { entry in
                        BarMark(
                            x: .value("Day", entry.day, unit: .day),
                            y: .value("Distance", entry.distanceMeters / 1000)
                        )
                        .foregroundStyle(.tint)
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day)) { AxisValueLabel(format: .dateTime.weekday(.narrow)) }
                    }
                    .frame(height: 180)
                    .padding(.vertical, 8)
                }

                if !bySport.isEmpty {
                    Section("By sport this week") {
                        ForEach(bySport) { entry in
                            HStack {
                                Label(entry.sport.label, systemImage: entry.sport.symbolName)
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(Formatters.distance(meters: entry.distanceMeters))
                                        .foregroundStyle(.secondary)
                                    Text("\(Formatters.duration(seconds: entry.durationSeconds)) · \(entry.count) \(entry.count == 1 ? "activity" : "activities")")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if lastWeek.isEmpty {
                    ContentUnavailableView(
                        "No activities this week",
                        systemImage: "chart.bar",
                        description: Text("Record something to see your weekly stats here.")
                    )
                }

                if !store.activities.isEmpty {
                    Section("All time") {
                        HStack {
                            StatColumn(title: "Distance", value: Formatters.distance(meters: allTimeDistance))
                            StatColumn(title: "Time", value: Formatters.duration(seconds: allTimeDuration))
                            StatColumn(title: "Activities", value: "\(store.activities.count)")
                        }
                        .listRowBackground(Color.clear)
                    }

                    Section("Personal bests") {
                        if let longestDistanceActivity, let distance = longestDistanceActivity.distanceMeters {
                            BestRow(
                                title: "Longest distance",
                                sport: longestDistanceActivity.sportType,
                                value: Formatters.distance(meters: Double(distance))
                            )
                        }
                        if let longestDurationActivity, let duration = longestDurationActivity.durationSeconds {
                            BestRow(
                                title: "Longest duration",
                                sport: longestDurationActivity.sportType,
                                value: Formatters.duration(seconds: duration)
                            )
                        }
                    }
                }
            }
            .navigationTitle("Stats")
        }
    }
}

private struct DayTotal: Identifiable {
    let day: Date
    let distanceMeters: Double
    var id: Date { day }
}

private struct SportTotal: Identifiable {
    let sport: SportType
    let distanceMeters: Double
    let durationSeconds: Int
    let count: Int
    var id: SportType { sport }
}

private struct BestRow: View {
    let title: String
    let sport: SportType
    let value: String

    var body: some View {
        HStack {
            Label(title, systemImage: sport.symbolName)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }
}

private struct StatColumn: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.monospacedDigit().bold())
            Text(title.uppercased()).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}