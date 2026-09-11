import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// JSON backup of every activity (with its track points), exported via the
/// system file exporter so the user can save it anywhere — including iCloud
/// Drive through the Files app. Plain Codable structs (not the `@Model`
/// classes) so the payload is stable and restorable later.
enum BackupService {
    /// Builds the export payload for the given context.
    static func backupFile(from context: ModelContext) throws -> BackupFile {
        var descriptor = FetchDescriptor<CDActivity>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        descriptor.fetchLimit = 2000
        let activities = (try? context.fetch(descriptor)) ?? []

        let backups = activities.map { activity -> BackupActivity in
            BackupActivity(
                id: activity.id,
                sportTypeRaw: activity.sportTypeRaw,
                startedAt: activity.startedAt,
                endedAt: activity.endedAt,
                durationSeconds: activity.durationSeconds,
                distanceMeters: activity.distanceMeters,
                elevationGainMeters: activity.elevationGainMeters,
                averageSpeedMps: activity.averageSpeedMps,
                maxSpeedMps: activity.maxSpeedMps,
                source: activity.source,
                createdAt: activity.createdAt,
                trackPoints: activity.trackPoints
                    .sorted { $0.timestamp < $1.timestamp }
                    .map { BackupTrackPoint(
                        id: $0.id,
                        timestamp: $0.timestamp,
                        latitude: $0.latitude,
                        longitude: $0.longitude,
                        altitudeMeters: $0.altitudeMeters,
                        speedMps: $0.speedMps,
                        heartRateBpm: $0.heartRateBpm,
                        cadenceRpm: $0.cadenceRpm
                    ) }
            )
        }

        let container = BackupContainer(
            app: "Larping",
            version: 1,
            exportedAt: Date(),
            activities: backups
        )
        let data = try JSONEncoder.pretty.encode(container)
        return BackupFile(data: data)
    }

    /// Ingests a previously exported backup. Only *adds* — activities whose
    /// id already exists are skipped, so re-importing the same file (or
    /// importing an older backup over newer data) never duplicates or destroys
    /// anything. Returns the number of activities imported (skipped not
    /// counted).
    static func restore(from data: Data, into context: ModelContext) throws -> (imported: Int, skipped: Int) {
        let container: BackupContainer
        do {
            container = try JSONDecoder.backup.decode(BackupContainer.self, from: data)
        } catch {
            throw BackupError.invalidFile
        }
        guard container.app == "Larping" else { throw BackupError.notLarpingFile }

        let existingIDs = Set((try? context.fetch(FetchDescriptor<CDActivity>()))?.map(\.id) ?? [])

        var imported = 0
        var skipped = 0
        for backup in container.activities {
            guard !existingIDs.contains(backup.id) else {
                skipped += 1
                continue
            }
            let activity = CDActivity()
            activity.id = backup.id
            activity.sportTypeRaw = backup.sportTypeRaw
            activity.startedAt = backup.startedAt
            activity.endedAt = backup.endedAt
            activity.durationSeconds = backup.durationSeconds
            activity.distanceMeters = backup.distanceMeters
            activity.elevationGainMeters = backup.elevationGainMeters
            activity.averageSpeedMps = backup.averageSpeedMps
            activity.maxSpeedMps = backup.maxSpeedMps
            activity.source = backup.source
            activity.createdAt = backup.createdAt

            let points = backup.trackPoints.map { backupPoint in
                let point = CDTrackPoint()
                point.id = backupPoint.id
                point.timestamp = backupPoint.timestamp
                point.latitude = backupPoint.latitude
                point.longitude = backupPoint.longitude
                point.altitudeMeters = backupPoint.altitudeMeters
                point.speedMps = backupPoint.speedMps
                point.heartRateBpm = backupPoint.heartRateBpm
                point.cadenceRpm = backupPoint.cadenceRpm
                return point
            }
            activity.trackPoints = points
            context.insert(activity)
            for point in points { context.insert(point) }
            imported += 1
        }
        try context.save()
        return (imported, skipped)
    }
}

enum BackupError: LocalizedError {
    case invalidFile
    case notLarpingFile

    var errorDescription: String? {
        switch self {
        case .invalidFile: return "That file isn't a valid Larping backup."
        case .notLarpingFile: return "That file isn't a Larping backup."
        }
    }
}

struct BackupContainer: Codable {
    let app: String
    let version: Int
    let exportedAt: Date
    let activities: [BackupActivity]
}

struct BackupActivity: Codable {
    let id: UUID
    let sportTypeRaw: String
    let startedAt: Date
    let endedAt: Date?
    let durationSeconds: Int?
    let distanceMeters: Int?
    let elevationGainMeters: Int?
    let averageSpeedMps: Double?
    let maxSpeedMps: Double?
    let source: String
    let createdAt: Date
    let trackPoints: [BackupTrackPoint]
}

struct BackupTrackPoint: Codable {
    let id: UUID
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let altitudeMeters: Double?
    let speedMps: Double?
    let heartRateBpm: Int?
    let cadenceRpm: Int?
}

/// Cross-app `FileDocument` for SwiftUI's `fileExporter` — the user can pick
/// any Files destination, including iCloud Drive.
struct BackupFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

extension JSONEncoder {
    static let pretty: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

extension JSONDecoder {
    /// Mirrors `JSONEncoder.pretty`'s date strategy, so exports round-trip.
    static let backup: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}