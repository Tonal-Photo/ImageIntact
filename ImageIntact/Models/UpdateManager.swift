import Foundation
import SwiftUI

// MARK: - Update Check Result States

enum UpdateCheckResult {
    case checking
    case upToDate
    case updateAvailable(AppUpdate)
    case error(Error)
    case downloading(progress: Double)
}

/// Manages application updates using a protocol-based provider system
@Observable
class UpdateManager {
    // MARK: - Published Properties

    var isCheckingForUpdates = false
    var availableUpdate: AppUpdate?
    var downloadProgress: Double = 0.0
    var isDownloadingUpdate = false
    var lastError: UpdateError?
    var showUpdateSheet = false
    var updateCheckResult: UpdateCheckResult = .checking

    // MARK: - Test Mode Properties

    static var testMode = false
    static var mockVersion: String?
    var isTestMode: Bool { UpdateManager.testMode }

    private var updateProvider: UpdateProvider
    private var settings = UpdateSettings.load()
    private var downloadTask: Task<Void, Never>?

    /// Get current app version from Info.plist (or mock version in test mode)
    var currentVersion: String {
        // Check for test mode mock version
        if UpdateManager.testMode, let mockVersion = UpdateManager.mockVersion {
            ApplicationLogger.shared.debug("TEST MODE: Reporting mock version \(mockVersion)", category: .network)
            return mockVersion
        }
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    init(provider: UpdateProvider? = nil) {
        // Default to GitHub provider, but allow injection for testing
        updateProvider = provider ?? GitHubUpdateProvider()
        ApplicationLogger.shared.debug("UpdateManager initialized with \(updateProvider.providerName)", category: .network)

        // Check for test mode from launch arguments
        checkForTestMode()
    }

    /// Check launch arguments and environment for test mode
    private func checkForTestMode() {
        #if DEBUG
            // Only check for test mode in debug builds
            let arguments = ProcessInfo.processInfo.arguments
            let environment = ProcessInfo.processInfo.environment

            // Check for test mode flag
            if arguments.contains("--test-update") || environment["IMAGEINTACT_TEST_UPDATE"] == "1" {
                UpdateManager.testMode = true
                ApplicationLogger.shared.debug("TEST MODE ACTIVATED", category: .network)

                // Check for mock version
                if let index = arguments.firstIndex(of: "--mock-version"),
                   index + 1 < arguments.count
                {
                    UpdateManager.mockVersion = arguments[index + 1]
                    ApplicationLogger.shared.debug("Mock version set to: \(arguments[index + 1])", category: .network)
                } else if let mockVersion = environment["IMAGEINTACT_MOCK_VERSION"] {
                    UpdateManager.mockVersion = mockVersion
                    ApplicationLogger.shared.debug("Mock version set to: \(mockVersion)", category: .network)
                } else {
                    // Default mock version if test mode but no version specified
                    UpdateManager.mockVersion = "1.0.0"
                    ApplicationLogger.shared.debug("Using default mock version: 1.0.0", category: .network)
                }
            }
        #else
            // In release builds, never enable test mode
            UpdateManager.testMode = false
            UpdateManager.mockVersion = nil
        #endif
    }

    // MARK: - Public Methods

    /// Check for updates (called on app launch if auto-check enabled)
    func checkForUpdates() {
        // In test mode, always check for updates regardless of last check time
        if UpdateManager.testMode {
            ApplicationLogger.shared.debug("Test mode: Forcing update check on launch", category: .network)
            Task {
                await performUpdateCheck()
            }
            return
        }

        guard settings.shouldCheckForUpdates() else {
            ApplicationLogger.shared.debug("Skipping automatic update check", category: .network)
            return
        }

        Task {
            await performUpdateCheck()
        }
    }

    /// Manually check for updates (via menu command)
    @MainActor
    func performUpdateCheck(isManual: Bool = false) async {
        guard !isCheckingForUpdates else { return }

        if isManual {
            showUpdateSheet = true
            updateCheckResult = .checking
        }

        isCheckingForUpdates = true
        lastError = nil

        defer {
            isCheckingForUpdates = false
            // Don't mark update check in test mode so it always checks
            if !UpdateManager.testMode {
                settings.markUpdateCheck()
            }
        }

        // Add a small delay so the user sees the checking state
        if isManual {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }

        do {
            ApplicationLogger.shared.debug("Checking for updates via \(updateProvider.providerName)...", category: .network)
            let update = try await updateProvider.checkForUpdates(currentVersion: currentVersion)

            if let update = update {
                // Check if this version is skipped
                if settings.isVersionSkipped(update.version) {
                    ApplicationLogger.shared.debug("Version \(update.version) is skipped by user preference", category: .network)
                    if isManual {
                        updateCheckResult = .upToDate
                    }
                    return
                }

                // Check OS compatibility
                if let minOS = update.minimumOSVersion {
                    if !isOSCompatible(minimumVersion: minOS) {
                        ApplicationLogger.shared.debug("Update requires macOS \(minOS) or later", category: .network)
                        lastError = .unsupportedPlatform
                        if isManual {
                            updateCheckResult = .error(UpdateError.unsupportedPlatform)
                        }
                        return
                    }
                }

                ApplicationLogger.shared.debug("Update available: v\(update.version)", category: .network)
                availableUpdate = update
                updateCheckResult = .updateAvailable(update)

                // Always show the update sheet for consistency
                if !isManual {
                    // For auto-check, show the sheet with the update
                    showUpdateSheet = true
                }
            } else {
                ApplicationLogger.shared.debug("No updates available (current: v\(currentVersion))", category: .network)

                if isManual {
                    updateCheckResult = .upToDate
                }
            }
        } catch {
            ApplicationLogger.shared.debug("Update check failed: \(error)", category: .network)
            lastError = error as? UpdateError ?? .networkError(error)

            if isManual {
                updateCheckResult = .error(error)
            }
        }
    }

    /// Download the available update
    @MainActor
    func downloadUpdate(_ update: AppUpdate) async {
        guard !isDownloadingUpdate else { return }

        isDownloadingUpdate = true
        downloadProgress = 0.0

        // Ensure the update sheet is visible to show progress
        await MainActor.run { [weak self] in
            self?.showUpdateSheet = true
            self?.updateCheckResult = .downloading(progress: 0.0)
        }

        downloadTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                ApplicationLogger.shared.debug("Starting download of update v\(update.version)...", category: .network)
                ApplicationLogger.shared.debug("Download URL: \(update.downloadURL)", category: .network)

                let localURL = try await self.updateProvider.downloadUpdate(update) { progress in
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        self.downloadProgress = progress
                        self.updateCheckResult = .downloading(progress: progress)
                        ApplicationLogger.shared.debug("Download progress: \(Int(progress * 100))%", category: .network)
                    }
                }

                ApplicationLogger.shared.debug("Update downloaded successfully to: \(localURL)", category: .network)

                // Mount and open the DMG
                await self.mountAndOpenDMG(at: localURL)

                // Dismiss sheets
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    self.showUpdateSheet = false
                    self.isDownloadingUpdate = false

                    // Show completion message
                    self.showDownloadCompleteAlert(at: localURL)
                }

            } catch {
                ApplicationLogger.shared.debug("Download failed: \(error)", category: .network)
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    self.lastError = error as? UpdateError ?? .downloadFailed(error)
                    self.isDownloadingUpdate = false
                    self.updateCheckResult = .error(error)
                }
            }
        }
    }

    /// Cancel ongoing download
    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        isDownloadingUpdate = false
        downloadProgress = 0.0
    }

    /// Skip a version
    func skipVersion(_ version: String) {
        var updatedSettings = settings
        updatedSettings.skipVersion(version)
        settings = updatedSettings
        showUpdateSheet = false
        availableUpdate = nil
    }

    // MARK: - DMG Handling

    /// Mount a DMG and open it in Finder
    private func mountAndOpenDMG(at url: URL) async {
        ApplicationLogger.shared.debug("Mounting DMG: \(url.lastPathComponent)", category: .network)

        do {
            // Use hdiutil to mount the DMG
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            process.arguments = ["attach", url.path, "-autoopen"]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                ApplicationLogger.shared.debug("DMG mounted successfully", category: .network)

                // Read output to find mount point
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    ApplicationLogger.shared.debug("Mount output: \(output)", category: .network)

                    // Extract mount point (usually /Volumes/ImageIntact-X.X.X)
                    let lines = output.components(separatedBy: .newlines)
                    for line in lines {
                        if line.contains("/Volumes/") {
                            let components = line.components(separatedBy: .whitespaces)
                            if let volumePath = components.last {
                                ApplicationLogger.shared.debug("Opening mounted volume: \(volumePath)", category: .network)
                                // Open the mounted volume in Finder
                                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: volumePath)
                            }
                        }
                    }
                }
            } else {
                ApplicationLogger.shared.debug("Failed to mount DMG (exit code: \(process.terminationStatus))", category: .network)
                // Fallback: just open the DMG file
                NSWorkspace.shared.open(url)
            }
        } catch {
            ApplicationLogger.shared.debug("Error mounting DMG: \(error)", category: .network)
            // Fallback: just open the DMG file
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Settings Management

    /// Enable or disable automatic update checks
    func setAutomaticChecking(_ enabled: Bool) {
        settings.automaticallyCheckForUpdates = enabled
        settings.save()
    }

    /// Set update check interval
    func setCheckInterval(_ interval: TimeInterval) {
        settings.checkInterval = interval
        settings.save()
    }

    // MARK: - Helper Methods

    /// Check if current OS is compatible with minimum version
    private func isOSCompatible(minimumVersion: String) -> Bool {
        let currentOS = ProcessInfo.processInfo.operatingSystemVersion
        let currentOSString = "\(currentOS.majorVersion).\(currentOS.minorVersion)"

        return currentOSString.compare(minimumVersion, options: .numeric) != .orderedAscending
    }

    /// Show alert when no updates are available
    private func showNoUpdatesAlert() {
        let alert = NSAlert()
        alert.messageText = "You're up to date!"
        alert.informativeText = "ImageIntact \(currentVersion) is the latest version available."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// Show error alert
    private func showErrorAlert() {
        guard let error = lastError else { return }

        let alert = NSAlert()
        alert.messageText = "Update Check Failed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// Show download complete alert
    private func showDownloadCompleteAlert(at url: URL) {
        let alert = NSAlert()
        alert.messageText = "Update Ready to Install"

        var message = "The update has been downloaded and the installer will now open.\n\n"
        message += "⚠️ IMPORTANT: Before installing:\n"
        message += "1. Quit ImageIntact (Cmd+Q)\n"
        message += "2. Drag the new ImageIntact to Applications\n"
        message += "3. Replace the existing version when prompted\n\n"

        if UpdateManager.testMode {
            message += "🧪 TEST MODE: This is a test download.\n"
            message += "Location: \(url.path)"
        }

        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open Installer")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            // User clicked "Open Installer"
            // The DMG mounting happens in the calling function
        }
    }
}

// MARK: - Mock Provider for Testing

#if DEBUG
    /// Mock provider for testing update UI without hitting GitHub
    class MockUpdateProvider: UpdateProvider {
        var providerName: String { "Mock Provider" }

        func checkForUpdates(currentVersion _: String) async throws -> AppUpdate? {
            // Simulate network delay
            try await Task.sleep(nanoseconds: 1_000_000_000)

            // Return a fake update
            guard let testURL = URL(string: "https://example.com/test.dmg") else {
                return nil
            }
            return AppUpdate(
                version: "99.9.9",
                releaseNotes:
                "This is a test update for development purposes.\n\n• Feature 1\n• Feature 2\n• Bug fixes",
                downloadURL: testURL,
                publishedDate: Date(),
                minimumOSVersion: "14.0",
                fileSize: 10_000_000
            )
        }

        func downloadUpdate(_: AppUpdate, progress: @escaping (Double) -> Void) async throws
            -> URL
        {
            // Simulate download progress
            for i in 0 ... 10 {
                try await Task.sleep(nanoseconds: 100_000_000)
                progress(Double(i) / 10.0)
            }

            // Return a fake path
            return FileManager.default.temporaryDirectory.appendingPathComponent("test.dmg")
        }
    }
#endif
