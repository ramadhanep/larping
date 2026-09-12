import XCTest
@testable import larping

final class GPXParserTests: XCTestCase {
    private let sampleGPX = """
    <?xml version="1.0"?>
    <gpx><trk><trkseg>
      <trkpt lat="1.0" lon="1.0"><ele>10</ele><time>2026-01-01T10:00:00Z</time></trkpt>
      <trkpt lat="1.001" lon="1.0"><ele>15</ele><time>2026-01-01T10:00:10Z</time></trkpt>
      <trkpt lat="1.002" lon="1.0"><ele>12</ele><time>2026-01-01T10:00:20Z</time></trkpt>
    </trkseg></trk></gpx>
    """

    func testParsesPointsDistanceAndElevationGain() throws {
        let result = try GPXParser.parse(data: sampleGPX.data(using: .utf8)!)

        XCTAssertEqual(result.trackPoints.count, 3)
        XCTAssertGreaterThan(result.distanceMeters, 0)
        // Elevation only accumulates on increases: 10->15 (+5), 15->12 (ignored).
        XCTAssertEqual(result.elevationGainMeters, 5, accuracy: 0.001)
        XCTAssertNotNil(result.startedAt)
        XCTAssertNotNil(result.endedAt)
    }

    func testThrowsOnEmptyFile() {
        let empty = "<?xml version=\"1.0\"?><gpx></gpx>".data(using: .utf8)!
        XCTAssertThrowsError(try GPXParser.parse(data: empty)) { error in
            guard case .some(.noTrackPoints) = error as? GPXParser.ParseError else {
                return XCTFail("expected .noTrackPoints, got \(error)")
            }
        }
    }

    func testDetectsSportFromType() throws {
        let cycling = """
        <?xml version="1.0"?><gpx><trk><type>Cycling_Sport</type><trkseg>
          <trkpt lat="1.0" lon="1.0"></trkpt>
          <trkpt lat="1.001" lon="1.0"></trkpt>
        </trkseg></trk></gpx>
        """
        let cycled = try GPXParser.parse(data: cycling.data(using: .utf8)!)
        XCTAssertEqual(cycled.sportType, .ride)

        let hiking = """
        <?xml version="1.0"?><gpx><trk><type>hiking</type><trkseg>
          <trkpt lat="1.0" lon="1.0"></trkpt>
          <trkpt lat="1.001" lon="1.0"></trkpt>
        </trkseg></trk></gpx>
        """
        XCTAssertEqual(try GPXParser.parse(data: hiking.data(using: .utf8)!).sportType, .hike)
    }

    func testUnknownTypeFallsBackToNil() throws {
        let mystery = """
        <?xml version="1.0"?><gpx><trk><type>knitting</type><trkseg>
          <trkpt lat="1.0" lon="1.0"></trkpt>
          <trkpt lat="1.001" lon="1.0"></trkpt>
        </trkseg></trk></gpx>
        """
        XCTAssertNil(try GPXParser.parse(data: mystery.data(using: .utf8)!).sportType)
    }
}
