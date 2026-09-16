import SwiftData
import XCTest
@testable import larping

@MainActor
final class ActivitiesStoreTests: XCTestCase {
    /// Creates an in-memory container + store over it, returning both so tests
    /// can re-fetch through the container to prove real persistence.
    private func makeStore() throws -> (store: ActivitiesStore, container: ModelContainer) {
        let container = try ModelContainer(
            for: CDActivity.self, CDTrackPoint.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return (ActivitiesStore(modelContext: ModelContext(container)), container)
    }

    private func payload(timestamp: String = "2026-01-01T10:00:00Z") -> TrackPointPayload {
        TrackPointPayload(
            timestamp: timestamp,
            latitude: 1,
            longitude: 1,
            altitudeMeters: nil,
            speedMps: nil,
            heartRateBpm: nil,
            cadenceRpm: nil
        )
    }

    func testCreatePersistsAndAppearsInStore() throws {
        let (store, container) = try makeStore()
        store.refresh()

        let activity = try store.create(
            sportType: .run,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_000_300),
            durationSeconds: 300,
            distanceMeters: 1000,
            elevationGainMeters: nil,
            averageSpeedMps: 3.33,
            maxSpeedMps: 5,
            source: "mobile",
            eventName: "Morning Run",
            trackPointsPayloads: [payload()]
        )

        // In-memory list is live.
        XCTAssertTrue(store.activities.contains { $0.id == activity.id })

        // Re-fetch through a fresh context over the same store.
        let saved = try container.mainContext.fetch(FetchDescriptor<CDActivity>())
        let reloaded = try XCTUnwrap(saved.first)
        XCTAssertEqual(reloaded.eventName, "Morning Run")
        XCTAssertEqual(reloaded.sportType, .run)
        XCTAssertEqual(reloaded.trackPoints.count, 1)
    }

    func testRenameTrimsAndEmptyClearsToNil() throws {
        let (store, container) = try makeStore()
        store.refresh()
        let activity = try store.create(
            sportType: .ride,
            startedAt: Date(),
            endedAt: Date(),
            durationSeconds: nil,
            distanceMeters: nil,
            elevationGainMeters: nil,
            averageSpeedMps: nil,
            maxSpeedMps: nil,
            source: "mobile",
            eventName: "Ride",
            trackPointsPayloads: []
        )

        try store.rename(activity, to: "  Evening Ride  ")
        XCTAssertEqual(activity.eventName, "Evening Ride")
        let saved = try container.mainContext.fetch(FetchDescriptor<CDActivity>())
        XCTAssertEqual(saved.first?.eventName, "Evening Ride")

        try store.rename(activity, to: "   ")
        XCTAssertNil(activity.eventName)
    }

    func testDeleteRemovesFromStoreAndContext() throws {
        let (store, container) = try makeStore()
        store.refresh()
        let activity = try store.create(
            sportType: .walk,
            startedAt: Date(),
            endedAt: Date(),
            durationSeconds: nil,
            distanceMeters: nil,
            elevationGainMeters: nil,
            averageSpeedMps: nil,
            maxSpeedMps: nil,
            source: "mobile",
            trackPointsPayloads: []
        )

        try store.delete(activity)
        XCTAssertFalse(store.activities.contains { $0.id == activity.id })
        let remaining = try container.mainContext.fetch(FetchDescriptor<CDActivity>())
        XCTAssertTrue(remaining.isEmpty)
    }

    /// Record history heatmap + Stats share `store.activities`; nothing may
    /// silently cap the list that feeds all-time stats. The heatmap bounds
    /// itself (RecordView slices the 500 most recent), not the store.
    func testRefreshLoadsAllActivitiesWithoutCap() throws {
        let (store, container) = try makeStore()
        for i in 0..<600 {
            let activity = CDActivity()
            activity.startedAt = Date(timeIntervalSince1970: Double(1_700_000_000 + i))
            container.mainContext.insert(activity)
        }
        try container.mainContext.save()

        store.refresh()
        XCTAssertEqual(store.activities.count, 600)
    }

    /// A failed save must leave zero trace: no phantom activity in the store's
    /// in-memory list, and — via a fresh context over the same store — nothing
    /// pending that could surface in the list or a later unrelated save.
    func testCreateRollsBackOnFailedSave() throws {
        let (store, container) = try makeStore()
        store.persistOperation = { throw TestSaveError() }

        XCTAssertThrowsError(try store.create(
            sportType: .run,
            startedAt: Date(),
            endedAt: Date(),
            durationSeconds: nil,
            distanceMeters: nil,
            elevationGainMeters: nil,
            averageSpeedMps: nil,
            maxSpeedMps: nil,
            source: "mobile",
            trackPointsPayloads: [payload()]
        ))
        XCTAssertTrue(store.activities.isEmpty)
        let fresh = ModelContext(container)
        XCTAssertTrue(try fresh.fetch(FetchDescriptor<CDActivity>()).isEmpty)
        XCTAssertTrue(try fresh.fetch(FetchDescriptor<CDTrackPoint>()).isEmpty)
    }

    /// A failed rename must not leave the in-memory activity carrying a name the
    /// store didn't persist (UI would show "renamed" until relaunch) — revert +
    /// throw, not silent swallow.
    func testRenameFailureKeepsStoredName() throws {
        let (store, container) = try makeStore()
        let activity = try store.create(
            sportType: .ride,
            startedAt: Date(),
            endedAt: Date(),
            durationSeconds: nil,
            distanceMeters: nil,
            elevationGainMeters: nil,
            averageSpeedMps: nil,
            maxSpeedMps: nil,
            source: "mobile",
            eventName: "Old Name",
            trackPointsPayloads: []
        )

        store.persistOperation = { throw TestSaveError() }
        XCTAssertThrowsError(try store.rename(activity, to: "New Name"))

        XCTAssertEqual(activity.eventName, "Old Name")
        let fresh = ModelContext(container)
        XCTAssertEqual(try fresh.fetch(FetchDescriptor<CDActivity>()).first?.eventName, "Old Name")
    }

    /// A failed delete must keep the activity live in memory AND the store — a
    /// "deleted" activity that resurrects on next launch is a lie.
    func testDeleteFailureKeepsActivity() throws {
        let (store, container) = try makeStore()
        let activity = try store.create(
            sportType: .walk,
            startedAt: Date(),
            endedAt: Date(),
            durationSeconds: nil,
            distanceMeters: nil,
            elevationGainMeters: nil,
            averageSpeedMps: nil,
            maxSpeedMps: nil,
            source: "mobile",
            trackPointsPayloads: []
        )

        store.persistOperation = { throw TestSaveError() }
        XCTAssertThrowsError(try store.delete(activity))

        XCTAssertTrue(store.activities.contains { $0.id == activity.id })
        let fresh = ModelContext(container)
        let remaining = try fresh.fetch(FetchDescriptor<CDActivity>())
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.id, activity.id)
    }
}

private struct TestSaveError: Error {}