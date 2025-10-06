//
//  ProgressPublisher+Debug.swift
//  ImageIntact
//
//  Debug extensions for ProgressPublisher
//

import Foundation

extension ProgressPublisher {

    /// Dump current state to console (can be called from LLDB)
    /// Usage in LLDB: po ProgressPublisher.shared.dumpState()
    @MainActor
    func dumpState() {
        print("╔══════════════════════════════════════════════════════╗")
        print("║          ProgressPublisher State Dump                 ║")
        print("╚══════════════════════════════════════════════════════╝")
        print("")

        print("📊 Core State:")
        print("├─ isBackupRunning: \(isBackupRunning)")
        print("├─ currentPhase: \(currentPhase)")
        print("├─ overallProgress: \(String(format: "%.2f%%", overallProgress * 100))")
        print("└─ statusMessage: \(statusMessage.isEmpty ? "[empty]" : statusMessage)")
        print("")

        print("📁 File Progress:")
        print("├─ totalFiles: \(totalFiles)")
        print("├─ processedFiles: \(processedFiles)")
        print("└─ currentFileName: \(currentFileName.isEmpty ? "[none]" : currentFileName)")
        print("")

        if totalBytes > 0 {
            print("💾 Data Progress:")
            print("├─ totalBytes: \(ProgressPublisher.formatBytes(totalBytes))")
            print("├─ transferredBytes: \(ProgressPublisher.formatBytes(transferredBytes))")
            print("├─ currentSpeed: \(String(format: "%.2f MB/s", currentSpeed))")
            if let eta = estimatedTimeRemaining {
                print("└─ ETA: \(ProgressPublisher.formatETA(eta))")
            } else {
                print("└─ ETA: [calculating...]")
            }
            print("")
        }

        if !destinations.isEmpty {
            print("🎯 Destinations (\(destinations.count)):")
            for (index, (name, progress)) in destinations.enumerated() {
                let prefix = index == destinations.count - 1 ? "└─" : "├─"
                print("\(prefix) \(name):")
                print("   ├─ Files: \(progress.filesCompleted)/\(progress.filesTotal)")
                print("   ├─ State: \(progress.state)")
                print("   ├─ Bytes: \(ProgressPublisher.formatBytes(progress.bytesTransferred))")
                if progress.isVerifying {
                    print("   ├─ Verifying: true")
                    print("   └─ Verified: \(progress.verifiedCount)")
                } else {
                    print("   └─ Speed: \(String(format: "%.2f MB/s", progress.speed))")
                }
            }
            print("")
        }

        if isAnalyzing {
            print("🔍 Analysis Progress:")
            print("├─ Images analyzed: \(analyzedImages)/\(totalImagesToAnalyze)")
            print("└─ Progress: \(String(format: "%.1f%%", Double(analyzedImages) / Double(max(1, totalImagesToAnalyze)) * 100))")
            print("")
        }

        if networkOperationInProgress {
            print("🌐 Network Operation:")
            print("├─ Message: \(networkOperationMessage)")
            if networkRetryAttempt > 0 {
                print("└─ Retry: \(networkRetryAttempt)/\(networkRetryMaxAttempts)")
            } else {
                print("└─ Status: In progress")
            }
            print("")
        }

        if !failedFiles.isEmpty {
            print("❌ Failed Files (\(failedFiles.count)):")
            for (index, failure) in failedFiles.prefix(5).enumerated() {
                let prefix = (index == min(4, failedFiles.count - 1)) ? "└─" : "├─"
                print("\(prefix) \(failure.file)")
                print("   └─ \(failure.error)")
            }
            if failedFiles.count > 5 {
                print("   ... and \(failedFiles.count - 5) more")
            }
            print("")
        }

        print("═════════════════════════════════════════════════════════")
    }

