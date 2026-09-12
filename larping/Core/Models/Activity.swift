import Foundation

nonisolated enum SportType: String, Codable, CaseIterable, Identifiable {
    case run, ride, walk, hike, swim, other
    var id: String { rawValue }

    var label: String {
        switch self {
        case .run: return "Run"
        case .ride: return "Ride"
        case .walk: return "Walk"
        case .hike: return "Hike"
        case .swim: return "Swim"
        case .other: return "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .run: return "figure.run"
        case .ride: return "figure.outdoor.cycle"
        case .walk: return "figure.walk"
        case .hike: return "figure.hiking"
        case .swim: return "figure.pool.swim"
        case .other: return "figure.mixed.cardio"
        }
    }

    /// Running/walking/hiking/swimming read naturally as pace (min/km);
    /// cycling and everything else read naturally as speed (km/h).
    var usesPaceMetric: Bool {
        switch self {
        case .run, .walk, .hike, .swim: return true
        case .ride, .other: return false
        }
    }
}

/// Builds the default event title for an activity: "Larping Run", bumped to
/// "Larping Run 1" / "Larping Run 2" / … as soon as a name already exists, so
/// recording the same sport repeatedly never produces duplicates.
nonisolated enum EventNamer {
    static func nextName(base: String, existing: [String]) -> String {
        var maxSuffix = -1
        if existing.contains(base) { maxSuffix = 0 }
        let prefix = base + " "
        for name in existing where name.hasPrefix(prefix) {
            if let n = Int(name.dropFirst(prefix.count)) {
                maxSuffix = max(maxSuffix, n)
            }
        }
        return maxSuffix < 0 ? base : "\(base) \(maxSuffix + 1)"
    }
}

/// In-memory transfer shape produced by the live recorder and GPX import and
/// consumed by `ActivitiesStore` when materializing SwiftData track points.
nonisolated struct TrackPointPayload: Codable {
    let timestamp: String
    let latitude: Double
    let longitude: Double
    let altitudeMeters: Double?
    let speedMps: Double?
    let heartRateBpm: Int?
    let cadenceRpm: Int?
}