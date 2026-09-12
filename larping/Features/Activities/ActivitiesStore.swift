import CoreLocation
import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class ActivitiesStore {
    private(set) var activities: [CDActivity] = []
    private(set) var isLoading = false
    var errorMessage: String?

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func refresh() {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            var descriptor = FetchDescriptor<CDActivity>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
            descriptor.fetchLimit = 500
            activities = try modelContext.fetch(descriptor)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func create(
        sportType: SportType,
        startedAt: Date,
        endedAt: Date?,
        durationSeconds: Int?,
        distanceMeters: Int?,
        elevationGainMeters: Int?,
        averageSpeedMps: Double?,
        maxSpeedMps: Double?,
        source: String?,
        eventName: String? = nil,
        trackPointsPayloads: [TrackPointPayload]
    ) -> CDActivity {
        let activity = CDActivity()
        activity.sportType = sportType
        activity.startedAt = startedAt
        activity.endedAt = endedAt
        activity.durationSeconds = durationSeconds
        activity.distanceMeters = distanceMeters
        activity.elevationGainMeters = elevationGainMeters
        activity.averageSpeedMps = averageSpeedMps
        activity.maxSpeedMps = maxSpeedMps
        activity.source = source ?? "mobile"
        activity.eventName = eventName

        let points: [CDTrackPoint] = trackPointsPayloads.map { payload in
            let point = CDTrackPoint()
            point.timestamp = ISO8601DateFormatter.parse(payload.timestamp) ?? Date()
            point.latitude = payload.latitude
            point.longitude = payload.longitude
            point.altitudeMeters = payload.altitudeMeters
            point.speedMps = payload.speedMps
            point.heartRateBpm = payload.heartRateBpm
            point.cadenceRpm = payload.cadenceRpm
            return point
        }
        activity.trackPoints = points

        modelContext.insert(activity)
        for point in points { modelContext.insert(point) }
        try? modelContext.save()
        activities.insert(activity, at: 0)
        return activity
    }

    func rename(_ activity: CDActivity, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        activity.eventName = trimmed.isEmpty ? nil : trimmed
        try? modelContext.save()
    }

    func delete(_ activity: CDActivity) {
        modelContext.delete(activity)
        try? modelContext.save()
        activities.removeAll { $0.id == activity.id }
    }

    func coordinates(for activity: CDActivity) -> [CLLocationCoordinate2D] {
        activity.trackPoints
            .sorted { $0.timestamp < $1.timestamp }
            .map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }
}