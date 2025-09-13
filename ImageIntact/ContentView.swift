import SwiftUI
import Darwin

struct ContentView: View {
    @State private var backupManager = BackupManager()
    @State private var updateManager = UpdateManager()
    @FocusState private var focusedField: FocusField?
    
    // First-run and help system
    @State private var showWelcomePopup = false
    
    // Store event monitor to properly clean it up
    @State private var eventMonitor: Any?
    
    // Premium features
    @State private var showPurchaseView = false
    @State private var showUpgradeAlert = false
    
    enum FocusField: Hashable {
        case source
        case destination(Int)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header - following HIG for window headers
            VStack(spacing: 4) {
                // Test mode indicator (only in debug builds)
                #if DEBUG
                if updateManager.isTestMode {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("TEST MODE - Mock Version: \(updateManager.currentVersion)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(6)
                    .padding(.top, 8)
                }
                #endif
                
                Text("ImageIntact")
                    .font(.system(size: 20, weight: .semibold))
                
                Text("Verify and backup your photos to multiple locations")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                // Subtle system info display
                Text(SystemCapabilities.shared.displayName)
                    .font(.system(size: 10))
                    .foregroundColor(Color.secondary.opacity(0.5))
            }
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            Divider()
            
            // Main content - ScrollView for everything except header and bottom buttons
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Add consistent top padding
                        Color.clear.frame(height: 20)
                        
                        // Source Section
                        SourceFolderSection(backupManager: backupManager, focusedField: $focusedField)
                        
                        // Organization Section - only show if source is selected
                        if backupManager.sourceURL != nil {
                            // Consistent spacing between sections
                            Color.clear.frame(height: 20)
                            Divider()
                                .padding(.horizontal, 20)
                            Color.clear.frame(height: 20)
                            
                            OrganizationSection(backupManager: backupManager)
                        }
                        
                        // Consistent spacing between sections
                        Color.clear.frame(height: 20)
                        Divider()
                            .padding(.horizontal, 20)
                        Color.clear.frame(height: 20)
                        
                        // Destinations Section
                        DestinationSection(backupManager: backupManager, focusedField: $focusedField)
                        
                        // Progress Section
                        MultiDestinationProgressSection(backupManager: backupManager)
                            .id("progressSection")
                        
                        // Add some bottom padding so content doesn't hide behind buttons
                        Color.clear.frame(height: 20)
                    }
                }
                .frame(maxHeight: .infinity)
                .onChange(of: backupManager.isProcessing) { _, isProcessing in
                    if isProcessing {
                        // Auto-scroll to progress section when backup starts
                        withAnimation(.easeInOut(duration: 0.3)) {
                            scrollProxy.scrollTo("progressSection", anchor: .top)
                        }
                    }
                }
                .onChange(of: backupManager.currentPhase) { _, phase in
                    // Also scroll when we enter copying phase (in case initial scroll didn't work)
                    if phase == .copyingFiles && backupManager.isProcessing {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            scrollProxy.scrollTo("progressSection", anchor: .top)
                        }
                    }
                }
            }
            
            // Bottom action area - always visible
            Divider()
            
            HStack {
                Button("Clear All") {
                    backupManager.clearAllSelections()
                }
                .keyboardShortcut("k", modifiers: .command)
                .buttonStyle(.plain)
                .foregroundColor(.red)
                .controlSize(.regular)
                .accessibilityLabel("Clear all selected folders")
                .help("Remove all source and destination selections")
                
                Spacer()
                
                Button("Run Backup") {
                    backupManager.runBackup()
                }
                .keyboardShortcut("r", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(!backupManager.canRunBackup())
                .accessibilityLabel("Start backup process")
                .help("Begin copying files to selected destinations")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 600, idealWidth: 700, maxWidth: .infinity,
               minHeight: 450, idealHeight: 550, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            setupKeyboardShortcuts()
            setupMenuCommands()
            
            print("🔐 Using SHA-1 checksums for faster verification")
            
            // Check for first run
            checkFirstRun()
            
            // Check for updates
            updateManager.checkForUpdates()
        }
        .sheet(isPresented: $showWelcomePopup) {
            WelcomeView(isPresented: $showWelcomePopup)
        }
        .sheet(isPresented: $backupManager.showCompletionReport) {
            BackupCompletionView(statistics: backupManager.statistics)
        }
        .sheet(isPresented: $backupManager.showMigrationDialog) {
            if let firstPlan = backupManager.pendingMigrationPlans.first {
                MigrationConfirmationView(
                    plan: firstPlan,
                    destinationName: firstPlan.destinationURL.lastPathComponent,
                    isPresented: $backupManager.showMigrationDialog,
                    onMigrate: {
                        // Migration completed, continue backup
                        Task {
                            await backupManager.continueBackupAfterMigration()
                        }
                    },
                    onSkip: {
                        // Skip migration, continue backup
                        Task {
                            await backupManager.continueBackupAfterMigration()
                        }
                    }
                )
            }
        }
        .sheet(isPresented: $backupManager.showDuplicateWarning) {
            if let duplicateAnalyses = backupManager.duplicateAnalyses {
                DuplicateWarningView(
                    analyses: duplicateAnalyses,
                    onProceed: { skipExact, skipRenamed in
                        Task {
                            await backupManager.continueBackupAfterDuplicateDecision(
                                skipExact: skipExact,
                                skipRenamed: skipRenamed
                            )
                        }
                    },
                    onCancel: {
                        backupManager.cancelBackupFromDuplicateWarning()
                    }
                )
            }
        }
        .onDisappear {
            // Clean up event monitor when view disappears
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
                eventMonitor = nil
            }
        }
        // Override default Escape key behavior to prevent cancellation
        .onExitCommand {
            // Do nothing - prevent default cancelOperation behavior
            // Users must use the explicit Cancel button
        }
        .sheet(isPresented: $updateManager.showUpdateSheet) {
            UpdateStatusSheet(
                result: updateManager.updateCheckResult,
                currentVersion: updateManager.currentVersion,
                onDownload: { update in
                    Task {
                        await updateManager.downloadUpdate(update)
                    }
                },
                onSkipVersion: { version in
                    updateManager.skipVersion(version)
                },
                onCancel: {
                    updateManager.cancelDownload()
                }
            )
        }
        .sheet(isPresented: $showPurchaseView) {
            PurchaseProView()
                .frame(minWidth: 500, minHeight: 600)
        }
        .alert("Upgrade to Pro", isPresented: $showUpgradeAlert) {
            if !BuildConfiguration.isOpenSourceBuild {
                Button("View Pro Features") {
                    showPurchaseView = true
                }
            }
            Button("OK", role: .cancel) { }
        } message: {
            if BuildConfiguration.isOpenSourceBuild {
                Text("This feature is only available in the App Store version of ImageIntact.")
            } else {
                Text("This feature requires ImageIntact Pro. Unlock all premium features with a one-time purchase.")
            }
        }
    }
    
    // MARK: - Menu Commands
    func setupMenuCommands() {
        // Debug menu - Test Update Flow
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("TestUpdateFlow"),
            object: nil,
            queue: .main
        ) { _ in
            Task {
                await testUpdateFlow()
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SelectSourceFolder"),
            object: nil,
            queue: .main
        ) { _ in
            selectSourceFolder()
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SelectDestination1"),
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                if !backupManager.destinationURLs.isEmpty {
                    selectDestinationFolder(at: 0)
                }
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AddDestination"),
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                backupManager.addDestination()
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("RunBackup"),
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                if backupManager.canRunBackup() {
                    backupManager.runBackup()
                }
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ClearAll"),
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                backupManager.clearAllSelections()
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ShowDebugLog"),
            object: nil,
            queue: .main
        ) { _ in
            showDebugLog()
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ExportDebugLog"),
            object: nil,
            queue: .main
        ) { _ in
            exportDebugLog()
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ShowHelp"),
            object: nil,
            queue: .main
        ) { _ in
            HelpWindowManager.shared.showHelp()
        }
        
        // Also listen for the ImageIntact Help command
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ShowImageIntactHelp"),
            object: nil,
            queue: .main
        ) { _ in
            HelpWindowManager.shared.showHelp()
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("CheckForUpdates"),
            object: nil,
            queue: .main
        ) { _ in
            Task {
                await updateManager.performUpdateCheck(isManual: true)
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("VerifyCoreData"),
            object: nil,
            queue: .main
        ) { _ in
            verifyCoreDataStorage()
        }
        
        // Premium feature notifications
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ShowPurchaseView"),
            object: nil,
            queue: .main
        ) { _ in
            showPurchaseView = true
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ShowUpgradePrompt"),
            object: nil,
            queue: .main
        ) { _ in
            showUpgradeAlert = true
        }
    }
    
    // MARK: - Keyboard Shortcuts
    func setupKeyboardShortcuts() {
        // Remove any existing monitor first
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        
        // Add new monitor and store the reference
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Check if Command key is pressed
            if event.modifierFlags.contains(.command) {
                switch event.charactersIgnoringModifiers {
                case "1":
                    // Select source folder
                    selectSourceFolder()
                    return nil
                case "2":
                    // Select first destination
                    if !backupManager.destinationURLs.isEmpty {
                        selectDestinationFolder(at: 0)
                    }
                    return nil
                default:
                    break
                }
            }
            
            // Escape key handling - disabled during backup operations
            // The Escape key (keyCode 53) is intentionally not handled to prevent
            // accidental cancellation of backup operations. Users must use the
            // explicit Cancel button in the UI.
            
            return event
        }
    }
    
    // MARK: - UI Helper Methods
    func selectSourceFolder() {
        let dialog = NSOpenPanel()
        dialog.canChooseFiles = false
        dialog.canChooseDirectories = true
        dialog.allowsMultipleSelection = false

        if dialog.runModal() == .OK {
            if let url = dialog.url {
                backupManager.setSource(url)
            }
        }
    }
    
    func selectDestinationFolder(at index: Int) {
        guard index < backupManager.destinationURLs.count else { return }
        
        let dialog = NSOpenPanel()
        dialog.canChooseFiles = false
        dialog.canChooseDirectories = true
        dialog.allowsMultipleSelection = false

        if dialog.runModal() == .OK {
            if let url = dialog.url {
                backupManager.setDestination(url, at: index)
            }
        }
    }
    
    // MARK: - Debug Log Methods
    func showDebugLog() {
        // Get the current session ID from BackupManager
        let sessionID = backupManager.sessionID
        
        // Try to get report from Core Data if we have a session
        let eventLogger = EventLogger.shared
        let logContent: String
        
        if !sessionID.isEmpty {
            // Get report for current session
            logContent = eventLogger.generateReport(for: sessionID)
        } else {
            // Get all recent sessions and show the latest one
            let sessions = eventLogger.getAllSessions()
            if let latestSession = sessions.first,
               let sessionUUID = latestSession.id?.uuidString {
                logContent = eventLogger.generateReport(for: sessionUUID)
            } else {
                // No sessions found, generate a basic report
                logContent = generateCurrentSessionDebugLog()
            }
        }
        
        // Write to temporary file and open
        let tempDir = FileManager.default.temporaryDirectory
        let tempLogPath = tempDir.appendingPathComponent("ImageIntact_Session_\(sessionID.isEmpty ? "Latest" : sessionID).log")
        
        do {
            try logContent.write(to: tempLogPath, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(tempLogPath)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Cannot Show Debug Log"
            alert.informativeText = "Could not create temporary debug log: \(error.localizedDescription)"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
    
    func generateCurrentSessionDebugLog() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        
        var logContent = "ImageIntact Debug Log - \(timestamp)\n"
        logContent += "Session ID: \(backupManager.sessionID)\n"
        logContent += "Total Files: \(backupManager.totalFiles)\n"
        logContent += "Processed Files: \(backupManager.processedFiles)\n"
        logContent += "Failed Files: \(backupManager.failedFiles.count)\n"
        logContent += "Was Cancelled: \(backupManager.shouldCancel)\n\n"
        
        // Add detailed error information
        if !backupManager.failedFiles.isEmpty {
            logContent += "ERROR DETAILS:\n"
            for (index, failure) in backupManager.failedFiles.enumerated() {
                logContent += "\(index + 1). File: \(failure.file)\n"
                logContent += "   Destination: \(failure.destination)\n"
                logContent += "   Error: \(failure.error)\n\n"
            }
        }
        
        if !backupManager.debugLog.isEmpty {
            logContent += "Checksum Timings:\n"
            logContent += backupManager.debugLog.joined(separator: "\n")
        } else {
            logContent += "No timing data available yet.\n"
        }
        
        return logContent
    }
    
    func exportDebugLog() {
        // Get session data from Core Data
        let sessionID = backupManager.sessionID
        let eventLogger = EventLogger.shared
        var logContent: String
        var exportData: Data?
        
        if !sessionID.isEmpty {
            // Get report for current session
            logContent = eventLogger.generateReport(for: sessionID)
            exportData = eventLogger.exportJSON(for: sessionID)
        } else {
            // Get all recent sessions and show the latest one
            let sessions = eventLogger.getAllSessions()
            if let latestSession = sessions.first,
               let sessionUUID = latestSession.id?.uuidString {
                logContent = eventLogger.generateReport(for: sessionUUID)
                exportData = eventLogger.exportJSON(for: sessionUUID)
            } else {
                // No sessions found, generate a basic report
                logContent = generateCurrentSessionDebugLog()
            }
        }
        
        // Check if user wants to anonymize paths
        var shouldAnonymize = false
        if PreferencesManager.shared.anonymizePathsInExport {
            let alert = NSAlert()
            alert.messageText = "Export Debug Log"
            alert.informativeText = "Would you like to anonymize file paths in the exported log for privacy?\n\nThis will replace usernames and volume names with placeholders like [USER] and [VOLUME]."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Anonymize Paths")
            alert.addButton(withTitle: "Keep Original Paths")
            alert.addButton(withTitle: "Cancel")
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                shouldAnonymize = true
            } else if response == .alertThirdButtonReturn {
                return // User cancelled
            }
        }
        
        // Apply anonymization if requested
        if shouldAnonymize {
            logContent = PathAnonymizer.anonymizeInText(logContent)
            // For JSON, we need to parse, anonymize, and re-encode
            if let jsonData = exportData {
                if let jsonString = String(data: jsonData, encoding: .utf8) {
                    let anonymizedJson = PathAnonymizer.anonymizeInText(jsonString)
                    exportData = anonymizedJson.data(using: .utf8)
                }
            }
        }
        
        let savePanel = NSSavePanel()
        savePanel.title = "Export Debug Log"
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let suffix = shouldAnonymize ? "_anonymized" : ""
        savePanel.nameFieldStringValue = "ImageIntact_Debug_\(dateFormatter.string(from: Date()))\(suffix).txt"
        savePanel.allowedContentTypes = [.plainText, .json]
        savePanel.canCreateDirectories = true
        
        if savePanel.runModal() == .OK, let exportURL = savePanel.url {
            do {
                // Export as JSON if user selected .json extension
                if exportURL.pathExtension == "json", let jsonData = exportData {
                    try jsonData.write(to: exportURL)
                } else {
                    // Export as text
                    try logContent.write(to: exportURL, atomically: true, encoding: .utf8)
                }
                
                let alert = NSAlert()
                alert.messageText = "Debug Log Exported"
                alert.informativeText = "Debug log has been saved to:\n\n\(exportURL.path)"
                alert.alertStyle = .informational
                alert.addButton(withTitle: "OK")
                alert.runModal()
            } catch {
                let alert = NSAlert()
                alert.messageText = "Export Failed"
                alert.informativeText = "Could not export debug log: \(error.localizedDescription)"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }
    
    // MARK: - Test Update Flow
    func testUpdateFlow() async {
        print("🧪 Test Update Flow triggered")
        
        // Enable test mode temporarily if not already enabled
        let wasInTestMode = UpdateManager.testMode
        if !wasInTestMode {
            UpdateManager.testMode = true
            UpdateManager.mockVersion = "1.0.0"
            print("🧪 Temporarily enabled test mode with version 1.0.0")
        }
        
        // Trigger update check
        await updateManager.performUpdateCheck(isManual: true)
        
        // Restore previous test mode state after a delay
        if !wasInTestMode {
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                UpdateManager.testMode = false
                UpdateManager.mockVersion = nil
                print("🧪 Test mode disabled")
            }
        }
    }
    
    // MARK: - First Run
    func checkFirstRun() {
        let hasSeenWelcome = UserDefaults.standard.bool(forKey: "hasSeenWelcome")
        if !hasSeenWelcome {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.showWelcomePopup = true
                UserDefaults.standard.set(true, forKey: "hasSeenWelcome")
            }
        }
    }
    
    // MARK: - Helper Methods
    func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }
    
    // MARK: - Core Data Verification
    func verifyCoreDataStorage() {
        let report = EventLogger.shared.verifyDataStorage()
        
        // Write to temp file and open
        let tempDir = FileManager.default.temporaryDirectory
        let tempPath = tempDir.appendingPathComponent("CoreData_Verification.txt")
        
        do {
            try report.write(to: tempPath, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(tempPath)
        } catch {
            print("Failed to write verification report: \(error)")
        }
    }
}

