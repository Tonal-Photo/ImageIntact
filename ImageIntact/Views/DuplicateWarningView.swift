//
//  DuplicateWarningView.swift
//  ImageIntact
//
//  Shows duplicate file analysis and allows user to choose action
//

import SwiftUI

struct DuplicateWarningView: View {
    let analyses: [URL: DuplicateDetector.DuplicateAnalysis]
    let onProceed: (Bool, Bool) -> Void  // (skipExact, skipRenamed)
    let onCancel: () -> Void
    
    @State private var skipExactDuplicates = true
    @State private var skipRenamedDuplicates = false
    @State private var showingDetails = false
    @State private var selectedDestination: URL?
    
    // Calculate totals across all destinations
    private var totalExactDuplicates: Int {
        analyses.values.reduce(0) { $0 + $1.exactDuplicates.count }
    }
    
    private var totalRenamedDuplicates: Int {
        analyses.values.reduce(0) { $0 + $1.renamedDuplicates.count }
    }
    
    private var totalSpaceSaved: Int64 {
        var saved: Int64 = 0
        if skipExactDuplicates {
            saved += analyses.values.reduce(0) { sum, analysis in
                sum + analysis.exactDuplicates.reduce(0) { $0 + $1.sourceFile.size }
            }
        }
        if skipRenamedDuplicates {
            saved += analyses.values.reduce(0) { sum, analysis in
                sum + analysis.renamedDuplicates.reduce(0) { $0 + $1.sourceFile.size }
            }
        }
        return saved
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "doc.on.doc.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.orange)
                
                Text("Duplicate Files Detected")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Some files already exist at the destination(s)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 24)
            .padding(.bottom, 20)
            
            Divider()
            
