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

    /// Test seam — nil means persist via the real `modelContext.save()`. Lets a
    /// test force a persistence failure so save-ordering + rollback recovery can
    /// be asserted without breaking a real disk store.
    var persistOperation: (() throws -> Void)?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    private func persist() throws {
        if let persistOperation {
            try persistOperation()
        } else {
            try modelContext.save()
        }
    }

    func refresh() {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            // No fetch limit: `activities` backs Stats' all-time totals/bests as
            // well as the Record heatmap, so capping here would silently drop
            // old activities from the stats. The heatmap bounds itself instead
            // (`RecordView` slices the most-recent 500).
            let descriptor = FetchDescriptor<CDActivity>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
            activities = try modelContext.fetch(descriptor)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Creates + persists an activity. Throws if the save fails (e.g. disk
    /// full) — recording auto-save and imports must never silently drop an
    /// activity. The activity is only added to the in-memory list once the
    /// store actually persisted it, so a failed save can't masquerade as
    /// success in the UI.
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
    ) throws -> CDActivity {
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
        do {
            try persist()
        } catch {
            // A failed save leaves the inserts pending in the context. Roll them
            // back so the phantom activity can't surface in the @Query list or
            // get committed by a later unrelated save.
            modelContext.rollback()
            throw error
        }
        activities.insert(activity, at: 0)
        return activity
    }

    /// Renames an activity's event title. Throws on persistence failure — the
    /// in-memory name is reverted so the UI can never show a title the store
    /// didn't persist.
    func rename(_ activity: CDActivity, to name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let newName = trimmed.isEmpty ? nil : trimmed
        guard newName != activity.eventName else { return }
        let oldName = activity.eventName
        activity.eventName = newName
        do {
            try persist()
        } catch {
            activity.eventName = oldName
            throw error
        }
    }

    /// Deletes an activity (cascade removes its points). Throws on persistence
    /// failure — the pending delete is rolled back and the activity stays live
    /// in memory, so a deletion that didn't persist can't masquerade as done.
    func delete(_ activity: CDActivity) throws {
        modelContext.delete(activity)
        do {
            try persist()
        } catch {
            modelContext.rollback()
            throw error
        }
        activities.removeAll { $0.id == activity.id }
    }

    func coordinates(for activity: CDActivity) -> [CLLocationCoordinate2D] {
        activity.trackPoints
            .sorted { $0.timestamp < $1.timestamp }
            .map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }
}