import CoreLocation
import Observation

/// Wraps `CLLocationManager` for a single recording session. A `class`
/// (not a struct/actor) because `CLLocationManagerDelegate` needs identity
/// and callbacks arrive off the main actor.
@MainActor
@Observable
final class LocationTracker: NSObject, CLLocationManagerDelegate {
    enum RecordingState {
        case idle, recording, paused
    }

    private(set) var state: RecordingState = .idle
    private(set) var routeCoordinates: [CLLocationCoordinate2D] = []
    private(set) var distanceMeters: Double = 0
    private(set) var currentSpeedMps: Double = 0
    private(set) var maxSpeedMps: Double = 0
    private(set) var elevationGainMeters: Double = 0
    private(set) var authorizationStatus: CLAuthorizationStatus

    private var trackPoints: [TrackPointPayload] = []
    private let manager = CLLocationManager()
    private var lastLocation: CLLocation?
    private var lastAltitude: Double?
    private var startedAt: Date?

    private static let isoFormatter = ISO8601DateFormatter()

    override init() {
        authorizationStatus = CLLocationManager().authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func start() {
        guard state != .recording else { return }
        if authorizationStatus == .authorizedWhenInUse {
            manager.requestAlwaysAuthorization()
        }
        state = .recording
        startedAt = Date()
        trackPoints = []
        routeCoordinates = []
        distanceMeters = 0
        currentSpeedMps = 0
        maxSpeedMps = 0
        elevationGainMeters = 0
        lastLocation = nil
        lastAltitude = nil
        manager.startUpdatingLocation()
    }

    func pause() {
        guard state == .recording else { return }
        state = .paused
        manager.stopUpdatingLocation()
    }

    func resume() {
        guard state == .paused else { return }
        state = .recording
        manager.startUpdatingLocation()
    }

    struct Recording {
        let startedAt: Date
        let endedAt: Date
        let trackPoints: [TrackPointPayload]
        let distanceMeters: Double
        let elevationGainMeters: Double
        let maxSpeedMps: Double
    }

    func stop() -> Recording {
        manager.stopUpdatingLocation()
        let recording = Recording(
            startedAt: startedAt ?? Date(),
            endedAt: Date(),
            trackPoints: trackPoints,
            distanceMeters: distanceMeters,
            elevationGainMeters: elevationGainMeters,
            maxSpeedMps: maxSpeedMps
        )
        state = .idle
        startedAt = nil
        return recording
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            locations.forEach(self.record)
        }
    }

    private func record(_ location: CLLocation) {
        guard state == .recording else { return }
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy < 50 else { return }

        if let lastLocation {
            distanceMeters += location.distance(from: lastLocation)
        }
        lastLocation = location
        currentSpeedMps = max(location.speed, 0)
        maxSpeedMps = max(maxSpeedMps, currentSpeedMps)

        if location.verticalAccuracy >= 0 {
            if let lastAltitude, location.altitude > lastAltitude {
                elevationGainMeters += location.altitude - lastAltitude
            }
            lastAltitude = location.altitude
        }

        routeCoordinates.append(location.coordinate)
        trackPoints.append(
            TrackPointPayload(
                timestamp: Self.isoFormatter.string(from: location.timestamp),
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                altitudeMeters: location.verticalAccuracy >= 0 ? location.altitude : nil,
                speedMps: location.speed >= 0 ? location.speed : nil,
                heartRateBpm: nil,
                cadenceRpm: nil
            )
        )
    }
}
