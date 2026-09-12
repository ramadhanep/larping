import SwiftUI
import UniformTypeIdentifiers

struct ImportGPXView: View {
    @Environment(ActivitiesStore.self) private var activitiesStore
    @Environment(\.dismiss) private var dismiss

    @State private var showFilePicker = false
    @State private var fileURL: URL?
    @State private var parsed: GPXParser.Result?
    @State private var sportType: SportType = .run
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var gpxType: UTType { UTType(filenameExtension: "gpx") ?? .xml }

    var body: some View {
        NavigationStack {
            Form {
                Section("File") {
                    Button {
                        showFilePicker = true
                    } label: {
                        Label(fileURL?.lastPathComponent ?? "Choose GPX file", systemImage: "doc.badge.plus")
                    }
                }

                if let parsed {
                    Section("Details") {
                        Picker("Sport", selection: $sportType) {
                            ForEach(SportType.allCases) { sport in
                                Label(sport.label, systemImage: sport.symbolName).tag(sport)
                            }
                        }
                    }
                    Section("Summary") {
                        LabeledContent("Distance", value: Formatters.distance(meters: parsed.distanceMeters))
                        LabeledContent("Points", value: "\(parsed.trackPoints.count)")
                        if parsed.elevationGainMeters > 0 {
                            LabeledContent("Elevation gain", value: Formatters.elevation(meters: parsed.elevationGainMeters))
                        }
                    }
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Import GPX")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving { ProgressView() } else { Text("Import") }
                    }
                    .disabled(parsed == nil || isSaving)
                }
            }
            .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [gpxType, .xml]) { result in
                handlePickedFile(result)
            }
        }
    }

    private func handlePickedFile(_ result: Result<URL, Error>) {
        errorMessage = nil
        parsed = nil
        do {
            let url = try result.get()
            guard url.startAccessingSecurityScopedResource() else {
                errorMessage = "Couldn't access the selected file."
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            let data = try Data(contentsOf: url)
            fileURL = url
            parsed = try GPXParser.parse(data: data)
            if let detectedSport = parsed?.sportType {
                sportType = detectedSport
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() async {
        guard let parsed else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let startedAt = parsed.startedAt ?? Date()
        let endedAt = parsed.endedAt ?? startedAt
        let duration = Int(endedAt.timeIntervalSince(startedAt))

        activitiesStore.create(
            sportType: sportType,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: duration > 0 ? duration : nil,
            distanceMeters: Int(parsed.distanceMeters),
            elevationGainMeters: parsed.elevationGainMeters > 0 ? Int(parsed.elevationGainMeters) : nil,
            averageSpeedMps: duration > 0 ? parsed.distanceMeters / Double(duration) : nil,
            maxSpeedMps: nil,
            source: "gpx_import",
            trackPointsPayloads: parsed.trackPoints
        )
        dismiss()
    }
}