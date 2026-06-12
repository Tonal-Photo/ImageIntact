import Foundation

// MARK: - Preflight Decision Dialogs + Continuations
//
// Split out of BackupManagerQueueIntegration.swift (gh#141, 500-line limit).
//
// The migration and duplicate preflight checks pause the run and present a
// decision sheet; the continuations below re-enter performQueueBasedBackup
// once the user answers. The re-entry arms that method's skip flags for the
// already-answered checks — the detectors have no decline-memory, so
// re-running an answered check re-presents the same sheet forever (gh#141).

extension BackupManager {
    // MARK: - Migration Support

    /// Check if migration is needed for organizing existing files.
    /// internal (not private): called from performQueueBasedBackup in
    /// BackupManagerQueueIntegration.swift.
    @MainActor
    func checkForMigration(source: URL, destinations: [URL], manifest: [FileManifestEntry])
        async
    {
        ApplicationLogger.shared.debug("Checking for migration opportunities", category: .backup)

        // Check for cancellation
        guard !state.shouldCancel else {
            ApplicationLogger.shared.debug("Migration check cancelled", category: .backup)
            return
        }

        state.pendingMigrationPlans.removeAll()

        // Start security-scoped access for source
        let sourceAccessGranted = source.startAccessingSecurityScopedResource()
        defer {
            if sourceAccessGranted {
                source.stopAccessingSecurityScopedResource()
            }
        }

        let detector = BackupMigrationDetector()

        // Check each destination for migration needs
        for (_, destination) in destinations.enumerated() {
            if let plan = await detector.checkForMigrationNeeded(
                source: source,
                destination: destination,
                organizationName: organizationName,
                manifest: manifest
            ) {
                ApplicationLogger.shared.debug("Migration needed for \(destination.lastPathComponent): \(plan.fileCount) files", category: .backup)
                state.pendingMigrationPlans.append(plan)
            }
        }

        // Show migration dialog if needed
        if !state.pendingMigrationPlans.isEmpty {
            showMigrationDialog = true
        }
    }

    /// Continue backup after migration decision.
    /// Re-enters with skipMigrationCheck armed: the user just answered the
    /// offer (Organize or Skip), and after Skip the org folder is still
    /// absent, so a re-run check would re-present the sheet (gh#141). The
    /// duplicate check still runs — that dialog has not been shown yet at
    /// this point in the chain.
    @MainActor
    func continueBackupAfterMigration() async {
        ApplicationLogger.shared.debug("Continuing backup after migration", category: .backup)
        showMigrationDialog = false
        state.pendingMigrationPlans.removeAll()

        // Re-run the backup now that migration is handled
        if let source = sourceURL {
            let destinations = destinationItems.compactMap { $0.url }
            await performQueueBasedBackup(
                source: source,
                destinations: destinations,
                skipMigrationCheck: true
            )
        } else {
            // Should be unreachable (the dialog was armed by a run that had
            // a source), but don't strand the just-dismissed dialog: land in
            // a clean idle state instead of silently dropping the decision.
            ApplicationLogger.shared.error(
                "Migration continuation found no source URL - returning to idle", category: .backup)
            state.isProcessing = false
            state.statusMessage = "Backup cancelled"
        }
    }

    // MARK: - Duplicate Support

    /// Check for duplicate files at destinations.
    /// internal (not private): called from performQueueBasedBackup in
    /// BackupManagerQueueIntegration.swift.
    @MainActor
    func checkForDuplicates(source _: URL, destinations: [URL], manifest: [FileManifestEntry])
        async
    {
        ApplicationLogger.shared.debug("Checking for duplicate files", category: .backup)

        // Check for cancellation
        guard !state.shouldCancel else {
            ApplicationLogger.shared.debug("Duplicate check cancelled", category: .backup)
            return
        }

        state.statusMessage = "Analyzing for duplicates..."

        // Perform duplicate analysis for all destinations
        let analyses = await duplicateDetector.preflightDuplicateCheck(
            manifest: manifest,
            destinations: destinations,
            organizationName: organizationName
        )

        // Check if any duplicates were found
        let totalDuplicates = analyses.values.reduce(0) { $0 + $1.totalDuplicates }

        if totalDuplicates > 0 {
            ApplicationLogger.shared.debug("Found \(totalDuplicates) duplicate files across destinations", category: .backup)
            state.duplicateAnalyses = analyses
            showDuplicateWarning = true
        } else {
            ApplicationLogger.shared.debug("No duplicates found", category: .backup)
            state.duplicateAnalyses = nil
            showDuplicateWarning = false
        }
    }

    /// Continue backup after duplicate handling decision.
    /// Re-enters with BOTH skip flags armed: the duplicate sheet only appears
    /// after the migration question is resolved, so a re-run migration check
    /// would re-present it (migration-skip → duplicate chain), and the
    /// analysis the user decided on is retained in state.duplicateAnalyses
    /// for the orchestrator (gh#141).
    @MainActor
    func continueBackupAfterDuplicateDecision(skipExact: Bool, skipRenamed: Bool) async {
        ApplicationLogger.shared.debug("Continuing backup with duplicate preferences", category: .backup)
        showDuplicateWarning = false
        state.skipExactDuplicates = skipExact
        state.skipRenamedDuplicates = skipRenamed

        // Re-run the backup now that duplicate handling is decided
        if let source = sourceURL {
            let destinations = destinationItems.compactMap { $0.url }
            await performQueueBasedBackup(
                source: source,
                destinations: destinations,
                skipMigrationCheck: true,
                skipDuplicateCheck: true
            )
        } else {
            // Should be unreachable (the dialog was armed by a run that had
            // a source), but don't strand the just-dismissed dialog: land in
            // a clean idle state instead of silently dropping the decision.
            ApplicationLogger.shared.error(
                "Duplicate continuation found no source URL - returning to idle", category: .backup)
            state.duplicateAnalyses = nil
            state.isProcessing = false
            state.statusMessage = "Backup cancelled"
        }
    }

    /// Cancel backup from duplicate warning
    @MainActor
    func cancelBackupFromDuplicateWarning() {
        ApplicationLogger.shared.debug("Backup cancelled by user from duplicate warning", category: .backup)
        showDuplicateWarning = false
        state.duplicateAnalyses = nil
        state.isProcessing = false
        state.statusMessage = "Backup cancelled"
    }
}
