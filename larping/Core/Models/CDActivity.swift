import Foundation
import SwiftData

@Model
final class CDActivity {
    var id = UUID()
    var sportTypeRaw: String = SportType.run.rawValue
    var startedAt: Date = Date()
    var endedAt: Date?
    var durationSeconds: Int?
    var distanceMeters: Int?
    var elevationGainMeters: Int?
    var averageSpeedMps: Double?
    var maxSpeedMps: Double?
    var source: String = "mobile"
    var eventName: String?
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \CDTrackPoint.activity)
    var trackPoints: [CDTrackPoint] = []

    var sportType: SportType {
        get { SportType(rawValue: sportTypeRaw) ?? .run }
        set { sportTypeRaw = newValue.rawValue }
    }

    @Transient
    var averagePaceSecondsPerKm: Int? {
        guard sportType.usesPaceMetric,
              let averageSpeedMps, averageSpeedMps > 0.1 else { return nil }
        return Int(1000 / averageSpeedMps)
    }

    @Transient
    var calories: Int? {
        guard let distanceMeters, let durationSeconds, durationSeconds > 0 else { return nil }
        let km = Double(distanceMeters) / 1000
        let hours = Double(durationSeconds) / 3600
        return Int(km * hours * 60)
    }

    /// Highest heart rate in any track point (nil when the activity has none —
    /// live iPhone recordings never populate HR; HealthKit-imported ones do).
    @Transient
    var maxHeartRateBpm: Int? {
        trackPoints.compactMap(\.heartRateBpm).max()
    }

    @Transient
    var averageHeartRateBpm: Int? {
        let rates = trackPoints.compactMap(\.heartRateBpm)
        guard !rates.isEmpty else { return nil }
        return rates.reduce(0, +) / rates.count
    }

    init() {}
}