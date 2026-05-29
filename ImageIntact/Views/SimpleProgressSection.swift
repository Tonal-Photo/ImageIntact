import SwiftUI

struct SimpleProgressSection: View {
  @Bindable var backupManager: BackupManager

  var body: some View {
    if !backupManager.statusMessage.isEmpty || backupManager.isProcessing {
      VStack(alignment: .leading, spacing: 12) {
        Divider()
          .padding(.horizontal, 20)

        if backupManager.isProcessing && backupManager.progressTracker.totalFiles > 0 {
          // Simple overall progress
          VStack(alignment: .leading, spacing: 12) {
            HStack {
              Text("Backup Progress")
                .font(.headline)

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
              // Overall progress
              HStack {
                // Show appropriate counter based on phase
                if backupManager.currentPhase == .verifyingDestinations {
                  Text(
                    "Verifying: \(backupManager.progressTracker.verifiedFiles)/\(backupManager.progressTracker.totalFiles)"
                  )
                  .font(.subheadline)
                } else {
                  Text("Files: \(backupManager.progressTracker.processedFiles)/\(backupManager.progressTracker.totalFiles)")
                    .font(.subheadline)
                }

                Spacer()

                // ETA display
                let eta = backupManager.formattedETA()
                if !eta.isEmpty {
                  Text(eta)
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                if backupManager.progressTracker.copySpeed > 0 {
                  Text("\(String(format: "%.1f", backupManager.progressTracker.copySpeed)) MB/s")
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
              }

              ProgressView(value: backupManager.progressTracker.overallProgress)
                .progressViewStyle(.linear)

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
        } else {
          HStack {
            if backupManager.isProcessing {
              ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
                .scaleEffect(0.8)
            }

            Text(backupManager.statusMessage)
              .font(.system(.body, design: .monospaced))
              .foregroundColor(.secondary)

            Spacer()
          }
          .padding(.horizontal, 20)
        }
      }
      .transition(.opacity)
    }
  }
}
