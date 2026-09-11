import Foundation

enum Formatters {
    static func distance(meters: Double?) -> String {
        guard let meters else { return "–" }
        return String(format: "%.2f km", meters / 1000)
    }

    static func duration(seconds: Int?) -> String {
        guard let seconds else { return "–" }
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    static func pace(secondsPerKm: Int?) -> String {
        guard let secondsPerKm, secondsPerKm > 0 else { return "–" }
        return String(format: "%d:%02d /km", secondsPerKm / 60, secondsPerKm % 60)
    }

    static func paceFromSpeed(metersPerSecond: Double) -> String {
        guard metersPerSecond > 0.1 else { return "–" }
        let secondsPerKm = Int(1000 / metersPerSecond)
        return pace(secondsPerKm: secondsPerKm)
    }

    static func speed(metersPerSecond: Double?) -> String {
        guard let metersPerSecond, metersPerSecond > 0.1 else { return "–" }
        return String(format: "%.1f km/h", metersPerSecond * 3.6)
    }

    static func elevation(meters: Double?) -> String {
        guard let meters else { return "–" }
        return String(format: "%.0f m", meters)
    }

    static func paceOrSpeed(sportType: SportType, averagePaceSecondsPerKm: Int?, averageSpeedMps: Double?) -> String {
        if sportType.usesPaceMetric {
            if let averagePaceSecondsPerKm { return pace(secondsPerKm: averagePaceSecondsPerKm) }
            if let averageSpeedMps { return paceFromSpeed(metersPerSecond: averageSpeedMps) }
            return "–"
        }
        return speed(metersPerSecond: averageSpeedMps)
    }

    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static func displayDate(iso: String) -> String {
        guard let date = ISO8601DateFormatter.flexible.date(from: iso) else { return iso }
        return displayDateFormatter.string(from: date)
    }

    static func displayDate(date: Date) -> String {
        displayDateFormatter.string(from: date)
    }
}

extension ISO8601DateFormatter {
    /// Parses both fractional-seconds (`2026-01-01T10:00:00.123Z`) and plain
    /// (`2026-01-01T10:00:00Z`) ISO-8601 strings, since the recorder emits one
    /// variant and imports/API responses may carry the other.
    static func parse(_ string: String) -> Date? {
        if let date = flexible.date(from: string) { return date }
        return plain.date(from: string)
    }

    static let flexible: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
