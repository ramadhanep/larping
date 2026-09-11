import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ActivitiesStore.self) private var activitiesStore
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system
    @AppStorage("displayName") private var displayName = "Larping User"
    @AppStorage("bio") private var bio = ""
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
                    VStack(spacing: 8) {
                        Image(systemName: "figure.run.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(.tint)
                        Text(displayName).font(.title2.bold())
                        if !bio.isEmpty {
                            Text(bio).font(.footnote).multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .listRowBackground(Color.clear)
                }

                Section {
                    Button("Edit profile") {
                        showEdit = true
                    }
                }

                Section("Appearance") {
                    Picker("Theme", selection: $appearanceMode) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
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

                Section("About") {
                    Label("Larping", systemImage: "figure.run")
                    Label("actually works", systemImage: "bolt.fill")
                        .foregroundStyle(.secondary)
                }
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