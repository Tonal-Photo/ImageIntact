//
//  BackupState.swift
//  ImageIntact
//
//  Owns the transient per-run backup state extracted from BackupManager
//  (AMUX-201, #103 decomposition). BackupManager owns one instance via
//  `let state = BackupState()`; views and tests reach these through
//  `bm.state.X`. Mirrors the prior BookmarkManager/SourceManager/
//  DestinationManager extractions.
//
//  Grouped by concern: run state, modal-presentation flags, migration,
//  duplicate handling, trash, and large-backup confirmation.
//
//  The `state` reference is `let` for now; AMUX-206 (ProgressTracker
//  re-entrancy) decides whether mid-session swaps require `var`.
//

import Foundation

@MainActor
@Observable
final class BackupState {

    // MARK: - Nested types (moved from BackupManager)

    struct LogEntry {
        let timestamp: Date
        let sessionID: String
        let action: String
        let source: String
        let destination: String
        let checksum: String
        let algorithm: String
        let fileSize: Int64
        let reason: String
    }

    struct LargeBackupInfo {
        let fileCount: Int
        let totalBytes: Int64
        let destinationCount: Int
        let estimatedTimePerDestination: String
    }

    // MARK: - Run state

    var isProcessing = false
    var statusMessage = ""
    var failedFiles: [(file: String, destination: String, error: String)] = []
    var sessionID = UUID().uuidString
    var shouldCancel = false
    var debugLog: [String] = []
    var overallStatusText: String = ""  // e.g. "1 copying, 1 verifying"
    var currentPhase: BackupPhase = .idle
    var logEntries: [LogEntry] = []
    var currentOrchestrator: BackupOrchestrating?

    // MARK: - Modal-presentation flags

    var showCompletionReport = false
    var showMigrationDialog = false
    var showDuplicateWarning = false
    var showTrashConfirmation = false
    var showLargeBackupConfirmation = false

    // MARK: - Migration state

    var pendingMigrationPlans: [BackupMigrationDetector.MigrationPlan] = []

    // MARK: - Duplicate-handling state

    var duplicateAnalyses: [URL: DuplicateDetector.DuplicateAnalysis]?
    var skipExactDuplicates = true
    var skipRenamedDuplicates = false

    // MARK: - Trash state

    var trashSourceResult: String? = nil

    // MARK: - Large-backup confirmation state

    var largeBackupInfo: LargeBackupInfo?
    var largeBackupContinuation: CheckedContinuation<Bool, Never>?
}
