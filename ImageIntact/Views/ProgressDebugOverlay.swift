//
//  ProgressDebugOverlay.swift
//  ImageIntact
//
//  Debug overlay for monitoring ProgressPublisher state in real-time
//

import SwiftUI

/// A debug overlay that shows all ProgressPublisher state
struct ProgressDebugOverlay: View {
    @ObservedObject var progressPublisher = ProgressPublisher.shared
    @State private var isExpanded = false
    @State private var copyToPasteboard = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            // Collapsed state - just show indicator
            if !isExpanded {
                Button(action: { isExpanded.toggle() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "ladybug.fill")
                        Text("Debug")
                    }
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.purple.opacity(0.2))
                    .foregroundColor(.purple)
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help("Show progress debug overlay")
            }

            // Expanded state - show full debug info
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    // Header
                    HStack {
                        Label("Progress Debug", systemImage: "ladybug.fill")
                            .font(.caption.bold())
                            .foregroundColor(.purple)

                        Spacer()

                        Button(action: copyDebugInfo) {
                            Image(systemName: "doc.on.doc")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .help("Copy debug info to clipboard")

                        Button(action: { isExpanded = false }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .help("Close debug overlay")
                    }

                    Divider()

                    // Core State
                    DebugSection(title: "Core State") {
                        DebugRow("Running", progressPublisher.isBackupRunning)
                        DebugRow("Phase", progressPublisher.currentPhase.debugDescription)
                        DebugRow("Overall", String(format: "%.1f%%", progressPublisher.overallProgress * 100))
                        DebugRow("Status", progressPublisher.statusMessage.isEmpty ? "—" : progressPublisher.statusMessage)
                    }

                    // File Progress
                    DebugSection(title: "Files") {
                        DebugRow("Total", "\(progressPublisher.totalFiles)")
                        DebugRow("Processed", "\(progressPublisher.processedFiles)")
                        DebugRow("Current", progressPublisher.currentFileName.isEmpty ? "—" : progressPublisher.currentFileName)
                    }

                    // Bytes Progress
                    if progressPublisher.totalBytes > 0 {
                        DebugSection(title: "Data") {
                            DebugRow("Total", formatBytes(progressPublisher.totalBytes))
                            DebugRow("Transferred", formatBytes(progressPublisher.transferredBytes))
                            DebugRow("Speed", String(format: "%.1f MB/s", progressPublisher.currentSpeed))
                            if let eta = progressPublisher.estimatedTimeRemaining {
                                DebugRow("ETA", formatETA(eta))
                            }
                        }
                    }

                    // Destinations
                    if !progressPublisher.destinations.isEmpty {
                        DebugSection(title: "Destinations") {
                            ForEach(Array(progressPublisher.destinations.keys.sorted()), id: \.self) { key in
                                if let dest = progressPublisher.destinations[key] {
                                    DebugRow(dest.name, "\(dest.filesCompleted)/\(dest.filesTotal) (\(dest.state))")
                                    if dest.isVerifying {
                                        DebugRow("  Verified", "\(dest.verifiedCount)")
                                    }
                                }
                            }
                        }
                    }

                    // Analysis Progress
                    if progressPublisher.isAnalyzing {
                        DebugSection(title: "Analysis") {
                            DebugRow("Images", "\(progressPublisher.analyzedImages)/\(progressPublisher.totalImagesToAnalyze)")
                        }
                    }

                    // Network Status
                    if progressPublisher.networkOperationInProgress {
                        DebugSection(title: "Network") {
                            DebugRow("Message", progressPublisher.networkOperationMessage)
                            if progressPublisher.networkRetryAttempt > 0 {
                                DebugRow("Retry", "\(progressPublisher.networkRetryAttempt)/\(progressPublisher.networkRetryMaxAttempts)")
                            }
                        }
                    }

                    // Errors
                    if let lastError = progressPublisher.lastError {
                        DebugSection(title: "Errors") {
                            DebugRow("Last", String(lastError.prefix(50)))
                            DebugRow("Failed", "\(progressPublisher.failedFiles.count) files")
                        }
                    }
                }
                .font(.system(size: 10, design: .monospaced))
                .padding(12)
                .frame(width: 350)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .shadow(radius: 4)

                if copyToPasteboard {
                    Text("Copied!")
                        .font(.caption2)
                        .foregroundColor(.green)
                        .transition(.opacity)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                copyToPasteboard = false
                            }
                        }
                }
            }
        }
    }

    private func copyDebugInfo() {
        let info = generateDebugInfo()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(info, forType: .string)
        copyToPasteboard = true
    }

    private func generateDebugInfo() -> String {
        var lines: [String] = []
        lines.append("=== ProgressPublisher Debug Info ===")
        lines.append("Timestamp: \(Date())")
        lines.append("")

        lines.append("Core State:")
        lines.append("  Running: \(progressPublisher.isBackupRunning)")
        lines.append("  Phase: \(progressPublisher.currentPhase)")
        lines.append("  Progress: \(String(format: "%.1f%%", progressPublisher.overallProgress * 100))")
        lines.append("  Status: \(progressPublisher.statusMessage)")
        lines.append("")

        lines.append("Files:")
        lines.append("  Total: \(progressPublisher.totalFiles)")
        lines.append("  Processed: \(progressPublisher.processedFiles)")
        lines.append("  Current: \(progressPublisher.currentFileName)")
        lines.append("")

        if progressPublisher.totalBytes > 0 {
            lines.append("Data:")
            lines.append("  Total: \(formatBytes(progressPublisher.totalBytes))")
            lines.append("  Transferred: \(formatBytes(progressPublisher.transferredBytes))")
            lines.append("  Speed: \(String(format: "%.1f MB/s", progressPublisher.currentSpeed))")
            if let eta = progressPublisher.estimatedTimeRemaining {
                lines.append("  ETA: \(formatETA(eta))")
            }
            lines.append("")
        }

        if !progressPublisher.destinations.isEmpty {
            lines.append("Destinations:")
            for (name, dest) in progressPublisher.destinations {
                lines.append("  \(name): \(dest.filesCompleted)/\(dest.filesTotal) - \(dest.state)")
            }
            lines.append("")
        }

        if progressPublisher.isAnalyzing {
            lines.append("Analysis:")
            lines.append("  Progress: \(progressPublisher.analyzedImages)/\(progressPublisher.totalImagesToAnalyze)")
            lines.append("")
        }

        if let lastError = progressPublisher.lastError {
            lines.append("Errors:")
            lines.append("  Last: \(lastError)")
            lines.append("  Failed Files: \(progressPublisher.failedFiles.count)")
            lines.append("")
        }

        lines.append("=== End Debug Info ===")
        return lines.joined(separator: "\n")
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func formatETA(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "< 1 min"
        } else if seconds < 3600 {
            return "\(Int(seconds / 60)) min"
        } else {
            let hours = Int(seconds / 3600)
            let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(hours)h \(minutes)m"
        }
    }
}

// MARK: - Helper Views

struct DebugSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.bold())
                .foregroundColor(.secondary)
            content()
        }
    }
}

struct DebugRow: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    init(_ label: String, _ value: Bool) {
        self.label = label
        self.value = value ? "✓" : "✗"
    }

    var body: some View {
        HStack(spacing: 4) {
            Text("\(label):")
                .foregroundColor(.secondary)
            Text(value)
                .foregroundColor(.primary)
            Spacer()
        }
    }
}

// MARK: - Phase Debug Description
extension BackupPhase {
    var debugDescription: String {
        switch self {
        case .idle: return "idle"
        case .analyzingSource: return "analyzing"
        case .buildingManifest: return "manifest"
        case .copyingFiles: return "copying"
        case .flushingToDisk: return "flushing"
        case .verifyingDestinations: return "verifying"
        case .complete: return "complete"
        }
    }
}