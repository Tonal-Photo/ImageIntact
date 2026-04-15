//
//  LoggingPreferencesView.swift
//  ImageIntact
//
//  Logging & Privacy tab of the Preferences window.
//

import SwiftUI

struct LoggingPreferencesView: View {
    @Bindable var preferences: PreferencesManager = .shared
    @ObservedObject private var debugSettings = DebugSettings.shared
    @State private var showClearConfirmation = false
    @State private var showPrivacyExplanation = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Operational Logs Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Operational Logs")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)

                        Text("Debug and error logs for troubleshooting")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 12) {
                                Text("Minimum log level:")
                                    .font(.system(size: 13))
                                    .frame(width: 160, alignment: .trailing)

                                Picker("", selection: $preferences.minimumLogLevel) {
                                    Text("Debug").tag(0)
                                    Text("Info").tag(1)
                                    Text("Warning").tag(2)
                                    Text("Error").tag(3)
                                    Text("Critical").tag(4)
                                }
                                .pickerStyle(MenuPickerStyle())
                                .frame(width: 120)

                                Spacer()
                            }

                            Toggle("Log to Console.app", isOn: $preferences.enableConsoleLogging)
                                .font(.system(size: 13))
                                .help("Send logs to macOS Console for debugging")

                            Toggle("Enable debug menu items", isOn: $preferences.enableDebugMenu)
                                .font(.system(size: 13))
                                .help("Show additional debugging options in menus")

                            Divider()
                                .padding(.vertical, 8)

                            VStack(alignment: .leading, spacing: 4) {
                                Toggle("Verbose Logging", isOn: $debugSettings.verboseLogging)
                                    .font(.system(size: 13))
                                    .help("Show all debug messages. Resets when app quits.")

                                Text("Enables detailed diagnostic output for troubleshooting. This setting is not saved and will reset when ImageIntact quits.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            HStack(spacing: 12) {
                                Text("Keep operational logs for:")
                                    .font(.system(size: 13))
                                    .frame(width: 160, alignment: .trailing)

                                Picker("", selection: $preferences.operationalLogRetention) {
                                    Text("7 days").tag(7)
                                    Text("14 days").tag(14)
                                    Text("30 days").tag(30)
                                    Text("60 days").tag(60)
                                }
                                .pickerStyle(MenuPickerStyle())
                                .frame(width: 100)

                                Spacer()
                            }
                        }
                    }

                    Divider()
                        .padding(.vertical, 8)

                    // Backup History Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Backup History")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)

                        Text("ImageIntact maintains a local, private record of all your backups on this Mac to help you locate files in the future. This data never leaves your computer.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 12) {
                                Button("View Backup History...") {
                                    logInfo("Backup History viewer - planned for future release")
                                }
                                .controlSize(.small)
                                .disabled(true)
                                .help("View detailed history of all backups (coming soon)")

                                Button("Export Backup Catalog...") {
                                    logInfo("Catalog export - planned for future release")
                                }
                                .controlSize(.small)
                                .disabled(true)
                                .help("Export a catalog of all backed up files (coming soon)")
                            }

                            HStack(spacing: 8) {
                                Text("Storage location:")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Text("~/Library/Application Support/ImageIntact/")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    Divider()
                        .padding(.vertical, 8)

                    // Privacy Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Privacy")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)

                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top, spacing: 8) {
                                Toggle("Anonymize paths when exporting logs", isOn: $preferences.anonymizePathsInExport)
                                    .font(.system(size: 13))
                                    .help("Replace usernames and volume names with placeholders in exported logs")

                                Button(action: {
                                    showPrivacyExplanation = true
                                }) {
                                    Image(systemName: "questionmark.circle")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 12))
                                }
                                .buttonStyle(.plain)
                                .help("Learn about path anonymization")
                            }

                            if preferences.anonymizePathsInExport {
                                Text("Example: /Users/yourname/Pictures → /Users/[USER]/Pictures")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .padding(.leading, 20)
                            }

                            Button("Clear Operational Logs") {
                                showClearConfirmation = true
                            }
                            .controlSize(.small)
                            .help("Remove debug logs while keeping backup history")
                        }
                    }

                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 100)
                .padding(.top, 20)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .alert("Clear Operational Logs?", isPresented: $showClearConfirmation) {
            Button("Clear", role: .destructive) {
                ApplicationLogger.shared.cleanupOldLogs(daysToKeep: 0)
                logInfo("Operational logs cleared by user")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all debug and error logs. Your backup history will be preserved.")
        }
        .sheet(isPresented: $showPrivacyExplanation) {
            PrivacyExplanationView()
        }
    }
}
