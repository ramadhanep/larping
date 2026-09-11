import SwiftData
import XCTest
@testable import larping

final class BackupServiceTests: XCTestCase {
    private func makeInMemoryContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: CDActivity.self, CDTrackPoint.self, configurations: config)
        return ModelContext(container)
    }

    private func makeActivity() -> CDActivity {
        let activity = CDActivity()
        activity.distanceMeters = 1000
        activity.durationSeconds = 300
        let point = CDTrackPoint()
        point.latitude = 1
        point.longitude = 1
        activity.trackPoints = [point]
        return activity
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

    func testRestoreRejectsNonLarpingFile() throws {
        let junk = try JSONEncoder().encode(["hello": "world"])
        let context = try makeInMemoryContext()
        XCTAssertThrowsError(try BackupService.restore(from: junk, into: context))
    }
}