            // Summary Section
            VStack(spacing: 16) {
                // Duplicate counts
                HStack(spacing: 24) {
                    DuplicateStatView(
                        icon: "equal.circle.fill",
                        title: "Exact Duplicates",
                        count: totalExactDuplicates,
                        color: .blue
                    )
                    
                    DuplicateStatView(
                        icon: "arrow.triangle.2.circlepath.circle.fill",
                        title: "Renamed Files",
                        count: totalRenamedDuplicates,
                        color: .orange
                    )
                }
                
                // Space savings
                if totalSpaceSaved > 0 {
                    HStack {
                        Image(systemName: "internaldrive.fill")
                            .foregroundColor(.green)
                        Text("Potential space saved:")
                            .foregroundColor(.secondary)
                        Text(ByteCountFormatter.string(fromByteCount: totalSpaceSaved, countStyle: .binary))
                            .fontWeight(.medium)
                    }
                    .font(.callout)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            .padding(20)
            
            // Options Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Choose what to do:")
                    .font(.headline)
                
                // Skip exact duplicates option
                Toggle(isOn: $skipExactDuplicates) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Skip exact duplicates")
                            .font(.system(size: 14))
                        Text("Files with same name and content")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(CheckboxToggleStyle())
                
                // Skip renamed duplicates option
                Toggle(isOn: $skipRenamedDuplicates) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Skip renamed duplicates")
                            .font(.system(size: 14))
                        Text("Same content but different names")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(CheckboxToggleStyle())
                
                // View details button
                Button(action: { showingDetails.toggle() }) {
                    HStack {
                        Text("View Details")
                            .font(.system(size: 13))
                        Image(systemName: showingDetails ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11))
                    }
                }
                .buttonStyle(LinkButtonStyle())
                .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            
            // Details Section (collapsible)
            if showingDetails {
                Divider()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(analyses.keys.sorted(by: { $0.path < $1.path })), id: \.self) { destination in
                            if let analysis = analyses[destination] {
                                DestinationDuplicatesView(
                                    destination: destination,
                                    analysis: analysis
                                )
                            }
                        }
                    }
                    .padding(20)
                }
                .frame(maxHeight: 200)
            }
            
            Divider()
            
            // Action Buttons
            HStack(spacing: 12) {
                Button("Cancel Backup") {
                    onCancel()
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button("Copy All Anyway") {
                    onProceed(false, false)
                }
                
                Button("Continue with Selection") {
                    onProceed(skipExactDuplicates, skipRenamedDuplicates)
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(!skipExactDuplicates && !skipRenamedDuplicates)
            }
            .padding(20)
        }
        .frame(width: 600)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Supporting Views

struct DuplicateStatView: View {
    let icon: String
    let title: String
    let count: Int
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(color)
            
            Text("\(count)")
                .font(.title)
                .fontWeight(.semibold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

struct DestinationDuplicatesView: View {
    let destination: URL
    let analysis: DuplicateDetector.DuplicateAnalysis
    
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Destination header
            HStack {
                Image(systemName: "internaldrive.fill")
                    .foregroundColor(.blue)
                
                Text(destination.lastPathComponent)
                    .font(.system(size: 13, weight: .medium))
                
                Spacer()
                
                Text("\(analysis.totalDuplicates) duplicates")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button(action: { isExpanded.toggle() }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            
            // Expanded details
            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    if !analysis.exactDuplicates.isEmpty {
                        Text("Exact duplicates:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 12)
                        
                        ForEach(analysis.exactDuplicates.prefix(5), id: \.checksum) { duplicate in
                            HStack {
                                Image(systemName: "doc.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.blue)
                                
                                Text(duplicate.sourceFile.relativePath.components(separatedBy: "/").last ?? "")
                                    .font(.system(size: 11))
                                    .lineLimit(1)
                                
                                if let org = duplicate.existingOrganization {
                                    Text("in \(org)/")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Text(ByteCountFormatter.string(fromByteCount: duplicate.sourceFile.size, countStyle: .binary))
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 20)
                        }
                        
                        if analysis.exactDuplicates.count > 5 {
                            Text("...and \(analysis.exactDuplicates.count - 5) more")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .italic()
                                .padding(.leading, 20)
                        }
                    }
                    
                    if !analysis.renamedDuplicates.isEmpty {
                        Text("Renamed duplicates:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 12)
                            .padding(.top, 4)
                        
                        ForEach(analysis.renamedDuplicates.prefix(3), id: \.checksum) { duplicate in
                            HStack {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 10))
                                    .foregroundColor(.orange)
                                
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(duplicate.sourceFile.relativePath.components(separatedBy: "/").last ?? "")
                                        .font(.system(size: 11))
                                        .lineLimit(1)
                                    
                                    Text("→ \(URL(fileURLWithPath: duplicate.destinationPath).lastPathComponent)")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Text(ByteCountFormatter.string(fromByteCount: duplicate.sourceFile.size, countStyle: .binary))
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 20)
                        }
                        
                        if analysis.renamedDuplicates.count > 3 {
                            Text("...and \(analysis.renamedDuplicates.count - 3) more")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .italic()
                                .padding(.leading, 20)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

// MARK: - Toggle Style

struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                .foregroundColor(configuration.isOn ? .accentColor : .secondary)
                .onTapGesture {
                    configuration.isOn.toggle()
                }
            
            configuration.label
        }
    }
}

// MARK: - Preview

struct DuplicateWarningView_Previews: PreviewProvider {
    static var previews: some View {
        let testAnalysis = DuplicateDetector.DuplicateAnalysis(
            totalSourceFiles: 100,
            exactDuplicates: [
                DuplicateDetector.DuplicateFile(
                    sourceFile: FileManifestEntry(
                        relativePath: "photo1.jpg",
                        sourceURL: URL(fileURLWithPath: "/source/photo1.jpg"),
                        checksum: "abc123",
                        size: 1024 * 1024 * 5
                    ),
                    destinationPath: "/dest/photo1.jpg",
                    checksum: "abc123",
                    isDifferentName: false,
                    existingOrganization: nil
                )
            ],
            renamedDuplicates: [
                DuplicateDetector.DuplicateFile(
                    sourceFile: FileManifestEntry(
                        relativePath: "photo2.jpg",
                        sourceURL: URL(fileURLWithPath: "/source/photo2.jpg"),
                        checksum: "def456",
                        size: 1024 * 1024 * 3
                    ),
                    destinationPath: "/dest/renamed_photo.jpg",
                    checksum: "def456",
                    isDifferentName: true,
                    existingOrganization: "2024-Photos"
                )
            ],
            uniqueFiles: 75,
            potentialSpaceSaved: 1024 * 1024 * 50,
            destinationDriveUUID: nil
        )
        
        DuplicateWarningView(
            analyses: [
                URL(fileURLWithPath: "/Volumes/BackupDrive"): testAnalysis
            ],
            onProceed: { _, _ in },
            onCancel: { }
        )
        .frame(width: 600)
    }
}