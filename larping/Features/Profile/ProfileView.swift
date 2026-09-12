import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ActivitiesStore.self) private var activitiesStore
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system
    @AppStorage("displayName") private var displayName = "Larping User"
    @AppStorage("bio") private var bio = "Chasing routes, one recording at a time."
    @State private var showEdit = false
    @State private var exportDocument: BackupFile?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var pendingImportURL: URL?
    @State private var confirmImport = false
    @State private var backupMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ZStack(alignment: .bottomLeading) {
                        LinearGradient(
                            colors: [Color.accentColor, .black],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(maxWidth: .infinity)
                        .clipped()

                        // Readability scrim: darkens the whole cover (not just
                        // the bottom) so a bright accent-gradient fallback never
                        // reads as raw lime/blue, while staying darkest at the
                        // bottom for the info block.
                        LinearGradient(
                            colors: [.black.opacity(0.32), .black.opacity(0.45), .black.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )

                        VStack(spacing: 6) {
                            Spacer(minLength: 0)

                            Image(systemName: "figure.run.circle.fill")
                                .font(.system(size: 46))
                                .foregroundStyle(.white)
                            Text(displayName)
                                .font(.headline.bold())
                                .foregroundStyle(.white)
                            if !bio.isEmpty {
                                Text(bio)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.9))
                                    .multilineTextAlignment(.center)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 14)
                        .padding(.top, 14)

                        Image("LogoHorizontal")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 14)
                            .foregroundStyle(.white)
                            .padding(15)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
                    .frame(height: 170)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                Section {
                    Button("Edit profile") {
                        showEdit = true
                    }
                }

                Section("Appearance") {
                    HStack(spacing: 6) {
                        ForEach(AppearanceMode.allCases) { mode in
                            let isSelected = appearanceMode == mode
                            Button {
                                appearanceMode = mode
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: mode.symbolName)
                                        .font(.system(size: 13, weight: .semibold))
                                    Text(mode.label)
                                        .font(.footnote.weight(.medium))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    isSelected ? Color.accentColor : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                                .foregroundStyle(
                                    isSelected
                                        ? (colorScheme == .dark ? Color.black : Color.white)
                                        : Color.secondary
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(4)
                    .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                }

                Section("Backup") {
                    Button {
                        exportBackup()
                    } label: {
                        Label("Export all activities", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        showImporter = true
                    } label: {
                        Label("Import backup", systemImage: "square.and.arrow.down")
                    }
                    Label("Export a backup JSON and save it to iCloud Drive or Files to keep your data safe across devices and reinstalls.", systemImage: "icloud")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Text("Larping v\(appVersion) (\(appBuild))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
                .listRowBackground(Color.clear)
            }
            .navigationTitle("Profile")
            .sheet(isPresented: $showEdit) {
                EditProfileView(displayName: displayName, bio: bio) { name, newBio in
                    displayName = name
                    bio = newBio
                }
            }
            .fileExporter(
                isPresented: $showExporter,
                document: exportDocument,
                contentType: .json,
                defaultFilename: backupFilename
            ) { result in
                switch result {
                case .success:
                    backupMessage = nil
                case .failure(let error):
                    backupMessage = error.localizedDescription
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    pendingImportURL = url
                    confirmImport = true
                case .failure:
                    break
                }
            }
            .confirmationDialog("Import backup?", isPresented: $confirmImport, titleVisibility: .visible) {
                Button("Import") { performImport() }
                Button("Cancel", role: .cancel) { pendingImportURL = nil }
            } message: {
                Text("Only new activities will be added. Nothing existing is overwritten or deleted.")
            }
            .alert(isPresented: Binding(
                get: { backupMessage != nil },
                set: { if !$0 { backupMessage = nil } }
            )) {
                Alert(
                    title: Text(backupMessage?.contains("imported") == true ? "Import" : "Backup"),
                    message: Text(backupMessage ?? ""),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private var backupFilename: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "larping-backup-\(formatter.string(from: Date()))"
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    private func exportBackup() {
        backupMessage = nil
        do {
            exportDocument = try BackupService.backupFile(from: modelContext)
            showExporter = true
        } catch {
            backupMessage = error.localizedDescription
        }
    }

    private func performImport() {
        defer { pendingImportURL = nil }
        guard let pendingImportURL else { return }
        guard pendingImportURL.startAccessingSecurityScopedResource() else {
            backupMessage = "Couldn't access the selected file."
            return
        }
        defer { pendingImportURL.stopAccessingSecurityScopedResource() }
        do {
            let data = try Data(contentsOf: pendingImportURL)
            let (imported, skipped) = try BackupService.restore(from: data, into: modelContext)
            activitiesStore.refresh()
            backupMessage = skipped > 0
                ? "Imported \(imported) activities. Skipped \(skipped) already present."
                : imported == 1 ? "Imported 1 activity." : "Imported \(imported) activities."
        } catch {
            backupMessage = error.localizedDescription
        }
    }
}

private struct EditProfileView: View {
    let displayName: String
    let bio: String
    let onSaved: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var bioText: String

    init(displayName: String, bio: String, onSaved: @escaping (String, String) -> Void) {
        self.displayName = displayName
        self.bio = bio
        self.onSaved = onSaved
        _name = State(initialValue: displayName)
        _bioText = State(initialValue: bio)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    TextField("Display name", text: $name)
                    TextField("Bio", text: $bioText, axis: .vertical)
                }
            }
            .navigationTitle("Edit profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSaved(name, bioText)
                        dismiss()
                    }
                }
            }
        }
    }
}