import Foundation

// MARK: - UI Test Support
//
// Split out of BackupManager.swift (AMUX-230, 500-line limit).

extension BackupManager {
    /// `internal` (not `private`) only because extensions in a separate file
    /// can't see private members; treat as init-only (called from init when
    /// launched with --uitest).
    func loadUITestPaths() {
        // The TestSourcePath / TestOrganizationName UserDefaults overrides are
        // for UI testing only. Wrap in #if DEBUG so a malicious local process
        // can't `defaults write` an arbitrary path into a Full-Disk-Access-
        // granted release build to coerce the app into reading protected files.
        #if DEBUG
        logInfo("Loading UI test paths")

        // Load test source path
        if let testSourcePath = UserDefaults.standard.string(forKey: "TestSourcePath") {
            let sourceURL = URL(fileURLWithPath: testSourcePath)
            self.sourceManager.sourceURL = sourceURL
            organizationName = SmartFolderName.from(url: sourceURL)
            logInfo("UI Test: Set source to \(testSourcePath)")
        }

        destinationManager.loadUITestDestinations()

        // Load test organization name if provided
        if let testOrgName = UserDefaults.standard.string(forKey: "TestOrganizationName") {
            organizationName = testOrgName
            logInfo("UI Test: Set organization name to \(testOrgName)")
        }

        // Clear source test values (destination keys cleared by DestinationManager)
        UserDefaults.standard.removeObject(forKey: "TestSourcePath")
        UserDefaults.standard.removeObject(forKey: "TestOrganizationName")
        #else
        // Release builds: never honor UI-test UserDefaults overrides.
        destinationManager.initializeEmpty()
        #endif
    }
}
