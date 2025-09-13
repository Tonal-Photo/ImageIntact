//
//  BugReportView.swift
//  ImageIntact
//
//  Bug reporting interface with PII sanitization
//

import SwiftUI
import AppKit

struct BugReportView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = BugReportViewModel()
    
    @State private var description = ""
    @State private var reproductionSteps = ""
    @State private var isRepeatable = "Sometimes"
    @State private var severity = "Minor"
    @State private var includeSystemInfo = true
    @State private var includeLogs = false
    @State private var showingSanitizationInfo = false
    @State private var showingSystemInfo = false
    @State private var showingPreview = false
    
    let severityOptions = ["Critical", "Major", "Minor", "Enhancement"]
    let repeatableOptions = ["Yes", "No", "Sometimes"]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Report a Bug")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
            }
            .padding()
            
            Divider()
            
            // Form
            Form {
                Section("Issue Details") {
                    // Description
                    VStack(alignment: .leading, spacing: 4) {
                        Text("What happened?")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextEditor(text: $description)
                            .frame(minHeight: 60)
                            .font(.system(size: 12))
                    }
                    
                    // Reproduction steps
                    VStack(alignment: .leading, spacing: 4) {
                        Text("How can we reproduce this? (optional)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextEditor(text: $reproductionSteps)
                            .frame(minHeight: 60)
                            .font(.system(size: 12))
                    }
                    
                    // Severity
                    Picker("Severity", selection: $severity) {
                        ForEach(severityOptions, id: \.self) { option in
                            HStack {
                                Image(systemName: severityIcon(for: option))
                                    .foregroundColor(severityColor(for: option))
                                Text(option)
                            }
                            .tag(option)
                        }
                    }
                    
                    // Repeatable
                    Picker("Is it repeatable?", selection: $isRepeatable) {
                        ForEach(repeatableOptions, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                
                Section("Include Information") {
                    // System info
                    HStack {
                        Toggle(isOn: $includeSystemInfo) {
                            HStack {
                                Text("System Information")
                                Button(action: { showingSystemInfo = true }) {
                                    Image(systemName: "info.circle")
                                        .foregroundColor(.accentColor)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                    
                    // Logs with consent
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Toggle(isOn: $includeLogs) {
                                HStack {
                                    Text("Sanitized Logs")
                                    Button(action: { showingSanitizationInfo = true }) {
                                        Image(systemName: "info.circle")
                                            .foregroundColor(.accentColor)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        }
                        
                        if includeLogs {
                            Label("I understand sanitized logs will be included", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            
            Divider()
            
            // Bottom buttons
            HStack {
                Button("Preview Report") {
                    showingPreview = true
                }
                .disabled(description.isEmpty)
                
                Spacer()
                
                Button("Generate Email") {
                    generateAndOpenEmail()
                }
                .buttonStyle(.borderedProminent)
                .disabled(description.isEmpty || (includeLogs && !viewModel.hasLogs))
            }
            .padding()
        }
        .frame(width: 600, height: 550)
        .onAppear {
            viewModel.loadSystemInfo()
            viewModel.checkForLogs()
        }
        .popover(isPresented: $showingSystemInfo) {
            SystemInfoPopover()
        }
        .popover(isPresented: $showingSanitizationInfo) {
            SanitizationInfoPopover()
        }
        .sheet(isPresented: $showingPreview) {
            BugReportPreview(
                report: generateReportText(),
                onSend: { generateAndOpenEmail() }
            )
        }
    }
    
    private func severityIcon(for severity: String) -> String {
        switch severity {
        case "Critical": return "exclamationmark.circle.fill"
        case "Major": return "exclamationmark.triangle.fill"
        case "Minor": return "exclamationmark.circle"
        default: return "lightbulb"
        }
    }
    
    private func severityColor(for severity: String) -> Color {
        switch severity {
        case "Critical": return .red
        case "Major": return .orange
        case "Minor": return .yellow
        default: return .blue
        }
    }
    
    private func generateReportText() -> String {
        var report = """
        === BUG REPORT ===
        Severity: \(severity)
        Date: \(Date().formatted())
        Version: \(viewModel.appVersion)
        System: \(viewModel.systemInfo)
        
        DESCRIPTION:
        \(description)
        
        """
        
        if !reproductionSteps.isEmpty {
            report += """
            STEPS TO REPRODUCE:
            \(reproductionSteps)
            
            """
        }
        
        report += "REPEATABLE: \(isRepeatable)\n\n"
        
        if includeLogs {
            report += """
            === SANITIZED LOGS ===
            \(viewModel.getSanitizedLogs())
            
            """
        }
        
        return report
    }
    
    private func generateAndOpenEmail() {
        let subject = "[\(severity)] Bug Report: \(String(description.prefix(50))) - \(viewModel.appVersion) on \(viewModel.osVersion)"
        let body = generateReportText()
        
        // Create mailto URL
        let to = "bugs@tonalphoto.com"
        
        // URL encode the components
        guard let subjectEncoded = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let bodyEncoded = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "mailto:\(to)?subject=\(subjectEncoded)&body=\(bodyEncoded)") else {
            return
        }
        
        NSWorkspace.shared.open(url)
        dismiss()
    }
}

// MARK: - System Info Popover

struct SystemInfoPopover: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("System Information")
                .font(.headline)
            
            Text("The following information helps us reproduce issues:")
                .font(.caption)
            
            VStack(alignment: .leading, spacing: 4) {
                Label("macOS version (e.g., 14.2)", systemImage: "desktopcomputer")
                Label("ImageIntact version (e.g., 1.2.7)", systemImage: "app")
                Label("Processor type (e.g., Apple M1 Pro)", systemImage: "cpu")
            }
            .font(.caption)
            .foregroundColor(.secondary)
            
            HStack {
                Spacer()
                Button("OK") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 350)
    }
}

// MARK: - Sanitization Info Popover

struct SanitizationInfoPopover: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Log Sanitization")
                .font(.headline)
            
            Text("We remove Personally Identifiable Information (PII) from logs:")
                .font(.caption)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("• Usernames:")
                    Text("/Users/john → /Users/[USER]")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.blue)
                }
                
                HStack {
                    Text("• Filenames:")
                    Text("IMG_1234.jpg → [FILENAME].jpg")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.blue)
                }
                
                HStack {
                    Text("• Volumes:")
                    Text("MyBackup → [VOLUME]")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.blue)
                }
                
                Text("• Email addresses → [EMAIL]")
                Text("• Network addresses → [NETWORK]")
            }
            .font(.caption)
            .foregroundColor(.secondary)
            
            Text("File types, counts, timestamps, and error messages are preserved.")
                .font(.caption)
                .italic()
            
            HStack {
                Spacer()
                Button("OK") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 400)
    }
}

// MARK: - Bug Report Preview

struct BugReportPreview: View {
    let report: String
    let onSend: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Preview Bug Report")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
            }
            .padding()
            
            Divider()
            
            ScrollView {
                Text(report)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(NSColor.textBackgroundColor))
            
            Divider()
            
            HStack {
                Text("This is what will be sent in the email")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button("Back") {
                    dismiss()
                }
                
                Button("Generate Email") {
                    onSend()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 700, height: 600)
    }
}

