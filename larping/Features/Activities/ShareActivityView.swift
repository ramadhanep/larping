import AVKit
import PhotosUI
import SwiftUI

private enum ShareTemplate: Int, CaseIterable, Identifiable {
    case classic, mapCard, video
    var id: Int { rawValue }
}

/// Lets the user export the route as three swipeable templates — a plain card
/// (path line over a custom photo, or a transparent PNG on its own), a map
/// template (real MapKit imagery + route + info card), and an animated video
/// over the same map — and share whichever is on screen via the system share
/// sheet. The classic template renders immediately; the map card loads
/// asynchronously; the video only renders on demand (a "Generate video" button
/// styled like Share) because it's the expensive one. Generated video lives in
/// a temp file and is cleaned up when this sheet closes unless the user saved
/// it somewhere first.
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
    @State private var fullPreview: UIImage?

    /// The user-typed event title wins; casing is preserved exactly as entered.
    /// Old/imported activities without one fall back to "Larping <Sport>".
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
            date: Formatters.displayDate(date: activity.startedAt),
            title: activity.eventName ?? ""
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                TabView(selection: $template) {
                    classicPreview.tag(ShareTemplate.classic)
                    preview(mapCardImage).tag(ShareTemplate.mapCard)
                    videoPreview.tag(ShareTemplate.video)
                }
                .tabViewStyle(.page)
                .frame(maxHeight: 640)

                shareSection

                if template == .classic {
                    HStack(spacing: 12) {
                        Button {
                            showCamera = true
                        } label: {
                            Label("Camera", systemImage: "camera.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        PhotosPicker(selection: $photoPickerItem, matching: .images) {
                            Label("Gallery", systemImage: "photo.fill")
                                .frame(maxWidth: .infinity)
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

                Spacer(minLength: 0)
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
            .onDisappear { cleanupVideo() }
            .fullScreenCover(isPresented: $showCamera) {
                CameraCaptureView { photo = $0 }
                    .ignoresSafeArea()
            }
            .fullScreenCover(isPresented: Binding(
                get: { fullPreview != nil },
                set: { if !$0 { fullPreview = nil } }
            )) {
                if let fullPreview {
                    ZStack {
                        Color.black.ignoresSafeArea()
                        ScrollView {
                            Image(uiImage: fullPreview)
                                .resizable()
                                .scaledToFit()
                        }
                        VStack {
                            HStack {
                                Spacer()
                                Button {
                                    self.fullPreview = nil
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title)
                                        .foregroundStyle(.white)
                                        .padding()
                                }
                            }
                            Spacer()
                        }
                    }
                }
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

    /// The classic template's photo-less card is a *transparent* PNG (see
    /// `ShareImageComposer.compose`) — its white content disappears against a
    /// light-mode background. A black backing here makes it visible in the
    /// preview only; the exported/shared image stays transparent.
    @ViewBuilder
    private var classicPreview: some View {
        if let composedImage {
            Image(uiImage: composedImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .background(photo == nil ? Color.black : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .contentShape(RoundedRectangle(cornerRadius: 20))
                .onTapGesture { fullPreview = composedImage }
        } else {
            RoundedRectangle(cornerRadius: 20)
                .fill(.fill.tertiary)
                .aspectRatio(0.5625, contentMode: .fit)
                .overlay { ProgressView() }
        }
    }

    @ViewBuilder
    private func preview(_ image: UIImage?) -> some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .contentShape(RoundedRectangle(cornerRadius: 20))
                .onTapGesture { fullPreview = image }
        } else {
            RoundedRectangle(cornerRadius: 20)
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
                .clipShape(RoundedRectangle(cornerRadius: 20))
        } else if let mapCardImage {
            preview(mapCardImage)
        } else {
            RoundedRectangle(cornerRadius: 20)
                .fill(.fill.tertiary)
                .aspectRatio(0.5625, contentMode: .fit)
                .overlay { ProgressView() }
        }
    }

    /// Share (or, for the video template, the generate trigger) styled as the
    /// primary action. Camera/gallery sit below it so template swiping never
    /// shuffles the controls.
    @ViewBuilder
    private var shareSection: some View {
        switch template {
        case .classic:
            imageShareLink(composedImage)
        case .mapCard:
            imageShareLink(mapCardImage)
        case .video:
            if let videoURL {
                ShareLink(item: videoURL) {
                    Label("Share video", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(colorScheme == .dark ? .black : .white)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Button {
                    Task { await generateVideo() }
                } label: {
                    if isGeneratingVideo {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("Generate video", systemImage: "film")
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(colorScheme == .dark ? .black : .white)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isGeneratingVideo)
            }
        }
    }

    @ViewBuilder
    private func imageShareLink(_ image: UIImage?) -> some View {
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
    }

    private func recomposeClassic() {
        composedImage = ShareImageComposer.compose(
            photo: photo,
            coordinates: coordinates,
            stats: stats
        )
    }

    private func recomposeMapCard() async {
        let snapshot = await ShareImageComposer.mapSnapshot(coordinates: coordinates)
        mapCardImage = ShareImageComposer.composeMapCard(snapshot: snapshot, coordinates: coordinates, stats: stats)
    }

    private func generateVideo() async {
        isGeneratingVideo = true
        defer { isGeneratingVideo = false }
        do {
            let snapshot = await ShareImageComposer.mapSnapshot(coordinates: coordinates)
            videoURL = try await ShareVideoComposer.composeVideo(snapshot: snapshot, coordinates: coordinates, stats: stats)
        } catch {
            videoError = error.localizedDescription
        }
    }

    private func cleanupVideo() {
        if let videoURL { try? FileManager.default.removeItem(at: videoURL) }
        videoURL = nil
    }

    private func loadPickedPhoto() async {
        guard let photoPickerItem,
              let data = try? await photoPickerItem.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        photo = image
    }
}