    /// Get a performance report
    @MainActor
    func performanceReport() -> String {
        var report: [String] = []

        report.append("=== ProgressPublisher Performance Report ===")
        report.append("")

        // Calculate effective transfer rate
        if transferredBytes > 0 && !destinations.isEmpty {
            let avgSpeed = destinations.values.map { $0.speed }.reduce(0, +) / Double(destinations.count)
            report.append("Average Speed: \(String(format: "%.2f MB/s", avgSpeed))")

            let maxSpeed = destinations.values.map { $0.speed }.max() ?? 0
            report.append("Peak Speed: \(String(format: "%.2f MB/s", maxSpeed))")
        }

        // Calculate progress rate
        if processedFiles > 0 && totalFiles > 0 {
            let progressRate = Double(processedFiles) / Double(totalFiles)
            report.append("Progress Rate: \(String(format: "%.1f%%", progressRate * 100))")
        }

        // Destination performance
        if !destinations.isEmpty {
            report.append("")
            report.append("Per-Destination Performance:")
            for (name, dest) in destinations {
                let efficiency = dest.filesTotal > 0 ? Double(dest.filesCompleted) / Double(dest.filesTotal) : 0
                report.append("  \(name): \(String(format: "%.1f%% complete, %.2f MB/s", efficiency * 100, dest.speed))")
            }
        }

        // Error rate
        if processedFiles > 0 {
            let errorRate = Double(failedFiles.count) / Double(processedFiles + failedFiles.count)
            report.append("")
            report.append("Error Rate: \(String(format: "%.2f%%", errorRate * 100))")
        }

        return report.joined(separator: "\n")
    }

    /// Simulate progress for testing UI updates
    @MainActor
    func simulateProgress() {
        print("🧪 Starting progress simulation...")

        // Start a backup
        startBackup(
            totalFiles: 1000,
            totalBytes: 1_000_000_000, // 1GB
            destinationNames: ["TestDrive1", "TestDrive2", "TestDrive3"]
        )

        updatePhase(.analyzingSource)

        Task {
            // Simulate analyzing
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            updatePhase(.buildingManifest)

            // Simulate manifest building
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            updatePhase(.copyingFiles)

            // Simulate file copying
            for i in 1...10 {
                for dest in destinations.keys {
                    updateDestinationProgress(
                        name: dest,
                        filesCompleted: i * 100,
                        bytesTransferred: Int64(i * 100_000_000),
                        state: .copying,
                        currentFile: "test_file_\(i * 100).jpg"
                    )
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }

            // Simulate verification
            updatePhase(.verifyingDestinations)
            for dest in destinations.keys {
                updateDestinationProgress(name: dest, state: .verifying, isVerifying: true)
            }

            for i in 1...10 {
                for dest in destinations.keys {
                    updateDestinationProgress(
                        name: dest,
                        verifiedCount: i * 100
                    )
                }
                try? await Task.sleep(nanoseconds: 300_000_000)
            }

            // Complete
            completeBackup()
            print("✅ Progress simulation complete")
        }
    }
}

// MARK: - Console Commands (callable from LLDB)
#if DEBUG
extension ProgressPublisher {

    /// Quick status check
    /// Usage: po ProgressPublisher.status()
    @MainActor
    static func status() {
        let pub = ProgressPublisher.shared
        if pub.isBackupRunning {
            print("🏃 Backup running: \(pub.currentPhase) - \(String(format: "%.1f%%", pub.overallProgress * 100))")
            print("   Files: \(pub.processedFiles)/\(pub.totalFiles)")
            print("   Status: \(pub.statusMessage)")
        } else {
            print("💤 No backup running")
        }
    }

    /// Force a UI update (useful for debugging UI refresh issues)
    /// Usage: po ProgressPublisher.forceUpdate()
    @MainActor
    static func forceUpdate() {
        shared.objectWillChange.send()
        print("🔄 Forced UI update")
    }

    /// List all active destinations
    /// Usage: po ProgressPublisher.listDestinations()
    @MainActor
    static func listDestinations() {
        let pub = ProgressPublisher.shared
        if pub.destinations.isEmpty {
            print("No active destinations")
        } else {
            for (name, dest) in pub.destinations {
                print("\(name): \(dest.filesCompleted)/\(dest.filesTotal) (\(dest.state))")
            }
        }
    }
}
#endif