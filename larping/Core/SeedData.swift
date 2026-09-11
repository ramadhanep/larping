import CoreLocation
import Foundation
import SwiftData

/// One-time sample data so a fresh install isn't an empty screen. Seeds a
/// handful of demo activities (all sports, spread across the last week with
/// looped routes so stats/maps/share all work) on the very first launch only.
/// The user can delete them all; they will NOT come back (guarded by a
/// UserDefaults flag, not by the count).
enum SeedData {
    private static let seededFlag = "seedSampleDataV1"

    static func seedIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: seededFlag) else { return }
        defer { UserDefaults.standard.set(true, forKey: seededFlag) }

        let count = (try? context.fetchCount(FetchDescriptor<CDActivity>())) ?? 0
        guard count == 0 else { return }

        for activity in makeActivities() {
            context.insert(activity)
            for point in activity.trackPoints { context.insert(point) }
        }
        try? context.save()
    }

    private static func makeActivities() -> [CDActivity] {
        let jakarta = CLLocationCoordinate2D(latitude: -6.2088, longitude: 106.8456)
        let bogor = CLLocationCoordinate2D(latitude: -6.5971, longitude: 106.8060)
        let bandung = CLLocationCoordinate2D(latitude: -6.9147, longitude: 107.6098)
        let cikarang = CLLocationCoordinate2D(latitude: -6.2833, longitude: 107.1333)

        return [
            activity(sport: .run, daysAgo: 6, startHour: 6, durationSeconds: 3000, distanceMeters: 6000, elevation: 42, center: jakarta, size: 0.010),
            activity(sport: .ride, daysAgo: 5, startHour: 7, durationSeconds: 5400, distanceMeters: 26000, elevation: 180, center: bogor, size: 0.030),
            activity(sport: .walk, daysAgo: 4, startHour: 17, durationSeconds: 2700, distanceMeters: 3200, center: bandung, size: 0.008),
            activity(sport: .hike, daysAgo: 3, startHour: 9, durationSeconds: 6600, distanceMeters: 9500, elevation: 760, center: bandung, size: 0.020),
            activity(sport: .swim, daysAgo: 2, startHour: 12, durationSeconds: 1800, distanceMeters: 1200, center: jakarta, size: 0.003),
            activity(sport: .other, daysAgo: 1, startHour: 19, durationSeconds: 3600, distanceMeters: 8000, center: cikarang, size: 0.015),
            activity(sport: .run, daysAgo: 0, startHour: 5, durationSeconds: 2600, distanceMeters: 5200, elevation: 28, center: jakarta, size: 0.009),
        ]
    }

    private static func activity(
        sport: SportType,
        daysAgo: Int,
        startHour: Int,
        durationSeconds: Int,
        distanceMeters: Int,
        elevation: Int? = nil,
        center: CLLocationCoordinate2D,
        size: Double
    ) -> CDActivity {
        let day = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Calendar.current.startOfDay(for: Date()))!
        let start = day.addingTimeInterval(Double(startHour) * 3600)
        let speed = Double(distanceMeters) / Double(durationSeconds)

        let activity = CDActivity()
        activity.sportType = sport
        activity.startedAt = start
        activity.endedAt = start.addingTimeInterval(Double(durationSeconds))
        activity.durationSeconds = durationSeconds
        activity.distanceMeters = distanceMeters
        activity.elevationGainMeters = elevation
        activity.averageSpeedMps = speed
        activity.maxSpeedMps = speed * 1.25
        activity.source = "sample"

        activity.trackPoints = randomPath(center: center, boxRadius: size, count: 64, speed: speed, start: start)
        return activity
    }

    /// Generates an organic, non-circular loop: a random walk with drifting
    /// heading, steered back toward the center when it strays too far
    /// (approximates city streets without a routing service).
    private static func randomPath(
        center: CLLocationCoordinate2D,
        boxRadius: Double,
        count: Int,
        speed: Double,
        start: Date
    ) -> [CDTrackPoint] {
        var points: [CDTrackPoint] = []
        var lat = center.latitude
        var lng = center.longitude
        var heading = Double.random(in: 0...(2 * .pi))
        let step = boxRadius * 0.18

        for i in 0..<count {
            heading += Double.random(in: -0.45...0.45)

            let toCenter = atan2(center.latitude - lat, center.longitude - lng)
            let distance = sqrt(pow(center.latitude - lat, 2) + pow(center.longitude - lng, 2))
            if distance > boxRadius * 0.85 {
                heading += (toCenter - heading) * 0.4
            }

            lat += sin(heading) * step
            lng += cos(heading) * step

            let point = CDTrackPoint()
            point.timestamp = start.addingTimeInterval(Double(i) * 8)
            point.latitude = lat
            point.longitude = lng
            point.speedMps = speed
            points.append(point)
        }
        return points
    }
}