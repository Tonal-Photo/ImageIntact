//
//  ManagePresetsSheet.swift
//  ImageIntact
//
//  Sheet for managing backup presets - create, edit, delete, reorder
//

import SwiftUI
import UniformTypeIdentifiers

struct ManagePresetsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var presetManager = BackupPresetManager.shared
    
    @State private var editingPreset: BackupPreset?
    @State private var renamingPreset: BackupPreset?
    @State private var newPresetName = ""
    @State private var showingImporter = false
    @State private var showingExporter = false
    @State private var exportingPreset: BackupPreset?
    @State private var showingDeleteConfirmation = false
    @State private var presetToDelete: BackupPreset?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Manage Presets")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            
            Divider()
            
            // Preset List
            List {
                // Built-in Presets Section
                Section("Built-in Presets") {
                    ForEach(presetManager.presets.filter { $0.isBuiltIn }) { preset in
                        PresetRow(
                            preset: preset,
                            isSelected: presetManager.selectedPreset?.id == preset.id,
                            onSelect: { selectPreset(preset) },
                            onDuplicate: { duplicatePreset(preset) },
                            onExport: { exportPreset(preset) }
                        )
                    }
                }
                
                // Custom Presets Section
                if !customPresets.isEmpty {
                    Section("Custom Presets") {
                        ForEach(customPresets) { preset in
                            PresetRow(
                                preset: preset,
                                isSelected: presetManager.selectedPreset?.id == preset.id,
                                isRenaming: renamingPreset?.id == preset.id,
                                renameName: $newPresetName,
                                onSelect: { selectPreset(preset) },
                                onRename: { startRenaming(preset) },
                                onCommitRename: { commitRename() },
                                onDuplicate: { duplicatePreset(preset) },
                                onExport: { exportPreset(preset) },
                                onDelete: { confirmDelete(preset) }
                            )
                        }
                        .onMove(perform: moveCustomPresets)
                        .onDelete(perform: deleteCustomPresets)
                    }
                }
            }
            .listStyle(InsetListStyle())
            
            Divider()
            
            // Bottom Toolbar
            HStack {
                // Import button
                Button(action: { showingImporter = true }) {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                
                Spacer()
                
                // Preset count
                Text("\(customPresets.count) custom preset\(customPresets.count == 1 ? "" : "s")")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .padding()
        }
        .frame(width: 600, height: 500)
        .alert("Delete Preset", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let preset = presetToDelete {
                    deletePreset(preset)
                }
            }
        } message: {
            if let preset = presetToDelete {
                Text("Are you sure you want to delete \"\(preset.name)\"? This action cannot be undone.")
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: PresetDocument(preset: exportingPreset),
            contentType: .json,
            defaultFilename: "\(exportingPreset?.name ?? "preset").json"
        ) { result in
            handleExportResult(result)
        }
    }
    
    private var customPresets: [BackupPreset] {
        presetManager.presets.filter { !$0.isBuiltIn }
    }
    
    private func selectPreset(_ preset: BackupPreset) {
        presetManager.selectedPreset = preset
    }
    
    private func startRenaming(_ preset: BackupPreset) {
        renamingPreset = preset
        newPresetName = preset.name
    }
    
    private func commitRename() {
        guard let preset = renamingPreset else { return }
        
        if presetManager.renamePreset(preset, to: newPresetName) {
            renamingPreset = nil
            newPresetName = ""
        }
    }
    
    private func duplicatePreset(_ preset: BackupPreset) {
        _ = presetManager.duplicatePreset(preset)
    }
    
    private func confirmDelete(_ preset: BackupPreset) {
        presetToDelete = preset
        showingDeleteConfirmation = true
    }
    
    private func deletePreset(_ preset: BackupPreset) {
        presetManager.deletePreset(preset)
        presetToDelete = nil
    }
    
    private func deleteCustomPresets(at offsets: IndexSet) {
        for index in offsets {
            if index < customPresets.count {
                deletePreset(customPresets[index])
            }
        }
    }
    
    private func moveCustomPresets(from source: IndexSet, to destination: Int) {
        // Calculate actual indices in the full preset array
        let builtInCount = presetManager.presets.filter { $0.isBuiltIn }.count
        
        for index in source {
            let sourceIndex = builtInCount + index
            let destIndex = builtInCount + (destination > index ? destination - 1 : destination)
            presetManager.movePreset(from: sourceIndex, to: destIndex)
        }
    }
    
    private func exportPreset(_ preset: BackupPreset) {
        exportingPreset = preset
        showingExporter = true
    }
    
    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }
            
            let data = try Data(contentsOf: url)
            _ = try presetManager.importPreset(from: data)
        } catch {
            ApplicationLogger.shared.error("Failed to import preset: \(error)", category: .app)
        }
    }
    
    private func handleExportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            ApplicationLogger.shared.info("Exported preset to: \(url.lastPathComponent)", category: .app)
        case .failure(let error):
            ApplicationLogger.shared.error("Failed to export preset: \(error)", category: .app)
        }
    }
}

