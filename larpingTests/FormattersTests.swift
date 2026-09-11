import XCTest
@testable import larping

final class FormattersTests: XCTestCase {
    func testDistance() {
        XCTAssertEqual(Formatters.distance(meters: 5250), "5.25 km")
        XCTAssertEqual(Formatters.distance(meters: nil), "–")
    }

    func testDuration() {
        XCTAssertEqual(Formatters.duration(seconds: 65), "1:05")
        XCTAssertEqual(Formatters.duration(seconds: 3725), "1:02:05")
        XCTAssertEqual(Formatters.duration(seconds: nil), "–")
    }

    func testPace() {
        XCTAssertEqual(Formatters.pace(secondsPerKm: 330), "5:30 /km")
        XCTAssertEqual(Formatters.pace(secondsPerKm: 0), "–")
        XCTAssertEqual(Formatters.pace(secondsPerKm: nil), "–")
    }

    func testSpeed() {
        XCTAssertEqual(Formatters.speed(metersPerSecond: 10), "36.0 km/h")
        XCTAssertEqual(Formatters.speed(metersPerSecond: 0.05), "–")
    }

    func testPaceOrSpeedRoutesBySport() {
        XCTAssertEqual(
            Formatters.paceOrSpeed(sportType: .run, averagePaceSecondsPerKm: 300, averageSpeedMps: nil),
            "5:00 /km"
        )
        XCTAssertEqual(
            Formatters.paceOrSpeed(sportType: .ride, averagePaceSecondsPerKm: nil, averageSpeedMps: 10),
            "36.0 km/h"
        )
    }

    func testISO8601RoundTripBothFormats() {
        XCTAssertNotNil(ISO8601DateFormatter.parse("2026-01-01T10:00:00Z"))
        XCTAssertNotNil(ISO8601DateFormatter.parse("2026-01-01T10:00:00.123Z"))
        XCTAssertNil(ISO8601DateFormatter.parse("not-a-date"))
    }
}
