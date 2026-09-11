import CoreLocation
import Foundation

/// Parses GPX 1.1 `<trkpt>` points into the same shape the live recorder
/// produces, so an imported file goes through the identical save path.
enum GPXParser {
    struct Result {
        let trackPoints: [TrackPointPayload]
        let distanceMeters: Double
        let elevationGainMeters: Double
        let startedAt: Date?
        let endedAt: Date?
    }

    enum ParseError: LocalizedError {
        case noTrackPoints
        var errorDescription: String? { "No track points found in this GPX file." }
    }

    static func parse(data: Data) throws -> Result {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()

        guard !delegate.points.isEmpty else { throw ParseError.noTrackPoints }

        var trackPoints: [TrackPointPayload] = []
        var distanceMeters = 0.0
        var elevationGainMeters = 0.0
        var lastLocation: CLLocation?
        var lastAltitude: Double?

        for point in delegate.points {
            let location = CLLocation(latitude: point.latitude, longitude: point.longitude)
            if let lastLocation {
                distanceMeters += location.distance(from: lastLocation)
            }
            lastLocation = location
            if let altitude = point.elevation {
                if let lastAltitude, altitude > lastAltitude {
                    elevationGainMeters += altitude - lastAltitude
                }
                lastAltitude = altitude
            }
            trackPoints.append(
                TrackPointPayload(
                    timestamp: point.time.map { ISO8601DateFormatter.flexible.string(from: $0) }
                        ?? ISO8601DateFormatter.flexible.string(from: Date()),
                    latitude: point.latitude,
                    longitude: point.longitude,
                    altitudeMeters: point.elevation,
                    speedMps: nil,
                    heartRateBpm: nil,
                    cadenceRpm: nil
                )
            )
        }

        return Result(
            trackPoints: trackPoints,
            distanceMeters: distanceMeters,
            elevationGainMeters: elevationGainMeters,
            startedAt: delegate.points.first?.time,
            endedAt: delegate.points.last?.time
        )
    }

    private struct Point {
        let latitude: Double
        let longitude: Double
        var elevation: Double?
        var time: Date?
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var points: [Point] = []
        private var currentText = ""
        private var current: Point?

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            currentText = ""
            if elementName == "trkpt", let latString = attributeDict["lat"], let lat = Double(latString),
               let lonString = attributeDict["lon"], let lon = Double(lonString) {
                current = Point(latitude: lat, longitude: lon)
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            currentText += string
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            switch elementName {
            case "ele":
                current?.elevation = Double(currentText.trimmingCharacters(in: .whitespacesAndNewlines))
            case "time":
                current?.time = ISO8601DateFormatter.parse(currentText.trimmingCharacters(in: .whitespacesAndNewlines))
            case "trkpt":
                if let current { points.append(current) }
                current = nil
            default:
                break
            }
        }
    }
}