// MARK: - Preset Row View

struct PresetRow: View {
    let preset: BackupPreset
    var isSelected: Bool = false
    var isRenaming: Bool = false
    @Binding var renameName: String
    
    var onSelect: () -> Void = {}
    var onRename: () -> Void = {}
    var onCommitRename: () -> Void = {}
    var onDuplicate: () -> Void = {}
    var onExport: () -> Void = {}
    var onDelete: (() -> Void)?
    
    init(preset: BackupPreset,
         isSelected: Bool = false,
         isRenaming: Bool = false,
         renameName: Binding<String> = .constant(""),
         onSelect: @escaping () -> Void = {},
         onRename: @escaping () -> Void = {},
         onCommitRename: @escaping () -> Void = {},
         onDuplicate: @escaping () -> Void = {},
         onExport: @escaping () -> Void = {},
         onDelete: (() -> Void)? = nil) {
        self.preset = preset
        self.isSelected = isSelected
        self.isRenaming = isRenaming
        self._renameName = renameName
        self.onSelect = onSelect
        self.onRename = onRename
        self.onCommitRename = onCommitRename
        self.onDuplicate = onDuplicate
        self.onExport = onExport
        self.onDelete = onDelete
    }
    
    var body: some View {
        HStack {
            // Icon
            Image(systemName: preset.icon)
                .foregroundColor(isSelected ? .accentColor : .secondary)
                .frame(width: 20)
            
            // Name (editable for custom presets)
            if isRenaming {
                TextField("Preset Name", text: $renameName, onCommit: onCommitRename)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(maxWidth: 200)
            } else {
                Text(preset.name)
                    .fontWeight(isSelected ? .medium : .regular)
                
                if preset.isBuiltIn {
                    Text("Built-in")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                }
            }
            
            Spacer()
            
            // Action buttons
            HStack(spacing: 8) {
                // Use count
                if preset.useCount > 0 {
                    Text("\(preset.useCount)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Duplicate button
                Button(action: onDuplicate) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(BorderlessButtonStyle())
                .help("Duplicate preset")
                
                // Export button
                Button(action: onExport) {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(BorderlessButtonStyle())
                .help("Export preset")
                
                // Rename button (custom presets only)
                if !preset.isBuiltIn {
                    Button(action: onRename) {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .help("Rename preset")
                }
                
                // Delete button (custom presets only)
                if !preset.isBuiltIn, let onDelete = onDelete {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .help("Delete preset")
                }
            }
            .opacity(isSelected ? 1.0 : 0.7)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isRenaming {
                onSelect()
            }
        }
    }
}

// MARK: - Preset Document for Export

struct PresetDocument: FileDocument {
    nonisolated static var readableContentTypes: [UTType] { [.json] }
    
    let preset: BackupPreset?
    
    init(preset: BackupPreset?) {
        self.preset = preset
    }
    
    nonisolated init(configuration: ReadConfiguration) throws {
        preset = nil
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let preset = preset else {
            throw CocoaError(.fileWriteUnknown)
        }
        
        // Export the preset as JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(preset)
        return FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Preview

struct ManagePresetsSheet_Previews: PreviewProvider {
    static var previews: some View {
        ManagePresetsSheet()
    }
}