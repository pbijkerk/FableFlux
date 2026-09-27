import SwiftUI
import SwiftData

struct FolderManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FeedFolder.sortOrder) private var folders: [FeedFolder]

    @State private var showAddAlert = false
    @State private var newFolderName = ""
    @State private var folderToRename: FeedFolder?
    @State private var renameText = ""
    @State private var folderToDelete: FeedFolder?
    @State private var showDeleteConfirm = false
    @State private var editMode: EditMode = .inactive
    @State private var opslagFout: OpslagFoutmelding?

    var body: some View {
        NavigationStack {
            List {
                ForEach(folders) { folder in
                    FolderRowView(
                        folder: folder,
                        onRename: {
                            renameText = folder.name
                            folderToRename = folder
                        },
                        onDelete: {
                            folderToDelete = folder
                            showDeleteConfirm = true
                        }
                    )
                }
                .onMove(perform: moveFolders)
            }
            .environment(\.editMode, $editMode)
            .navigationTitle("Folders beheren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Gereed") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        Button {
                            withAnimation { editMode = editMode == .active ? .inactive : .active }
                        } label: {
                            Text(editMode == .active ? "Stop" : "Volgorde")
                                .font(.subheadline)
                        }
                        Button("Toevoegen", systemImage: "plus") {
                            newFolderName = ""
                            showAddAlert = true
                        }
                    }
                }
            }
            .alert("Nieuwe folder", isPresented: $showAddAlert) {
                TextField("Naam", text: $newFolderName)
                Button("Toevoegen") { addFolder() }
                    .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Annuleren", role: .cancel) {}
            } message: {
                Text("Geef de folder een naam.")
            }
            .alert(
                "Hernoemen",
                isPresented: Binding(
                    get: { folderToRename != nil },
                    set: { if !$0 { folderToRename = nil } }
                )
            ) {
                TextField("Naam", text: $renameText)
                Button("Opslaan") { applyRename() }
                Button("Annuleren", role: .cancel) { folderToRename = nil }
            } message: {
                Text("Nieuwe naam voor \"\(folderToRename?.name ?? "")\".")
            }
            .alert("Folder verwijderen", isPresented: $showDeleteConfirm, presenting: folderToDelete) { folder in
                Button("Verwijderen", role: .destructive) { deleteFolder(folder) }
                Button("Annuleren", role: .cancel) {}
            } message: { folder in
                let feedCount = folder.feeds.count
                if feedCount > 0 {
                    Text("Verwijder \"\(folder.name)\"? De \(feedCount) feed(s) worden verplaatst naar Overig.")
                } else {
                    Text("Verwijder de lege folder \"\(folder.name)\"?")
                }
            }
            .opslagFoutmelding($opslagFout)
        }
    }

    private func moveFolders(from source: IndexSet, to destination: Int) {
        var reordered = folders
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, folder) in reordered.enumerated() {
            folder.sortOrder = index
        }
        modelContext.saveOrReport("de volgorde van de folders te bewaren", melding: &opslagFout)
    }

    private func addFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let maxOrder = folders.map(\.sortOrder).max() ?? -1
        let folder = FeedFolder(name: name, sortOrder: maxOrder + 1, isSystem: false)
        modelContext.insert(folder)
        modelContext.saveOrReport("de folder toe te voegen", melding: &opslagFout)
    }

    private func applyRename() {
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            folderToRename?.name = name
            modelContext.saveOrReport("de folder te hernoemen", melding: &opslagFout)
        }
        folderToRename = nil
    }

    private func deleteFolder(_ folder: FeedFolder) {
        // deleteRule: .nullify handles setting feed.folder = nil automatically
        modelContext.delete(folder)
        modelContext.saveOrReport("de folder te verwijderen", melding: &opslagFout)
    }
}

struct FolderRowView: View {
    let folder: FeedFolder
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: folder.icon)
                .foregroundStyle(.blue)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.name)
                    .font(.body)
                Text("\(folder.feeds.count) feed\(folder.feeds.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if folder.isSystem {
                Label("Systeem", systemImage: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .labelStyle(.iconOnly)
            }
        }
        .swipeActions(edge: .trailing) {
            if !folder.isSystem {
                Button(role: .destructive, action: onDelete) {
                    Label("Verwijderen", systemImage: "trash")
                }
                Button(action: onRename) {
                    Label("Hernoemen", systemImage: "pencil")
                }
                .tint(.orange)
            }
        }
        .contextMenu {
            if !folder.isSystem {
                Button("Hernoemen", systemImage: "pencil", action: onRename)
                Button("Verwijderen", systemImage: "trash", role: .destructive, action: onDelete)
            }
        }
    }
}
