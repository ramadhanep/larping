import Foundation
import SwiftData

@Model
final class CDTrackPoint {
    var id = UUID()
    var timestamp: Date = Date()
    var latitude: Double = 0
    var longitude: Double = 0
    var altitudeMeters: Double?
    var speedMps: Double?
    var heartRateBpm: Int?
    var cadenceRpm: Int?

    var activity: CDActivity?

    init() {}
}
