#!/usr/bin/env swift

// Test script to verify ProgressPublisher updates are working
// Run with: swift test-progress-updates.swift

import Foundation
import Combine

@MainActor
class ProgressTester {
    private var cancellables = Set<AnyCancellable>()

    func runTest() {
        print("📊 Testing ProgressPublisher Updates")
        print("=" * 50)

        // Get the shared instance
        let publisher = ProgressPublisher.shared

        // Subscribe to all published properties
        publisher.$isBackupRunning
            .sink { running in
                print("🏃 isBackupRunning: \(running)")
            }
            .store(in: &cancellables)

        publisher.$currentPhase
            .sink { phase in
                print("📍 Phase: \(phase)")
            }
            .store(in: &cancellables)

        publisher.$overallProgress
            .sink { progress in
                print("📈 Overall Progress: \(String(format: "%.1f%%", progress * 100))")
            }
            .store(in: &cancellables)

        publisher.$processedFiles
            .sink { files in
                print("📁 Processed Files: \(files)")
            }
            .store(in: &cancellables)

        publisher.$destinations
            .sink { destinations in
                if !destinations.isEmpty {
                    print("🎯 Destinations Update:")
                    for (name, progress) in destinations {
                        print("   - \(name): \(progress.filesCompleted)/\(progress.filesTotal) (\(progress.state))")
                    }
                }
            }
            .store(in: &cancellables)

        // Simulate a backup operation
        print("\n🚀 Starting simulated backup...")

        // Start backup
        publisher.startBackup(
            totalFiles: 100,
            totalBytes: 1_000_000,
            destinationNames: ["Drive1", "Drive2", "Drive3"]
        )

        // Simulate phase changes
        Thread.sleep(forTimeInterval: 0.5)
        publisher.updatePhase(.analyzingSource)

        Thread.sleep(forTimeInterval: 0.5)
        publisher.updatePhase(.buildingManifest)

        Thread.sleep(forTimeInterval: 0.5)
        publisher.updatePhase(.copyingFiles)

        // Simulate file completions
        for i in 1...10 {
            Thread.sleep(forTimeInterval: 0.2)

            // Update each destination
            for dest in ["Drive1", "Drive2", "Drive3"] {
                publisher.updateDestinationProgress(
                    name: dest,
                    filesCompleted: i * 10,
                    bytesTransferred: Int64(i * 100_000),
                    state: .copying,
                    currentFile: "file\(i * 10).jpg"
                )
            }

            print("📊 Simulated \(i * 10) files completed")
        }

        // Simulate verification
        Thread.sleep(forTimeInterval: 0.5)
        publisher.updatePhase(.verifyingDestinations)

        for dest in ["Drive1", "Drive2", "Drive3"] {
            publisher.updateDestinationProgress(
                name: dest,
                state: .verifying,
                isVerifying: true
            )
        }

        // Complete
        Thread.sleep(forTimeInterval: 0.5)
        publisher.completeBackup()

        print("\n✅ Test completed!")
        print("If you saw regular updates above, the ProgressPublisher is working correctly.")
    }
}

// Run the test
Task { @MainActor in
    let tester = ProgressTester()
    tester.runTest()

    // Keep the script running for a moment to let all updates process
    Thread.sleep(forTimeInterval: 2)
    exit(0)
}

// Keep RunLoop alive
RunLoop.main.run()