import PhotosUI
import SwiftUI

/// Lets the user export the route as an image — the path line composited
/// over either a custom photo (camera or library) or a plain dark background —
/// and share it via the system share sheet. The plain background renders
/// immediately on open; a photo only replaces it when the user picks one.
struct ShareActivityView: View {
    let activity: CDActivity
    let coordinates: [CLLocationCoordinate2D]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var photo: UIImage?
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var composedImage: UIImage?

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
                ZStack {
                    if let composedImage {
                        Image(uiImage: composedImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    } else {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.fill.tertiary)
                            .frame(maxWidth: .infinity)
                            .aspectRatio(0.5625, contentMode: .fit)
                            .overlay { ProgressView() }
                    }
                }
                .frame(maxHeight: 420)

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

                ShareLink(
                    item: Image(uiImage: composedImage ?? UIImage()),
                    preview: SharePreview("My Larping activity", image: Image(uiImage: composedImage ?? UIImage()))
                ) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(colorScheme == .dark ? .black : .white)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(composedImage == nil)

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
            .onAppear { recompose() }
            .onChange(of: photo) { recompose() }
            .onChange(of: photoPickerItem) {
                Task { await loadPickedPhoto() }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraCaptureView { photo = $0 }
                    .ignoresSafeArea()
            }
        }
    }

    private func recompose() {
        composedImage = ShareImageComposer.compose(
            photo: photo,
            coordinates: coordinates,
            stats: stats
        )
    }

    private func loadPickedPhoto() async {
        guard let photoPickerItem,
              let data = try? await photoPickerItem.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        photo = image
    }
}