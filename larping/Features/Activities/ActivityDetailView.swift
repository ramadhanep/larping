import MapKit
import SwiftUI

struct ActivityDetailView: View {
    let activity: CDActivity

    @Environment(ActivitiesStore.self) private var store
    @State private var showDeleteConfirmation = false
    @State private var showShareSheet = false
    @Environment(\.dismiss) private var dismiss

    private var coordinates: [CLLocationCoordinate2D] {
        store.coordinates(for: activity)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if coordinates.count > 1 {
                    RouteMap(coordinates: coordinates)
                        .frame(height: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                HStack {
                    Label(activity.sportType.label, systemImage: activity.sportType.symbolName)
                        .font(.title2.bold())
                    Spacer()
                }

                Text(Formatters.displayDate(date: activity.startedAt))
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    StatTile(title: "Distance", value: Formatters.distance(meters: activity.distanceMeters.map(Double.init)))
                    StatTile(title: "Duration", value: Formatters.duration(seconds: activity.durationSeconds))
                    StatTile(
                        title: activity.sportType.usesPaceMetric ? "Avg. pace" : "Avg. speed",
                        value: Formatters.paceOrSpeed(
                            sportType: activity.sportType,
                            averagePaceSecondsPerKm: activity.averagePaceSecondsPerKm,
                            averageSpeedMps: activity.averageSpeedMps
                        )
                    )
                    if let maxSpeed = activity.maxSpeedMps {
                        StatTile(
                            title: activity.sportType.usesPaceMetric ? "Best pace" : "Top speed",
                            value: activity.sportType.usesPaceMetric
                                ? Formatters.paceFromSpeed(metersPerSecond: maxSpeed)
                                : Formatters.speed(metersPerSecond: maxSpeed)
                        )
                    }
                    if let gain = activity.elevationGainMeters, gain > 0 {
                        StatTile(title: "Elevation gain", value: Formatters.elevation(meters: Double(gain)))
                    }
                    if let calories = activity.calories {
                        StatTile(title: "Calories", value: "\(calories) kcal")
                    }
                }

                HStack {
                    Spacer()
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete activity", systemImage: "trash")
                            .font(.subheadline)
                    }
                    .padding(.top, 16)
                }
            }
            .padding()
        }
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if coordinates.count > 1 {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showShareSheet = true
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareActivityView(activity: activity, coordinates: coordinates)
        }
        .confirmationDialog("Delete this activity?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { store.delete(activity); dismiss() }
            Button("Cancel", role: .cancel) {}
        }
    }
}

private struct RouteMap: View {
    let coordinates: [CLLocationCoordinate2D]

    private static let drawDuration: TimeInterval = 5.5

    @State private var startDate = Date()
    @State private var isDrawComplete = false

    private var region: MKCoordinateRegion {
        let lats = coordinates.map(\.latitude)
        let lngs = coordinates.map(\.longitude)
        let minLat = lats.min() ?? 0, maxLat = lats.max() ?? 0
        let minLng = lngs.min() ?? 0, maxLng = lngs.max() ?? 0
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.4, 0.005),
            longitudeDelta: max((maxLng - minLng) * 1.4, 0.005)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    var body: some View {
        TimelineView(.animation(paused: isDrawComplete)) { timeline in
            let progress = min(timeline.date.timeIntervalSince(startDate) / Self.drawDuration, 1)
            let revealedCount = max(2, Int(Double(coordinates.count) * progress))

            Map(initialPosition: .region(region)) {
                MapPolyline(coordinates: Array(coordinates.prefix(revealedCount)))
                    .stroke(.accent, lineWidth: 4)

                // Leading marker at the animation's current tip — stands in for
                // "the person"; could become a sport-specific icon later.
                Annotation("", coordinate: coordinates[revealedCount - 1]) {
                    Circle()
                        .fill(.accent)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                }
            }
            .mapStyle(.standard)
            .allowsHitTesting(false)
        }
        .task {
            startDate = Date()
            isDrawComplete = false
            try? await Task.sleep(for: .seconds(Self.drawDuration))
            isDrawComplete = true
        }
    }
}

private struct StatTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.monospacedDigit().bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
    }
}