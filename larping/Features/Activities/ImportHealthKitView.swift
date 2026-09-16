import CoreLocation
import HealthKit
import SwiftUI

/// Imports a workout recorded on Apple Watch / iPhone into Larping's local
/// store (route + heart rate where available). SwiftData stays authoritative;
/// Health is only a source here. Mirrors `ImportGPXView`'s shape —
/// independent picker with a summary and a single Import action.
struct ImportHealthKitView: View {
    @Environment(ActivitiesStore.self) private var activitiesStore
    @Environment(\.dismiss) private var dismiss

    @State private var workouts: [HKWorkout] = []
    @State private var selected: HKWorkout?
    @State private var sportType: SportType = .run
    @State private var isLoading = false
    @State private var isImporting = false
    @State private var errorMessage: String?
    @State private var status: HKAuthorizationStatus = .notDetermined

    private var isAuthorized: Bool { status == .sharingAuthorized }

    var body: some View {
        NavigationStack {
            Group {
                if !HealthKitService.isAvailable {
                    ContentUnavailableView(
                        "HealthKit unavailable",
                        systemImage: "heart.slash",
                        description: Text("This device doesn't support HealthKit.")
                    )
                } else if !isAuthorized {
                    authPrompt
                } else if workouts.isEmpty && !isLoading {
                    ContentUnavailableView(
                        "No Health workouts found",
                        systemImage: "figure.run",
                        description: Text("Workouts you record on Apple Watch or iPhone with the Workout app will appear here.")
                    )
                } else {
                    List {
                        Section("Recent Health workouts") {
                            if isLoading {
                                HStack { Spacer(); ProgressView(); Spacer() }
                            }
                            ForEach(workouts, id: \.uuid) { workout in
                                row(workout)
                            }
                        }

                        if let selected {
                            Section("Import as") {
                                Picker("Sport", selection: $sportType) {
                                    ForEach(SportType.allCases) { sport in
                                        Label(sport.label, systemImage: sport.symbolName).tag(sport)
                                    }
                                }
                            }
                            Section("Summary") {
                                LabeledContent("Date", value: Formatters.displayDate(date: selected.startDate))
                                LabeledContent("Duration", value: Formatters.duration(seconds: Int(selected.duration)))
                                LabeledContent(
                                    "Distance",
                                    value: Formatters.distance(meters: selected.totalDistance?.doubleValue(for: .meter()))
                                )
                            }
                        }

                        if let errorMessage {
                            Section { Text(errorMessage).foregroundStyle(.red) }
                        }
                    }
                }
            }
            .navigationTitle("Import from Health")
            .toolbar {
                if isAuthorized {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            Task { await importWorkout() }
                        } label: {
                            if isImporting { ProgressView() } else { Text("Import") }
                        }
                        .disabled(selected == nil || isImporting)
                    }
                }
            }
            .onAppear { refresh() }
        }
    }

    private var authPrompt: some View {
        VStack(spacing: 14) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(status == .sharingDenied
                 ? "Health access is off"
                 : "Import workouts from Health")
                .font(.headline)
            Text(status == .sharingDenied
                 ? "Enable it in Settings → Health → Data Access & Devices, then come back."
                 : "Larping reads your Health workouts, routes, and heart rate so you can import them here. You stay in control — nothing is uploaded anywhere.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                if status == .sharingDenied {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } else {
                    Task {
                        isLoading = true
                        await HealthKitService.requestAuthorization()
                        refresh()
                    }
                }
            } label: {
                if isLoading { ProgressView() } else {
                    Text(status == .sharingDenied ? "Open Settings" : "Allow HealthKit access")
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(28)
    }

    private func row(_ workout: HKWorkout) -> some View {
        Button {
            selected = workout
            sportType = SportType(workoutActivityType: workout.workoutActivityType)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: SportType(workoutActivityType: workout.workoutActivityType).symbolName)
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(SportType(workoutActivityType: workout.workoutActivityType).label)
                        .font(.headline)
                    Text(Formatters.displayDate(date: workout.startDate))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Formatters.duration(seconds: Int(workout.duration)))
                        .font(.subheadline.monospacedDigit())
                    Text(Formatters.distance(meters: workout.totalDistance?.doubleValue(for: .meter())))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if selected?.uuid == workout.uuid {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                }
            }
        }
    }

    private func refresh() {
        guard HealthKitService.isAvailable else { return }
        isLoading = true
        errorMessage = nil
        status = HealthKitService.shareStatus ?? .notDetermined
        guard status == .sharingAuthorized else {
            isLoading = false
            return
        }
        Task {
            defer { isLoading = false }
            do {
                workouts = try await HealthKitService.fetchRecentWorkouts()
                if workouts.isEmpty {
                    selected = nil
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func importWorkout() async {
        guard let selected else { return }
        isImporting = true
        errorMessage = nil
        defer { isImporting = false }

        let duration = selected.duration > 0 ? Int(selected.duration) : Int(selected.endDate.timeIntervalSince(selected.startDate))
        let route = await HealthKitService.fetchRoute(for: selected)
        let heartRate = await HealthKitService.heartRateSamples(for: selected)

        let distance: Double
        if let total = selected.totalDistance?.doubleValue(for: .meter()), total > 0 {
            distance = total
        } else {
            distance = routeDistance(route)
        }

        let points = trackPoints(route: route, heartRate: heartRate)

        do {
            try activitiesStore.create(
                sportType: sportType,
                startedAt: selected.startDate,
                endedAt: selected.endDate,
                durationSeconds: duration > 0 ? duration : nil,
                distanceMeters: distance > 0 ? Int(distance) : nil,
                elevationGainMeters: elevationGain(route) > 0 ? Int(elevationGain(route)) : nil,
                averageSpeedMps: duration > 0 && distance > 0 ? distance / Double(duration) : nil,
                maxSpeedMps: maxSpeed(route),
                source: "healthkit_import",
                trackPointsPayloads: points
            )
            dismiss()
        } catch {
            errorMessage = "Couldn't save: \(error.localizedDescription)"
        }
    }

    private func routeDistance(_ route: [CLLocation]) -> Double {
        let sortedRoute = route.sorted { $0.timestamp < $1.timestamp }
        return zip(sortedRoute, sortedRoute.dropFirst()).reduce(0) { $0 + $1.1.distance(from: $1.0) }
    }

    private func elevationGain(_ route: [CLLocation]) -> Double {
        var gain: Double = 0
        var last: Double?
        for location in route.sorted(by: { $0.timestamp < $1.timestamp }) where location.verticalAccuracy >= 0 {
            if let last, location.altitude > last {
                gain += location.altitude - last
            }
            last = location.altitude
        }
        return gain
    }

    private func maxSpeed(_ route: [CLLocation]) -> Double? {
        let speeds = route.map(\.speed).filter { $0 >= 0 }
        return speeds.max()
    }

    private func trackPoints(route: [CLLocation], heartRate: [HKQuantitySample]) -> [TrackPointPayload] {
        let hr = heartRate.compactMap { sample -> (Date, Int)? in
            let bpm = Int(sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())))
            return bpm > 0 ? (sample.startDate, bpm) : nil
        }
        .sorted { $0.0 < $1.0 }
        let formatter = ISO8601DateFormatter()
        return route.map { location in
            let bpm = hr.last(where: { $0.0 <= location.timestamp })?.1
            return TrackPointPayload(
                timestamp: formatter.string(from: location.timestamp),
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                altitudeMeters: location.verticalAccuracy >= 0 ? location.altitude : nil,
                speedMps: location.speed >= 0 ? location.speed : nil,
                heartRateBpm: bpm,
                cadenceRpm: nil
            )
        }
    }
}