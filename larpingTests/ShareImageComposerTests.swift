import CoreLocation
import XCTest
@testable import larping

final class ShareImageComposerTests: XCTestCase {
    private let stats = ShareImageComposer.Stats(
        symbolName: "figure.run",
        sportLabel: "Run",
        distance: "5.25 km",
        duration: "0:30:00",
        paceOrSpeed: "5:30",
        date: "Jan 1, 2026"
    )

    func testComposeWithoutPhotoProducesCanvasSizedImage() {
        let image = ShareImageComposer.compose(photo: nil, coordinates: [], stats: stats)
        XCTAssertEqual(image.size, ShareImageComposer.canvasSize)
    }

    func testComposeWithRouteProducesCanvasSizedImage() {
        let coordinates = [
            CLLocationCoordinate2D(latitude: 1, longitude: 1),
            CLLocationCoordinate2D(latitude: 1.001, longitude: 1.001),
        ]
        let image = ShareImageComposer.compose(photo: nil, coordinates: coordinates, stats: stats)
        XCTAssertEqual(image.size, ShareImageComposer.canvasSize)
    }
}
