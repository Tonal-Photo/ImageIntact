import SwiftUI

struct MigrationConfirmationView: View {
    let plan: BackupMigrationDetector.MigrationPlan
    let destinationName: String
    @Binding var isPresented: Bool
    let onMigrate: () -> Void
    let onSkip: () -> Void
    
    @State private var isMigrating = false
    @State private var migrationProgress = 0
    @State private var migrationTotal = 0
    @State private var migrationComplete = false
    @State private var isNetworkDrive = false
    
    var body: some View {
        VStack(spacing: 20) {
            headerSection
            detailsSection
            explanationSection
            progressSection
            buttonsSection
        }
        .padding(24)
        .frame(width: 500)
        .onAppear {
            checkDriveType()
        }
    }
    
    private func checkDriveType() {
        if let driveInfo = DriveAnalyzer.analyzeDrive(at: plan.destinationURL) {
            isNetworkDrive = driveInfo.connectionType == .network
        }
    }
    
    private func performMigration() {
        isMigrating = true
        migrationTotal = plan.fileCount
        migrationProgress = 0
        
        Task {
            let detector = BackupMigrationDetector()
            
            do {
                try await detector.performMigration(plan: plan) { completed, total in
                    Task { @MainActor in
                        migrationProgress = completed
                        migrationTotal = total
                    }
                }
                
                await MainActor.run {
                    // Show completion state
                    migrationComplete = true
                    migrationProgress = migrationTotal
                    
                    // Wait a moment to show completion, then close
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        onMigrate()
                        isPresented = false
                    }
                }
            } catch {
                await MainActor.run {
                    // Show error
                    print("❌ Migration failed: \(error)")
                    isMigrating = false
                    
                    // Show error alert
                    let alert = NSAlert()
                    alert.messageText = "Migration Failed"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .critical
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
        }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    // MARK: - View Components
    
    private var explanationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("What will happen:", systemImage: "info.circle")
                .font(.subheadline)
                .fontWeight(.medium)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("• Files will be moved (not copied) to the organized folder")
                Text("• Each file will be verified after moving")
                Text("• Original files will no longer be in the root folder")
                Text("• This helps keep your backups organized by source")
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.leading, 20)
        }
    }
    
    @ViewBuilder
    private var progressSection: some View {
        if isMigrating || migrationComplete {
            VStack(spacing: 12) {
                if migrationComplete {
                    completionView
                } else {
                    activeProgressView
                }
            }
            .padding()
            .background(progressBackground)
            .transition(.opacity.combined(with: .scale))
        }
    }
    
    private var completionView: some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Organization complete!")
                    .font(.headline)
                    .foregroundColor(.green)
            }
            Text("\(migrationTotal) files organized successfully")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var activeProgressView: some View {
        VStack(spacing: 8) {
            HStack {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.8)
                Text("Organizing files...")
                    .font(.headline)
            }
            
            ProgressView(value: Double(migrationProgress), total: Double(max(migrationTotal, 1)))
                .progressViewStyle(.linear)
            
            progressDetailsRow
            
            if isNetworkDrive {
                Label("Network drive detected - this may take longer than usual", 
                      systemImage: "network")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }
    
    private var progressDetailsRow: some View {
        HStack {
            Text("Moving file \(migrationProgress) of \(migrationTotal)")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            if migrationProgress > 0 && migrationTotal > 0 {
                let percentage = Int((Double(migrationProgress) / Double(migrationTotal)) * 100)
                Text("\(percentage)%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var progressBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(migrationComplete ? Color.green.opacity(0.1) : Color.blue.opacity(0.1))
            .stroke(migrationComplete ? Color.green.opacity(0.3) : Color.blue.opacity(0.3), lineWidth: 1)
    }
    
    private var buttonsSection: some View {
        HStack(spacing: 12) {
            Button("Skip") {
                onSkip()
                isPresented = false
            }
            .buttonStyle(.plain)
            .disabled(isMigrating)
            
            Spacer()
            
            Button("Keep in Root") {
                isPresented = false
            }
            .disabled(isMigrating)
            
            Button(isMigrating ? "Organizing..." : "Organize Files") {
                if !isMigrating {
                    performMigration()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isMigrating)
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)
            
            Text("Organize Existing Backup?")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Found existing files that match your source")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DetailRow(
                icon: "doc.on.doc",
                label: "Files to organize:",
                value: "\(plan.fileCount) files"
            )
            
            DetailRow(
                icon: "arrow.up.arrow.down",
                label: "Total size:",
                value: formatBytes(plan.totalSize)
            )
            
            DetailRow(
                icon: "folder",
                label: "Move to folder:",
                value: plan.organizationFolder
            )
            
            DetailRow(
                icon: "externaldrive",
                label: "Destination:",
                value: destinationName
            )
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
}

struct DetailRow: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .frame(width: 20)
            
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.system(size: 12, weight: .medium))
        }
    }
}