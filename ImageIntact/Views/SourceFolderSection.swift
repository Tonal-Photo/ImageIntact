import SwiftUI

struct SourceFolderSection: View {
    @Bindable var backupManager: BackupManager
    @FocusState.Binding var focusedField: ContentView.FocusField?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Source", systemImage: "folder")
                .font(.headline)
                .foregroundColor(.primary)
            
            // Inner content - indented
            VStack(alignment: .leading, spacing: 12) {
                // Backup configuration (presets and filters) - always show for custom presets
                // Only hide during scanning
                if !backupManager.isScanning {
                    BackupConfigurationView(backupManager: backupManager)
                }
                
                FolderRow(
                    title: "Select Source Folder",
                    selectedURL: Binding(
                        get: { backupManager.sourceURL },
                        set: { newValue in
                            if let url = newValue {
                                backupManager.setSource(url)
                            }
                        }
                    ),
                    onClear: {
                        backupManager.sourceURL = nil
                        backupManager.sourceFileTypes = [:]
                        backupManager.scanProgress = ""
                        UserDefaults.standard.removeObject(forKey: backupManager.sourceKey)
                    },
                    onSelect: { url in
                        // Already handled in backupManager.setSource()
                    }
                )
                .focused($focusedField, equals: .source)
                .onTapGesture {
                    focusedField = .source
                }
                
                // File type summary and filter results - indented further
                if backupManager.sourceURL != nil {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            // File type summary - what was found
                            HStack(spacing: 4) {
                            if backupManager.isScanning {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(width: 14, height: 14)
                            } else if !backupManager.sourceFileTypes.isEmpty {
                                Image(systemName: "photo.stack")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Text(backupManager.getFormattedFileTypeSummary())
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        .animation(.easeInOut(duration: 0.2), value: backupManager.isScanning)
                        
                        // Show what will be copied if filter is active
                        if !backupManager.sourceFileTypes.isEmpty && !backupManager.isScanning {
                            if let filterInfo = backupManager.getFilteredFilesSummary(),
                               !backupManager.fileTypeFilter.includedExtensions.isEmpty {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.right.circle.fill")
                                        .font(.caption)
                                        .foregroundColor(.accentColor)
                                    
                                    Text("\(filterInfo.willCopy) of \(filterInfo.total) files will be backed up")
                                        .font(.caption)
                                        .foregroundColor(.accentColor)
                                    
                                    if !filterInfo.summary.isEmpty && filterInfo.willCopy > 0 {
                                        Text("• \(filterInfo.summary)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.accentColor.opacity(0.1))
                                )
                            }
                        }
                        }
                        
                        Spacer()
                        
                        // Save as Preset button - only show if we have valid configuration
                        let hasValidConfiguration = backupManager.sourceURL != nil && 
                            backupManager.destinationItems.contains { $0.url != nil }
                        let isDuplicatePreset = BackupPresetManager.shared.currentConfigurationMatchesExistingPreset(backupManager: backupManager)
                        
                        if hasValidConfiguration && !backupManager.isScanning {
                            Button(action: {
                                // We need to trigger the CreatePresetSheet
                                // For now, we'll use NotificationCenter to communicate with BackupConfigurationView
                                NotificationCenter.default.post(name: NSNotification.Name("ShowCreatePreset"), object: nil)
                            }) {
                                Text("Save as Preset")
                                    .font(.caption)
                                    .foregroundColor(isDuplicatePreset ? .secondary : .accentColor)
                            }
                            .buttonStyle(.plain)
                            .disabled(isDuplicatePreset)
                            .help(isDuplicatePreset ? "This configuration already exists as a preset" : "Save current configuration as a preset")
                        }
                    }
                    .padding(.leading, 20)
                    .padding(.trailing, 20)
                }
            }
            .padding(.leading, 20)
        }
        .padding(.horizontal, 20)
    }
}