import AVKit
import PhotosUI
import SwiftUI

private enum ShareTemplate: Int, CaseIterable, Identifiable {
    case classic, mapCard, video
    var id: Int { rawValue }
}

/// Lets the user export the route as three swipeable templates — a plain
/// card (path line over a custom photo or dark background), a dedicated map
/// card (real MapKit imagery + route overlay), and a slow animated video —
/// and share whichever is on screen via the system share sheet. The classic
/// template renders immediately on open; the map card loads asynchronously;
/// the video only renders on demand (it's the expensive one).
struct ShareActivityView: View {
    let activity: CDActivity
    let coordinates: [CLLocationCoordinate2D]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var photo: UIImage?
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var composedImage: UIImage?
    @State private var mapCardImage: UIImage?
    @State private var template: ShareTemplate = .classic
    @State private var videoURL: URL?
    @State private var isGeneratingVideo = false
    @State private var videoError: String?

    private var stats: ShareImageComposer.Stats {
        let pace = Formatters.paceOrSpeed(
            sportType: activity.sportType,
            averagePaceSecondsPerKm: activity.averagePaceSecondsPerKm,
            averageSpeedMps: activity.averageSpeedMps
        )
        return ShareImageComposer.Stats(
            symbolName: activity.sportType.symbolName,
            sportLabel: activity.sportType.label,
            distance: Formatters.distance(meters: activity.distanceMeters.map(Double.init)),
            duration: Formatters.duration(seconds: activity.durationSeconds),
            // Pace is always per-km; the "/km" unit is redundant on the share card.
            paceOrSpeed: activity.sportType.usesPaceMetric
                ? pace.replacingOccurrences(of: " /km", with: "")
                : pace,
            date: Formatters.displayDate(date: activity.startedAt)
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TabView(selection: $template) {
                    preview(composedImage).tag(ShareTemplate.classic)
                    preview(mapCardImage).tag(ShareTemplate.mapCard)
                    videoPreview.tag(ShareTemplate.video)
                }
                .tabViewStyle(.page)
                .frame(maxHeight: 420)

                if template == .classic {
                    HStack(spacing: 12) {
                        Button {
                            showCamera = true
                        } label: {
                            Label("Camera", systemImage: "camera.fill")
                        }
                        .buttonStyle(.bordered)

                        PhotosPicker(selection: $photoPickerItem, matching: .images) {
                            Label("Gallery", systemImage: "photo.fill")
                        }
                        .buttonStyle(.bordered)
                    }

                    if photo != nil {
                        Button(role: .destructive) {
                            photo = nil
                        } label: {
                            Label("Plain background", systemImage: "xmark.circle")
                                .font(.subheadline)
                        }
                        .buttonStyle(.plain)
                    }
                }

                shareControl

                Spacer()
            }
            .padding()
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                recomposeClassic()
                Task { await recomposeMapCard() }
            }
            .onChange(of: photo) { recomposeClassic() }
            .onChange(of: photoPickerItem) {
                Task { await loadPickedPhoto() }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraCaptureView { photo = $0 }
                    .ignoresSafeArea()
            }
            .alert("Couldn't create video", isPresented: Binding(
                get: { videoError != nil },
                set: { if !$0 { videoError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(videoError ?? "")
            }
        }
    }

    @ViewBuilder
    private func preview(_ image: UIImage?) -> some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        } else {
            RoundedRectangle(cornerRadius: 16)
                .fill(.fill.tertiary)
                .aspectRatio(0.5625, contentMode: .fit)
                .overlay { ProgressView() }
        }
    }

    @ViewBuilder
    private var videoPreview: some View {
        if let videoURL {
            VideoPlayer(player: AVPlayer(url: videoURL))
                .aspectRatio(0.5625, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        } else {
            RoundedRectangle(cornerRadius: 16)
                .fill(.fill.tertiary)
                .aspectRatio(0.5625, contentMode: .fit)
                .overlay {
                    if isGeneratingVideo {
                        ProgressView("Rendering\u{2026}")
                    } else {
                        Button("Generate video") {
                            Task { await generateVideo() }
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private var shareControl: some View {
        switch template {
        case .classic, .mapCard:
            let image = template == .classic ? composedImage : mapCardImage
            ShareLink(
                item: Image(uiImage: image ?? UIImage()),
                preview: SharePreview("My Larping activity", image: Image(uiImage: image ?? UIImage()))
            ) {
                Label("Share", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(colorScheme == .dark ? .black : .white)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(image == nil)

        case .video:
            if let videoURL {
                ShareLink(item: videoURL) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(colorScheme == .dark ? .black : .white)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }

    private func recomposeClassic() {
        composedImage = ShareImageComposer.compose(
            photo: photo,
            coordinates: coordinates,
            stats: stats
        )
    }

    private func recomposeMapCard() async {
        mapCardImage = await ShareImageComposer.composeMapCard(coordinates: coordinates, stats: stats)
    }

    private func generateVideo() async {
        isGeneratingVideo = true
        defer { isGeneratingVideo = false }
        do {
            videoURL = try await ShareVideoComposer.composeVideo(coordinates: coordinates, stats: stats)
        } catch {
            videoError = error.localizedDescription
        }
    }

    private func loadPickedPhoto() async {
        guard let photoPickerItem,
              let data = try? await photoPickerItem.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        photo = image
    }
}
