import SwiftUI

struct MultiDestinationProgressSection: View {
  @Bindable var backupManager: BackupManager
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
    if !backupManager.state.statusMessage.isEmpty || backupManager.state.isProcessing {
      VStack(alignment: .leading, spacing: 12) {
        Divider()
          .padding(.horizontal, 20)

        if backupManager.state.isProcessing && backupManager.progressTracker.totalFiles > 0 {
          // Show different UI based on destination count
          if destinations.count <= 1 {
            // Single destination - show simple progress
            SimpleBackupProgress(backupManager: backupManager)
          } else {
            // Multiple destinations - show per-destination progress
            MultiDestinationProgress(backupManager: backupManager, destinations: destinations)
          }
        } else {
          // Preparing or simple status with phase indicator
          VStack(alignment: .leading, spacing: 8) {
            HStack {
              if backupManager.state.isProcessing {
                ProgressView()
                  .progressViewStyle(CircularProgressViewStyle())
                  .scaleEffect(0.8)
              }

              Text(backupManager.state.statusMessage)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)

              Spacer()

              // Add cancel button during preparation phases too
              if backupManager.state.isProcessing {
                Button(action: {
                  backupManager.cancelOperation()
                }) {
                  Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .imageScale(.large)
                }
                .buttonStyle(.plain)
                .help("Cancel operation")
              }
            }

            // Add network drive warning if applicable
            if backupManager.state.isProcessing
              && (backupManager.state.statusMessage.contains("Checking")
                || backupManager.state.statusMessage.contains("checksum")
                || backupManager.state.currentPhase == .buildingManifest)
            {
              if let networkDrives = checkForNetworkDrives() {
                Label(networkDrives, systemImage: "network")
                  .font(.caption)
                  .foregroundColor(.orange)
                  .padding(.top, 4)
              }
            }

            // Show phase progress if in phase-based backup
            if backupManager.state.isProcessing {
              HStack(spacing: 4) {
                PhaseIndicator(
                  label: "Analyze", isActive: backupManager.state.currentPhase == .analyzingSource,
                  isComplete: backupManager.state.currentPhase.rawValue
                    > BackupPhase.analyzingSource.rawValue)
                PhaseIndicator(
                  label: "Manifest", isActive: backupManager.state.currentPhase == .buildingManifest,
                  isComplete: backupManager.state.currentPhase.rawValue
                    > BackupPhase.buildingManifest.rawValue)
                PhaseIndicator(
                  label: "Copy", isActive: backupManager.state.currentPhase == .copyingFiles,
                  isComplete: backupManager.state.currentPhase.rawValue
                    > BackupPhase.copyingFiles.rawValue)
                PhaseIndicator(
                  label: "Flush", isActive: backupManager.state.currentPhase == .flushingToDisk,
                  isComplete: backupManager.state.currentPhase.rawValue
                    > BackupPhase.flushingToDisk.rawValue)
                PhaseIndicator(
                  label: "Verify", isActive: backupManager.state.currentPhase == .verifyingDestinations,
                  isComplete: backupManager.state.currentPhase.rawValue
                    > BackupPhase.verifyingDestinations.rawValue)
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
  }

  private func checkDriveTypes() async {
    networkDestinations.removeAll()

    for destination in destinations {
      if let driveInfo = DriveAnalyzer.analyzeDrive(at: destination),
        driveInfo.connectionType == .network
      {
        networkDestinations.insert(destination.lastPathComponent)
      }
    }
  }
}