// MARK: - View Model

@MainActor
class BugReportViewModel: ObservableObject {
    @Published var hasLogs = false
    @Published var appVersion = ""
    @Published var osVersion = ""
    @Published var systemInfo = ""
    
    private let sanitizer = PIISanitizer()
    
    func loadSystemInfo() {
        // App version
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
           let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
            appVersion = "v\(version) (\(build))"
        }
        
        // OS version
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        self.osVersion = "macOS \(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"
        
        // Processor info
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
        
        // Combine system info
        self.systemInfo = "\(self.osVersion) (\(machine))"
    }
    
    func checkForLogs() {
        // Check if we have recent logs in Core Data
        let logger = ApplicationLogger.shared
        hasLogs = logger.hasRecentLogs()
    }
    
    func getSanitizedLogs() -> String {
        let logger = ApplicationLogger.shared
        let recentLogs = logger.getRecentLogs(hours: 24)
        
        // Sanitize the logs
        let sanitized = sanitizer.sanitize(recentLogs)
        return sanitized
    }
}

// MARK: - ApplicationLogger Extension

extension ApplicationLogger {
    func hasRecentLogs() -> Bool {
        // Check if we have logs from the last 24 hours
        let yesterday = Date().addingTimeInterval(-86400)
        let logs = fetchLogs(since: yesterday, limit: 1)
        return !logs.isEmpty
    }
    
    func getRecentLogs(hours: Int) -> String {
        let cutoff = Date().addingTimeInterval(-Double(hours * 3600))
        let logs = fetchLogs(since: cutoff, limit: 10000)
        return logs.map { $0.formattedMessage }.joined(separator: "\n")
    }
}