// MARK: - Reusable FolderRow
struct FolderRow: View {
    let title: String
    @Binding var selectedURL: URL?
    let onClear: () -> Void
    var onSelect: ((URL) -> Void)? = nil
    var showRemoveButton: Bool = true
    
    var body: some View {
        HStack(spacing: 12) {
            Button(action: selectFolder) {
                HStack {
                    Image(systemName: selectedURL == nil ? "folder.badge.plus" : "folder.fill")
                        .foregroundColor(selectedURL == nil ? .secondary : .accentColor)
                    
                    Text(selectedURL?.lastPathComponent ?? title)
                        .foregroundColor(selectedURL == nil ? .secondary : .primary)
                    
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            
            // Always reserve space for the button to maintain consistent width
            if selectedURL != nil && showRemoveButton {
                Button("Remove") {
                    onClear()
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .font(.system(size: 11))
                .frame(width: 60)
            } else {
                // Invisible spacer to maintain width
                Color.clear
                    .frame(width: 60)
            }
        }
    }
    
    func selectFolder() {
        let dialog = NSOpenPanel()
        dialog.canChooseFiles = false
        dialog.canChooseDirectories = true
        dialog.allowsMultipleSelection = false

        if dialog.runModal() == .OK {
            if let url = dialog.url {
                selectedURL = url
                onSelect?(url)
            }
        }
    }
}