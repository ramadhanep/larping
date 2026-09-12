import CoreLocation
import Foundation
import HealthKit

/// Optional HealthKit interoperability layer — writes finished activities as
/// `HKWorkout`s (with their route polyline) into the Health app. Everything
/// here is best-effort: Larping's SwiftData store is the source of truth and
/// recording never depends on HealthKit authorization.
///
/// Read side (importing Watch workouts back into Larping) is deliberately not
/// here yet — see `Core/GPXParser.swift` for the comparable import shape.
enum HealthKitService {
    static var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    /// `.sharingAuthorized` means we may write workouts to the user's Health
    /// store (object-per-type; `requestAuthorization` scopes it to workout +
    /// route write access).
    static var shareStatus: HKAuthorizationStatus? {
        guard isAvailable else { return nil }
        return HKHealthStore().authorizationStatus(for: .workoutType())
    }

    static var isAuthorized: Bool {
        shareStatus == .sharingAuthorized
    }

    /// Requests write access for workouts + workout routes and read access for
    /// workouts, routes, and heart rate. No-op when unavailable ("user sees no
    /// prompt" is the graceful-degradation path).
    static func requestAuthorization() async {
        guard isAvailable else { return }
        let store = HKHealthStore()
        let share: Set<HKSampleType> = [.workoutType(), HKSeriesType.workoutRoute()]
        var read: Set<HKObjectType> = [.workoutType(), HKSeriesType.workoutRoute()]
        if let heartRateType { read.insert(heartRateType) }
        _ = try? await store.requestAuthorization(toShare: share, read: read)
    }

    private static var heartRateType: HKQuantityType? {
        HKQuantityType.quantityType(forIdentifier: .heartRate)
    }

    /// Writes a completed activity to Health. Called only after the activity
    /// has already been persisted locally; any failure here is swallowed.
    static func saveWorkout(from activity: CDActivity) async {
        guard isAvailable, isAuthorized else { return }
        let store = HKHealthStore()

        let start = activity.startedAt
        let end = activity.endedAt ?? start
        let duration = activity.durationSeconds.map(Double.init) ?? end.timeIntervalSince(start)
        guard duration > 0 else { return }

        let workout = HKWorkout(
            activityType: HKWorkoutActivityType(sport: activity.sportType),
            start: start,
            end: end,
            duration: duration,
            totalEnergyBurned: nil,
            totalDistance: activity.distanceMeters.map { HKQuantity(unit: .meter(), doubleValue: Double($0)) },
            metadata: ["larping.activityID": activity.id.uuidString]
        )

        do {
            try await store.save(workout)
            if let samples = locationSamples(for: activity), samples.count > 1 {
                let builder = HKWorkoutRouteBuilder(healthStore: store, device: nil)
                try await builder.insertRouteData(samples)
                try await builder.finishRoute(with: workout, metadata: nil)
            }
        } catch {
            // Best-effort only — the local save already succeeded.
        }
    }

    /// Rebuilds `CLLocation` samples from the stored track points. Accuracy is
    /// reported at the recorder's accepted ceiling (<50m filter, see
    /// `LocationTracker`) — honest, never overstated; altitude unknown where
    /// the recording didn't capture it.
    private static func locationSamples(for activity: CDActivity) -> [CLLocation]? {
        let points = activity.trackPoints.sorted { $0.timestamp < $1.timestamp }
        guard !points.isEmpty else { return nil }
        return points.map { point in
            CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude),
                altitude: point.altitudeMeters ?? -1,
                horizontalAccuracy: 50,
                verticalAccuracy: point.altitudeMeters != nil ? 10 : -1,
                timestamp: point.timestamp
            )
        }
    }
}

extension HKWorkoutActivityType {
    init(sport: SportType) {
        switch sport {
        case .run: self = .running
        case .ride: self = .cycling
        case .walk: self = .walking
        case .hike: self = .hiking
        case .swim: self = .swimming
        case .other: self = .other
        }
    }
}

extension SportType {
    init(workoutActivityType: HKWorkoutActivityType) {
        switch workoutActivityType {
        case .running: self = .run
        case .cycling: self = .ride
        case .walking: self = .walk
        case .hiking: self = .hike
        case .swimming: self = .swim
        default: self = .other
        }
    }
}

// MARK: - Read / import (HealthKit → Larping)

extension HealthKitService {
    /// Most recent workouts, newest first — the import picker's source list.
    static func fetchRecentWorkouts(limit: Int = 20) async throws -> [HKWorkout] {
        guard isAvailable else { return [] }
        let store = HKHealthStore()
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: nil,
                limit: limit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
                }
            }
            store.execute(query)
        }
    }

    /// Route polyline for a workout (may be empty when the workout was
    /// recorded without GPS — imports then proceed without a route).
    static func fetchRoute(for workout: HKWorkout) async -> [CLLocation] {
        guard isAvailable else { return [] }
        let store = HKHealthStore()
        do {
            let routes: [HKWorkoutRoute] = try await withCheckedThrowingContinuation { continuation in
                let query = HKSampleQuery(
                    sampleType: HKSeriesType.workoutRoute(),
                    predicate: HKQuery.predicateForObjects(from: workout),
                    limit: HKObjectQueryNoLimit,
                    sortDescriptors: nil
                ) { _, samples, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: (samples as? [HKWorkoutRoute]) ?? [])
                    }
                }
                store.execute(query)
            }
            guard let route = routes.first else { return [] }
            return try await withCheckedThrowingContinuation { continuation in
                var all: [CLLocation] = []
                let query = HKWorkoutRouteQuery(route: route) { _, locations, done, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if done {
                        continuation.resume(returning: all)
                    } else if let locations {
                        all.append(contentsOf: locations)
                    }
                }
                store.execute(query)
            }
        } catch {
            return []
        }
    }

    /// Heart-rate samples inside a workout's time window, oldest first.
    /// Empty when unavailable or read access is denied.
    static func heartRateSamples(for workout: HKWorkout) async -> [HKQuantitySample] {
        guard isAvailable, let heartRateType,
              HKHealthStore().authorizationStatus(for: heartRateType) == .sharingAuthorized else { return [] }
        let predicate = HKQuery.predicateForSamples(
            withStart: workout.startDate,
            end: workout.endDate,
            options: [.strictStartDate, .strictEndDate]
        )
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: heartRateType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            HKHealthStore().execute(query)
        }
    }
}