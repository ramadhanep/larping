import MapKit
import SwiftUI

struct ActivityDetailView: View {
    let activity: CDActivity

    @Environment(ActivitiesStore.self) private var store
    @State private var showDeleteConfirmation = false
    @State private var showShareSheet = false
    @State private var showRename = false
    @State private var renameText = ""
    @Environment(\.dismiss) private var dismiss

    private var title: String {
        let trimmed = activity.eventName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? activity.sportType.label : trimmed
    }

    private var coordinates: [CLLocationCoordinate2D] {
        store.coordinates(for: activity)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if coordinates.count > 1 {
                    ZStack(alignment: .bottomLeading) {
                        RouteMap(coordinates: coordinates, sportType: activity.sportType)
                            .frame(height: 380)

                        LinearGradient(
                            colors: [.clear, .black.opacity(0.65)],
                            startPoint: .top,
                            endPoint: .bottom
                        )

                        HStack(alignment: .bottom) {
                            Image(systemName: activity.sportType.symbolName)
                                .font(.title2.bold())
                                .foregroundStyle(.white)
                                .padding(10)
                                .background(.black.opacity(0.35), in: Circle())

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                Text(title)
                                    .font(.title3.bold())
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.trailing)
                                Text(Formatters.displayDate(date: activity.startedAt))
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                        }
                        .padding(16)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                }

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
            }
            .padding()
        }
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if coordinates.count > 1 {
                        Button {
                            showShareSheet = true
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                    Button {
                        renameText = title
                        showRename = true
                    } label: {
                        Label("Rename event", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete activity", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareActivityView(activity: activity, coordinates: coordinates)
        }
        .alert("Rename event", isPresented: $showRename) {
            TextField("Event name", text: $renameText)
            Button("Save") { store.rename(activity, to: renameText) }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete \"\(title)\"?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { store.delete(activity); dismiss() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
    }
}

private struct RouteMap: View {
    let coordinates: [CLLocationCoordinate2D]
    let sportType: SportType

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
        // MapPolyline overlay reconciliation is too slow to keep up with a 60fps
        // TimelineView tick, so the line stayed visually static and only caught up
        // in one jump once ticking stopped. Throttling to ~12fps gives MapKit time
        // to actually apply each polyline update, keeping the line in step with
        // the marker instead of popping in at the end.
        TimelineView(.animation(minimumInterval: 1.0 / 12.0, paused: isDrawComplete)) { timeline in
            let progress = min(timeline.date.timeIntervalSince(startDate) / Self.drawDuration, 1)
            let revealedCount = max(2, Int(Double(coordinates.count) * progress))

            Map(initialPosition: .region(region)) {
                MapPolyline(coordinates: Array(coordinates.prefix(revealedCount)))
                    .stroke(.accent, lineWidth: 4)

                // The "person" marker: a sport-specific icon riding the tip of
                // the route while it draws, bouncing gently — it comes to rest
                // at the finish when the draw completes.
                Annotation("", coordinate: coordinates[revealedCount - 1]) {
                    Image(systemName: sportType.symbolName)
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .padding(7)
                        .background(.black.opacity(0.6), in: Circle())
                        .symbolEffect(.bounce, options: .repeating, isActive: !isDrawComplete)
                }
            }
            .mapStyle(.standard)
            .allowsHitTesting(false)
            .animation(nil, value: revealedCount)
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