import SwiftUI

struct MultiDestinationProgressSection: View {
    @Bindable var backupManager: BackupManager
    @ObservedObject var progressPublisher = ProgressPublisher.shared
    @State private var networkDestinations: Set<String> = []
    
    private var destinations: [URL] {
        backupManager.destinationURLs.compactMap { $0 }
    }
    
    private func phaseDescription(for phase: BackupPhase) -> String {
        switch phase {
        case .idle: return "Idle"
        case .analyzingSource: return "Analyzing source files"
        case .buildingManifest: return "Building manifest (calculating checksums)"
        case .copyingFiles: return "Copying files"
        case .flushingToDisk: return "Flushing to disk"
        case .verifyingDestinations: return "Verifying checksums"
        case .complete: return "Complete"
        }
    }
    
    private func checkForNetworkDrives() -> String? {
        guard !networkDestinations.isEmpty else { return nil }
        
        let count = networkDestinations.count
        if count == 1 {
            return "Network drive detected - operations may take longer"
        } else {
            return "\(count) network drives detected - operations may take longer"
        }
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // Main backup progress
            if !progressPublisher.statusMessage.isEmpty || progressPublisher.isBackupRunning {
                VStack(alignment: .leading, spacing: 12) {
                Divider()
                    .padding(.horizontal, 20)

                if progressPublisher.isBackupRunning && progressPublisher.totalFiles > 0 &&
                   progressPublisher.currentPhase != .analyzingSource &&
                   progressPublisher.currentPhase != .buildingManifest {
                    // Show different UI based on destination count
                    if destinations.count <= 1 {
                        // Single destination - show simple progress
                        SimpleBackupProgress(backupManager: backupManager)
                    } else {
                        // Multiple destinations - show per-destination progress
                        MultiDestinationProgress(backupManager: backupManager, destinations: destinations)
                    }
                } else if progressPublisher.isBackupRunning {
                    // Preparing or simple status with phase indicator
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            if progressPublisher.isBackupRunning {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                    .scaleEffect(0.8)
                            }

                            Text(progressPublisher.statusMessage)
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            // Add cancel button during preparation phases too
                            if progressPublisher.isBackupRunning {
                                Button(action: {
                                    backupManager.cancelOperation()
                                }) {
                                    Label("Cancel", systemImage: "stop.circle.fill")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .help("Cancel operation")
                            }
                        }
                        
                        // Add network drive warning if applicable
                        if progressPublisher.isBackupRunning &&
                           (progressPublisher.statusMessage.contains("Checking") ||
                            progressPublisher.statusMessage.contains("checksum") ||
                            progressPublisher.currentPhase == .buildingManifest) {
                            if let networkDrives = checkForNetworkDrives() {
                                Label(networkDrives, systemImage: "network")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                    .padding(.top, 4)
                            }
                        }
                        
                        // Show phase progress if in phase-based backup
                        if progressPublisher.isBackupRunning {
                            HStack(spacing: 4) {
                                PhaseIndicator(label: "Analyze", isActive: progressPublisher.currentPhase == .analyzingSource,
                                             isComplete: progressPublisher.currentPhase.rawValue > BackupPhase.analyzingSource.rawValue)
                                PhaseIndicator(label: "Manifest", isActive: progressPublisher.currentPhase == .buildingManifest,
                                             isComplete: progressPublisher.currentPhase.rawValue > BackupPhase.buildingManifest.rawValue)
                                PhaseIndicator(label: "Copy", isActive: progressPublisher.currentPhase == .copyingFiles,
                                             isComplete: progressPublisher.currentPhase.rawValue > BackupPhase.copyingFiles.rawValue)
                                PhaseIndicator(label: "Flush", isActive: progressPublisher.currentPhase == .flushingToDisk,
                                             isComplete: progressPublisher.currentPhase.rawValue > BackupPhase.flushingToDisk.rawValue)
                                PhaseIndicator(label: "Verify", isActive: progressPublisher.currentPhase == .verifyingDestinations,
                                             isComplete: progressPublisher.currentPhase.rawValue > BackupPhase.verifyingDestinations.rawValue)
                            }
                            .font(.caption2)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                }
                .transition(.opacity)
                .task {
                    await checkDriveTypes()
                }
                .onChange(of: destinations) { _, _ in
                    Task {
                        await checkDriveTypes()
                    }
                }
            }

            // Network Operation Status - show when retrying network operations
            if progressPublisher.networkOperationInProgress && !progressPublisher.networkOperationMessage.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                        .padding(.horizontal, 20)

                    HStack {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(0.7)

                        Image(systemName: "network")
                            .foregroundColor(.orange)

                        Text(progressPublisher.networkOperationMessage)
                            .font(.caption)
                            .foregroundColor(.orange)

                        if progressPublisher.networkRetryAttempt > 0 {
                            Spacer()
                            Text("Attempt \(progressPublisher.networkRetryAttempt)/\(progressPublisher.networkRetryMaxAttempts)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal, 20)
                .transition(.opacity)
            }

            // Vision Analysis Progress - show when analyzing
            if progressPublisher.isAnalyzing && progressPublisher.totalImagesToAnalyze > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                        .padding(.horizontal, 20)

                    HStack {
                        Image(systemName: "eye.circle")
                            .foregroundColor(.blue)
                        Text("Vision & Core Image Analysis")
                            .font(.subheadline)
                            .foregroundColor(.primary)

                        Spacer()

                        Text("\(progressPublisher.analyzedImages)/\(progressPublisher.totalImagesToAnalyze) images")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 20)

                    ProgressView(value: Double(progressPublisher.analyzedImages) / Double(progressPublisher.totalImagesToAnalyze))
                        .progressViewStyle(.linear)
                        .padding(.horizontal, 20)

                    Text("Analyzing images for objects, scenes, faces, colors, and quality...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 20)
                }
                .padding(.vertical, 12)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .padding(.horizontal, 20)
                .transition(.opacity)
            }
        }
    }
    
    private func checkDriveTypes() async {
        networkDestinations.removeAll()
        
        for destination in destinations {
            if let driveInfo = DriveAnalyzer.analyzeDrive(at: destination),
               driveInfo.connectionType == .network {
                networkDestinations.insert(destination.lastPathComponent)
            }
        }
    }
}

struct SimpleBackupProgress: View {
    @Bindable var backupManager: BackupManager
    @ObservedObject var progressPublisher = ProgressPublisher.shared
    
    private func formatDataProgress() -> String {
        let copiedMB = Double(backupManager.totalBytesCopied) / (1024 * 1024)
        let totalMB = Double(backupManager.totalBytesToCopy) / (1024 * 1024)
        
        if totalMB > 1024 {
            // Show in GB if over 1GB
            let copiedGB = copiedMB / 1024
            let totalGB = totalMB / 1024
            return String(format: "%.1f/%.1f GB", copiedGB, totalGB)
        } else {
            return String(format: "%.0f/%.0f MB", copiedMB, totalMB)
        }
    }
    
    private func phaseDescription(for phase: BackupPhase) -> String {
        switch phase {
        case .idle: return "Idle"
        case .analyzingSource: return "Analyzing source files"
        case .buildingManifest: return "Building manifest (calculating checksums)"
        case .copyingFiles: return "Copying files"
        case .flushingToDisk: return "Flushing to disk"
        case .verifyingDestinations: return "Verifying checksums"
        case .complete: return "Complete"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Backup Progress")
                    .font(.headline)
                
                Spacer()
                
                Button(action: {
                    backupManager.cancelOperation()
                }) {
                    Label("Cancel", systemImage: "stop.circle.fill")
                        .foregroundColor(.red)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Cancel backup")
            }
            
            VStack(alignment: .leading, spacing: 8) {
                // Show current phase
                Text("Phase: \(phaseDescription(for: backupManager.currentPhase))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    // Show appropriate counter based on phase
                    if backupManager.currentPhase == .verifyingDestinations {
                        Text("Verifying: \(backupManager.progressTracker.verifiedFiles)/\(backupManager.totalFiles)")
                            .font(.subheadline)
                    } else {
                        Text("Files: \(backupManager.processedFiles)/\(backupManager.totalFiles)")
                            .font(.subheadline)
                    }
                    
                    Spacer()
                    
                    // Data processed display
                    if backupManager.totalBytesCopied > 0 {
                        let processedMB = Double(backupManager.totalBytesCopied) / (1024 * 1024)
                        Text(String(format: "%.1f MB/s", backupManager.copySpeed > 0 ? backupManager.copySpeed : processedMB / max(1, Date().timeIntervalSince(backupManager.progressTracker.copyStartTime))))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                    
                    // ETA display
                    let eta = backupManager.formattedETA()
                    if !eta.isEmpty && eta != "Calculating..." {
                        Text("• \(eta)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Overall progress across all phases
                HStack(spacing: 8) {
                    ProgressView(value: progressPublisher.overallProgress)
                        .progressViewStyle(.linear)
                    
                    // Data progress indicator
                    if backupManager.totalBytesToCopy > 0 {
                        Text(formatDataProgress())
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                }
                
                HStack {
                    if !backupManager.currentFileName.isEmpty {
                        Text("Current: \(backupManager.currentFileName)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    
                    Spacer()
                    
                    if !backupManager.currentDestinationName.isEmpty {
                        Text("→ \(backupManager.currentDestinationName)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .padding(.horizontal, 20)
    }
}

struct MultiDestinationProgress: View {
    @Bindable var backupManager: BackupManager
    @ObservedObject var progressPublisher = ProgressPublisher.shared
    let destinations: [URL]
    @State private var networkDrives: Set<String> = []
    
    private func phaseDescription(for phase: BackupPhase) -> String {
        switch phase {
        case .idle: return "Idle"
        case .analyzingSource: return "Analyzing source files"
        case .buildingManifest: return "Building manifest (calculating checksums)"
        case .copyingFiles: return "Copying files"
        case .flushingToDisk: return "Flushing to disk"
        case .verifyingDestinations: return "Verifying checksums"
        case .complete: return "Complete"
        }
    }
    
    private func checkDriveTypes() async {
        networkDrives.removeAll()

        for destination in destinations {
            if let driveInfo = DriveAnalyzer.analyzeDrive(at: destination),
               driveInfo.connectionType == .network {
                networkDrives.insert(destination.lastPathComponent)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Backup Progress")
                    .font(.headline)
                
                Spacer()
                
                // Show aggregate progress
                if progressPublisher.overallProgress > 0 {
                    Text("\(Int(progressPublisher.overallProgress * 100))% Complete")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Button(action: {
                    backupManager.cancelOperation()
                }) {
                    Label("Cancel", systemImage: "stop.circle.fill")
                        .foregroundColor(.red)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Cancel backup")
            }
            
            // Overall progress bar (shows total progress across all phases)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Overall Progress")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    if !backupManager.overallStatusText.isEmpty {
                        Text(backupManager.overallStatusText)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else if backupManager.currentPhase == .buildingManifest {
                        Text("Building manifest...")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else if backupManager.currentPhase == .complete {
                        Text("Complete")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                }
                ProgressView(value: progressPublisher.overallProgress)
                    .progressViewStyle(.linear)
            }
            
            // Per-destination progress
            if backupManager.currentPhase == .buildingManifest {
                // During manifest building, show a single progress for all destinations
                VStack(alignment: .leading, spacing: 4) {
                    Text("Building source manifest for all destinations...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ProgressView(value: backupManager.phaseProgress)
                        .progressViewStyle(.linear)
                }
            }
            
            // Current file info
            if !backupManager.currentFileName.isEmpty {
                HStack {
                    Text("Current: \(backupManager.currentFileName)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    Spacer()
                    
                    if !backupManager.currentDestinationName.isEmpty {
                        Text("→ \(backupManager.currentDestinationName)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .padding(.horizontal, 20)
        .task {
            await checkDriveTypes()
        }
        .onChange(of: destinations) { _, _ in
            Task {
                await checkDriveTypes()
            }
        }
    }
}

struct DestinationProgressRow: View {
    let destinationName: String
    let completedFiles: Int
    let totalFiles: Int
    let isActive: Bool
    var phase: BackupPhase = .copyingFiles
    var state: String = "copying"
    var isNetworkDrive: Bool = false
    var isVerifying: Bool = false
    var verifiedCount: Int = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                HStack(spacing: 4) {
                    if isNetworkDrive {
                        Image(systemName: "network")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    Text(destinationName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                Spacer()
                
                if state == "complete" {
                    Text("Complete ✓")
                        .font(.caption)
                        .foregroundColor(.green)
                } else if state == "verifying" {
                    Text("Verifying...")
                        .font(.caption)
                        .foregroundColor(.orange)
                } else if state == "copying" {
                    Text("Copying...")
                        .font(.caption)
                        .foregroundColor(.blue)
                } else {
                    Text("\(completedFiles)/\(totalFiles)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Activity indicator - show green for active, blue for complete
                Circle()
                    .fill(state == "complete" ? Color.green : (isActive ? Color.blue : Color.clear))
                    .frame(width: 8, height: 8)
            }
            
            ProgressView(value: Double(completedFiles), total: Double(totalFiles))
                .progressViewStyle(.linear)
                .scaleEffect(x: 1, y: 0.6) // Make it a bit thinner
        }
        .padding(.vertical, 4)
    }
}

struct PhaseIndicator: View {
    let label: String
    let isActive: Bool
    var isComplete: Bool = false
    
    var body: some View {
        HStack(spacing: 2) {
            if isComplete {
                Image(systemName: "checkmark.circle.fill")
                    .imageScale(.small)
                    .foregroundColor(.green)
            }
            Text(label)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isActive ? Color.accentColor : (isComplete ? Color.green.opacity(0.2) : Color.gray.opacity(0.2)))
        )
        .foregroundColor(isActive ? .white : (isComplete ? .green : .secondary))
    }
}