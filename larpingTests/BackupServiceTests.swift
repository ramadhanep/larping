import SwiftData
import XCTest
@testable import larping

final class BackupServiceTests: XCTestCase {
    private func makeInMemoryContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: CDActivity.self, CDTrackPoint.self, configurations: config)
        return ModelContext(container)
    }

    private func makeActivity(pointCount: Int = 1) -> CDActivity {
        let activity = CDActivity()
        activity.distanceMeters = 1000
        activity.durationSeconds = 300
        activity.trackPoints = (0..<pointCount).map { i in
            let point = CDTrackPoint()
            point.latitude = 1
            point.longitude = Double(i) + 1
            return point
        }
        return activity
    }

    private func backupActivity(id: UUID = UUID()) -> BackupActivity {
        BackupActivity(
            id: id,
            sportTypeRaw: "run",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: nil,
            durationSeconds: nil,
            distanceMeters: 1000,
            elevationGainMeters: nil,
            averageSpeedMps: nil,
            maxSpeedMps: nil,
            source: "mobile",
            eventName: nil,
            createdAt: Date(),
            trackPoints: [BackupTrackPoint(
                id: UUID(),
                timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                latitude: 1,
                longitude: 1,
                altitudeMeters: nil,
                speedMps: nil,
                heartRateBpm: nil,
                cadenceRpm: nil
            )]
        )
    }

    func testExportImportRoundTrip() throws {
        let sourceContext = try makeInMemoryContext()
        let activity = makeActivity()
        sourceContext.insert(activity)
        try sourceContext.save()

        let backup = try BackupService.backupFile(from: sourceContext)

        let destinationContext = try makeInMemoryContext()
        let result = try BackupService.restore(from: backup.data, into: destinationContext)

        XCTAssertEqual(result.imported, 1)
        XCTAssertEqual(result.skipped, 0)

        let restored = try destinationContext.fetch(FetchDescriptor<CDActivity>())
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored.first?.distanceMeters, 1000)
        XCTAssertEqual(restored.first?.trackPoints.count, 1)
    }

    func testReimportSameBackupSkipsExisting() throws {
        let sourceContext = try makeInMemoryContext()
        sourceContext.insert(makeActivity())
        try sourceContext.save()
        let backup = try BackupService.backupFile(from: sourceContext)

        let destinationContext = try makeInMemoryContext()
        _ = try BackupService.restore(from: backup.data, into: destinationContext)
        let second = try BackupService.restore(from: backup.data, into: destinationContext)

        XCTAssertEqual(second.imported, 0)
        XCTAssertEqual(second.skipped, 1)
    }

    /// Re-importing the same backup must not duplicate track points underneath
    /// the skipped activity — verified through a fresh context.
    func testReimportSameBackupDoesNotDuplicateTrackPoints() throws {
        let sourceContext = try makeInMemoryContext()
        sourceContext.insert(makeActivity(pointCount: 2))
        try sourceContext.save()
        let backup = try BackupService.backupFile(from: sourceContext)

        let destinationContext = try makeInMemoryContext()
        _ = try BackupService.restore(from: backup.data, into: destinationContext)
        _ = try BackupService.restore(from: backup.data, into: destinationContext)

        let fresh = ModelContext(destinationContext.container)
        let activities = try fresh.fetch(FetchDescriptor<CDActivity>())
        XCTAssertEqual(activities.count, 1)
        XCTAssertEqual(activities.first?.trackPoints.count, 2)
    }

    /// A malformed backup listing the same activity id twice must import it
    /// once, never twice — the "never duplicates" rule holds inside a single
    /// file too.
    func testRestoreSkipsDuplicateIdsWithinBackup() throws {
        let destinationContext = try makeInMemoryContext()
        let id = UUID()
        let data = try JSONEncoder.pretty.encode(BackupContainer(
            app: "Larping",
            version: 1,
            exportedAt: Date(),
            activities: [backupActivity(id: id), backupActivity(id: id)]
        ))

        let result = try BackupService.restore(from: data, into: destinationContext)
        XCTAssertEqual(result.imported, 1)
        XCTAssertEqual(result.skipped, 1)
        let fresh = ModelContext(destinationContext.container)
        XCTAssertEqual(try fresh.fetch(FetchDescriptor<CDActivity>()).count, 1)
    }

    /// A failed restore save must leave no partial import behind: the store ends
    /// up exactly as it was, so re-importing after fixing the cause is clean.
    func testRestoreSaveFailureDoesNotLeavePartialImport() throws {
        let sourceContext = try makeInMemoryContext()
        sourceContext.insert(makeActivity(pointCount: 2))
        try sourceContext.save()
        let backup = try BackupService.backupFile(from: sourceContext)

        let destinationContext = try makeInMemoryContext()
        XCTAssertThrowsError(try BackupService.restore(
            from: backup.data,
            into: destinationContext,
            persist: { _ in throw TestSaveError() }
        ))

        let fresh = ModelContext(destinationContext.container)
        XCTAssertTrue(try fresh.fetch(FetchDescriptor<CDActivity>()).isEmpty)
        XCTAssertTrue(try fresh.fetch(FetchDescriptor<CDTrackPoint>()).isEmpty)
    }

    /// Deleting an imported activity frees its ids (cascade), so re-importing
    /// the same backup revives it with its points exactly once — activity-level
    /// idempotency keys on ids, not point contents, and the cascade in between
    /// means no duplicated track points accumulate.
    func testReimportAfterDeleteRestoresCleanly() throws {
        let sourceContext = try makeInMemoryContext()
        sourceContext.insert(makeActivity(pointCount: 2))
        try sourceContext.save()
        let backup = try BackupService.backupFile(from: sourceContext)

        let destinationContext = try makeInMemoryContext()
        _ = try BackupService.restore(from: backup.data, into: destinationContext)
        let imported = try destinationContext.fetch(FetchDescriptor<CDActivity>())
        XCTAssertEqual(imported.count, 1)
        destinationContext.delete(imported[0])
        try destinationContext.save()
        XCTAssertTrue(try destinationContext.fetch(FetchDescriptor<CDActivity>()).isEmpty)

        let revive = try BackupService.restore(from: backup.data, into: destinationContext)
        XCTAssertEqual(revive.imported, 1)
        XCTAssertEqual(revive.skipped, 0)
        let fresh = ModelContext(destinationContext.container)
        let activities = try fresh.fetch(FetchDescriptor<CDActivity>())
        XCTAssertEqual(activities.count, 1)
        XCTAssertEqual(activities.first?.trackPoints.count, 2)
    }

    func testRestoreRejectsNonLarpingFile() throws {
        let junk = try JSONEncoder().encode(["hello": "world"])
        let context = try makeInMemoryContext()
        XCTAssertThrowsError(try BackupService.restore(from: junk, into: context))
    }
}

private struct TestSaveError: Error {}