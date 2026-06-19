//
//  MultiDestinationProgressDetails.swift
//  ImageIntact
//
//  Detail views for the live backup-progress section, split out of
//  MultiDestinationProgressSection.swift to keep each file under the
//  500-line limit. Carries the UI-test "progress.live" marker (AMUX-461).
//

import SwiftUI

struct SimpleBackupProgress: View {
  @Bindable var backupManager: BackupManager

  private func formatDataProgress() -> String {
    let copiedMB = Double(backupManager.progressTracker.totalBytesCopied) / (1024 * 1024)
    let totalMB = Double(backupManager.progressTracker.totalBytesToCopy) / (1024 * 1024)

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
          .uiTestLiveProgressMarker(backupManager)

        Spacer()

        Button(action: {
          backupManager.cancelOperation()
        }) {
          Image(systemName: "xmark.circle.fill")
            .foregroundColor(.red)
            .imageScale(.large)
        }
        .buttonStyle(.plain)
        .help("Cancel backup")
      }

      VStack(alignment: .leading, spacing: 8) {
        // Show current phase
        Text("Phase: \(phaseDescription(for: backupManager.state.currentPhase))")
          .font(.caption)
          .foregroundColor(.secondary)

        HStack {
          // Show appropriate counter based on phase
          if backupManager.state.currentPhase == .verifyingDestinations {
            Text(
              "Verifying: \(backupManager.progressTracker.verifiedFiles)/\(backupManager.progressTracker.totalFiles)"
            )
            .font(.subheadline)
          } else {
            Text("Files: \(backupManager.progressTracker.processedFiles)/\(backupManager.progressTracker.totalFiles)")
              .font(.subheadline)
          }

          Spacer()

          // Data processed display
          if backupManager.progressTracker.totalBytesCopied > 0 {
            let processedMB = Double(backupManager.progressTracker.totalBytesCopied) / (1024 * 1024)
            Text(
              String(
                format: "%.1f MB/s",
                backupManager.progressTracker.copySpeed > 0
                  ? backupManager.progressTracker.copySpeed
                  : processedMB
                    / max(1, Date().timeIntervalSince(backupManager.progressTracker.copyStartTime)))
            )
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
          ProgressView(value: backupManager.progressTracker.overallProgress)
            .progressViewStyle(.linear)

          // Data progress indicator
          if backupManager.progressTracker.totalBytesToCopy > 0 {
            Text(formatDataProgress())
              .font(.caption2)
              .foregroundColor(.secondary)
              .monospacedDigit()
          }
        }

        HStack {
          if !backupManager.progressTracker.currentFileName.isEmpty {
            Text("Current: \(backupManager.progressTracker.currentFileName)")
              .font(.caption2)
              .foregroundColor(.secondary)
              .lineLimit(1)
              .truncationMode(.middle)
          }

          Spacer()

          if !backupManager.progressTracker.currentDestinationName.isEmpty {
            Text("→ \(backupManager.progressTracker.currentDestinationName)")
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
        driveInfo.connectionType == .network
      {
        networkDrives.insert(destination.lastPathComponent)
      }
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Backup Progress")
          .font(.headline)
          .uiTestLiveProgressMarker(backupManager)

        Spacer()

        // Show aggregate progress
        if backupManager.progressTracker.overallProgress > 0 {
          Text("\(Int(backupManager.progressTracker.overallProgress * 100))% Complete")
            .font(.subheadline)
            .foregroundColor(.secondary)
        }

        Button(action: {
          backupManager.cancelOperation()
        }) {
          Image(systemName: "xmark.circle.fill")
            .foregroundColor(.red)
            .imageScale(.large)
        }
        .buttonStyle(.plain)
        .help("Cancel backup")
      }

      // Overall progress bar (shows total progress across all phases)
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text("Overall Progress")
            .font(.caption2)
            .foregroundColor(.secondary)
          Spacer()
          if !backupManager.state.overallStatusText.isEmpty {
            Text(backupManager.state.overallStatusText)
              .font(.caption2)
              .foregroundColor(.secondary)
          } else if backupManager.state.currentPhase == .buildingManifest {
            Text("Building manifest...")
              .font(.caption2)
              .foregroundColor(.secondary)
          } else if backupManager.state.currentPhase == .complete {
            Text("Complete")
              .font(.caption2)
              .foregroundColor(.green)
          }
        }
        ProgressView(value: backupManager.progressTracker.overallProgress)
          .progressViewStyle(.linear)
      }

      // Per-destination progress
      if backupManager.state.currentPhase == .buildingManifest {
        // During manifest building, show a single progress for all destinations
        VStack(alignment: .leading, spacing: 4) {
          Text("Building source manifest for all destinations...")
            .font(.caption)
            .foregroundColor(.secondary)
          ProgressView(value: backupManager.progressTracker.phaseProgress)
            .progressViewStyle(.linear)
        }
      } else if backupManager.state.currentPhase != .idle
        && backupManager.state.currentPhase != .analyzingSource
      {
        // Show destination rows for all other phases
        ForEach(destinations, id: \.lastPathComponent) { destination in
          DestinationProgressRow(
            destinationName: destination.lastPathComponent,
            completedFiles: backupManager.progressTracker.destinationProgress[destination.lastPathComponent] ?? 0,
            totalFiles: backupManager.progressTracker.destinationTotalFiles[
              destination.lastPathComponent] ?? backupManager.progressTracker.totalFiles,
            isActive: backupManager.progressTracker.currentDestinationName == destination.lastPathComponent,
            phase: backupManager.state.currentPhase,
            state: backupManager.progressTracker.destinationStates[destination.lastPathComponent] ?? "copying",
            isNetworkDrive: networkDrives.contains(destination.lastPathComponent)
          )
        }
      }

      // Current file info
      if !backupManager.progressTracker.currentFileName.isEmpty {
        HStack {
          Text("Current: \(backupManager.progressTracker.currentFileName)")
            .font(.caption2)
            .foregroundColor(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)

          Spacer()

          if !backupManager.progressTracker.currentDestinationName.isEmpty {
            Text("→ \(backupManager.progressTracker.currentDestinationName)")
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
        .scaleEffect(x: 1, y: 0.6)  // Make it a bit thinner
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
        .fill(
          isActive
            ? Color.accentColor : (isComplete ? Color.green.opacity(0.2) : Color.gray.opacity(0.2)))
    )
    .foregroundColor(isActive ? .white : (isComplete ? .green : .secondary))
  }
}

// MARK: - UI-test live-progress marker
//
// Exposes the live backup-progress state as a single machine-readable
// accessibility value on the "Backup Progress" headline, so the XCUITest suite
// can assert the progress bar advances, the phase moves copy → verify, and
// per-destination counts climb to the total. Gated on UITestSeam.isActive
// (DEBUG + --uitest), so Release builds and VoiceOver are unaffected and the
// view's layout is unchanged. See .planning/design/ui-test-live-progress.md.

private func uiTestPhaseLabel(_ phase: BackupPhase) -> String {
  switch phase {
  case .idle: return "idle"
  case .analyzingSource: return "analyzingSource"
  case .buildingManifest: return "buildingManifest"
  case .copyingFiles: return "copyingFiles"
  case .flushingToDisk: return "flushingToDisk"
  case .verifyingDestinations: return "verifyingDestinations"
  case .complete: return "complete"
  }
}

/// Grammar:
/// `phase=<raw>;name=<label>;overall=<0-100>;processed=N;verified=V;total=M;dests=name:done/total,...`
private func uiTestLiveProgressValue(_ backupManager: BackupManager) -> String {
  guard UITestSeam.isActive else { return "" }
  let pt = backupManager.progressTracker
  let phase = backupManager.state.currentPhase
  let destPairs = backupManager.destinationURLs.compactMap { $0 }.map { url -> String in
    let name = url.lastPathComponent
    let done = pt.destinationProgress[name] ?? 0
    let total = pt.destinationTotalFiles[name] ?? pt.totalFiles
    return "\(name):\(done)/\(total)"
  }.joined(separator: ",")
  let overall = Int((pt.overallProgress * 100).rounded())
  return "phase=\(phase.rawValue);name=\(uiTestPhaseLabel(phase));overall=\(overall);"
    + "processed=\(pt.processedFiles);verified=\(pt.verifiedFiles);total=\(pt.totalFiles);dests=\(destPairs)"
}

extension View {
  /// Attaches the `progress.live` marker — only under `--uitest`, so production
  /// builds add no identifier/value and the accessibility tree is unchanged.
  @ViewBuilder
  func uiTestLiveProgressMarker(_ backupManager: BackupManager) -> some View {
    if UITestSeam.isActive {
      accessibilityIdentifier("progress.live")
        .accessibilityValue(uiTestLiveProgressValue(backupManager))
    } else {
      self
    }
  }
}
