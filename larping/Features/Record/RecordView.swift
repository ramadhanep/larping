import MapKit
import SwiftData
import SwiftUI

struct RecordView: View {
    @Environment(ActivitiesStore.self) private var activitiesStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @State private var tracker = LocationTracker()
    @State private var elapsedSeconds = 0
    @State private var timer: Timer?
    @State private var selectedSport: SportType = .run
    @State private var eventName = ""
    @State private var eventEdited = false
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var showSavedConfirmation = false
    @State private var savedDistance: Double = 0

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Map(position: $cameraPosition) {
                    // History heatmap: every past route stacked at low opacity —
                    // overlapping segments blend brighter, giving a "heat" build-up
                    // without a real spatial-binning pass.
                    ForEach(activitiesStore.activities) { pastActivity in
                        let points = activitiesStore.coordinates(for: pastActivity)
                        if points.count > 1 {
                            MapPolyline(coordinates: points)
                                .stroke(Color.accentColor.opacity(0.12), lineWidth: 3)
                        }
                    }

                    if tracker.routeCoordinates.count > 1 {
                        MapPolyline(coordinates: tracker.routeCoordinates)
                            .stroke(.accent, lineWidth: 5)
                    }

                    if let tip = tracker.routeCoordinates.last, tracker.state != .idle {
                        Annotation("", coordinate: tip) {
                            Image(systemName: selectedSport.symbolName)
                                .font(.subheadline.bold())
                                .foregroundStyle(.white)
                                .padding(7)
                                .background(.accent, in: Circle())
                                .symbolEffect(.bounce, options: .repeating, isActive: tracker.state == .recording)
                        }
                    } else {
                        UserAnnotation()
                    }
                }
                .ignoresSafeArea(edges: .top)
                .onChange(of: tracker.routeCoordinates.last?.latitude) {
                    guard tracker.state == .recording else { return }
                    cameraPosition = .userLocation(fallback: .automatic)
                }

                controls
                    .padding()
                    .background(colorScheme == .dark ? AnyShapeStyle(Color.black) : AnyShapeStyle(.thinMaterial))
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
            .navigationTitle("Record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        cameraPosition = .userLocation(fallback: .automatic)
                    } label: {
                        Image(systemName: "location.fill")
                    }
                }
            }
            .task { tracker.requestPermission() }
            .onChange(of: selectedSport) {
                guard !eventEdited else { return }
                eventName = suggestedEventName(for: selectedSport)
            }
            .onAppear { eventName = suggestedEventName(for: selectedSport) }
            .alert("Activity saved", isPresented: $showSavedConfirmation) {
                Button("Done", role: .cancel) {}
            } message: {
                Text("\(Formatters.distance(meters: savedDistance)) recorded. \nYou can view or delete it from the Activities tab.")
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 16) {
            if tracker.state == .idle {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Menu {
                            ForEach(SportType.allCases) { sport in
                                Button {
                                    selectedSport = sport
                                } label: {
                                    Label(sport.label, systemImage: sport.symbolName)
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: selectedSport.symbolName)
                                Text(selectedSport.label)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .font(.subheadline.weight(.semibold))
                            .padding(.vertical, 14)
                            .padding(.horizontal, 16)
                            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 14))
                        }

                        TextField("Event name", text: Binding(
                            get: { eventName },
                            set: { eventName = $0; eventEdited = true }
                        ))
                        .font(.subheadline.weight(.medium))
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 14))
                    }

                    if eventName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Event name is required to start.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Label(selectedSport.label, systemImage: selectedSport.symbolName)
                        .font(.headline)
                        .foregroundStyle(.accent)
                        .symbolEffect(.bounce, options: .repeating, isActive: tracker.state == .recording)
                    Spacer()
                    Text(eventName.isEmpty ? "Larping \(selectedSport.label)" : eventName)
                        .font(.headline)
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }

            HStack(spacing: 32) {
                StatColumn(title: "Time", value: Formatters.duration(seconds: elapsedSeconds))
                StatColumn(title: "Distance", value: Formatters.distance(meters: tracker.distanceMeters))
                StatColumn(
                    title: selectedSport.usesPaceMetric ? "Pace" : "Speed",
                    value: selectedSport.usesPaceMetric
                        ? Formatters.paceFromSpeed(metersPerSecond: tracker.currentSpeedMps)
                        : Formatters.speed(metersPerSecond: tracker.currentSpeedMps)
                )
            }

            switch tracker.state {
            case .idle:
                Button {
                    startRecording()
                } label: {
                    Label("Start", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(colorScheme == .dark ? .black : .white)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(
                    tracker.authorizationStatus == .denied || tracker.authorizationStatus == .restricted
                        || eventName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )

            case .recording:
                HStack(spacing: 16) {
                    Button {
                        tracker.pause()
                        stopTimer()
                    } label: {
                        Label("Pause", systemImage: "pause.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button(role: .destructive) {
                        finishRecording()
                    } label: {
                        Label("Finish", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

            case .paused:
                HStack(spacing: 16) {
                    Button {
                        tracker.resume()
                        startTimer()
                    } label: {
                        Label("Resume", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button(role: .destructive) {
                        finishRecording()
                    } label: {
                        Label("Finish", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }

            if tracker.authorizationStatus == .denied || tracker.authorizationStatus == .restricted {
                Text("Location access is off. Enable it in Settings to record a route.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else if tracker.authorizationStatus == .notDetermined {
                Text("Allow location access to see your route on the map.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 8)
    }

    private func startRecording() {
        tracker.start()
        elapsedSeconds = 0
        cameraPosition = .userLocation(fallback: .automatic)
        startTimer()
    }

    private func finishRecording() {
        stopTimer()
        let recording = tracker.stop()
        savedDistance = recording.distanceMeters
        let title = eventName.trimmingCharacters(in: .whitespacesAndNewlines)
        activitiesStore.create(
            sportType: selectedSport,
            startedAt: recording.startedAt,
            endedAt: recording.endedAt,
            durationSeconds: Int(recording.endedAt.timeIntervalSince(recording.startedAt)),
            distanceMeters: Int(recording.distanceMeters),
            elevationGainMeters: recording.elevationGainMeters > 0 ? Int(recording.elevationGainMeters) : nil,
            averageSpeedMps: averageSpeedMps(recording),
            maxSpeedMps: recording.maxSpeedMps > 0 ? recording.maxSpeedMps : nil,
            source: "mobile",
            eventName: title.isEmpty ? suggestedEventName(for: selectedSport) : title,
            trackPointsPayloads: recording.trackPoints
        )
        showSavedConfirmation = true
        eventEdited = false
        eventName = suggestedEventName(for: selectedSport)
    }

    private func suggestedEventName(for sport: SportType) -> String {
        let all = (try? modelContext.fetch(FetchDescriptor<CDActivity>())) ?? []
        return EventNamer.nextName(base: "Larping \(sport.label)", existing: all.compactMap(\.eventName))
    }

    private func averageSpeedMps(_ recording: LocationTracker.Recording) -> Double? {
        let duration = recording.endedAt.timeIntervalSince(recording.startedAt)
        return duration > 0 ? recording.distanceMeters / duration : nil
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in elapsedSeconds += 1 }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

private struct StatColumn: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.monospacedDigit().bold())
            Text(title.uppercased()).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}