//
//  AdvancedPreferencesView.swift
//  ImageIntact
//
//  Advanced tab of the Preferences window.
//

import SwiftUI

struct AdvancedPreferencesView: View {
    @Bindable var preferences: PreferencesManager = .shared

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Experimental Features Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Experimental Features")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)

                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Enable smart duplicate detection", isOn: $preferences.enableSmartDuplicateDetection)
                                .font(.system(size: 13))
                                .help("Detect and skip files that are already backed up at destinations using checksums")

                            Toggle("Show technical details during backup", isOn: $preferences.showTechnicalDetails)
                                .font(.system(size: 13))
                                .help("Display additional technical information in the progress view")
                        }
                    }

                    Divider()
                        .padding(.vertical, 8)

                    // Safety Confirmations Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Safety Confirmations")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)

                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Confirm before large backups", isOn: $preferences.confirmLargeBackups)
                                .font(.system(size: 13))
                                .help("Ask for confirmation before starting backups over the threshold")

                            HStack(spacing: 12) {
                                Text("File count threshold:")
                                    .font(.system(size: 13))
                                    .frame(width: 160, alignment: .trailing)

                                TextField("", value: $preferences.largeBackupFileThreshold, format: .number)
                                    .frame(width: 80)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .disabled(!preferences.confirmLargeBackups)

                                Text("files")
                                    .font(.system(size: 13))

                                Spacer()
                            }

                            HStack(spacing: 12) {
                                Text("Size threshold:")
                                    .font(.system(size: 13))
                                    .frame(width: 160, alignment: .trailing)

                                TextField("", value: $preferences.largeBackupSizeThresholdGB, format: .number)
                                    .frame(width: 80)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .disabled(!preferences.confirmLargeBackups)

                                Text("GB")
                                    .font(.system(size: 13))

                                Spacer()
                            }

                            Toggle("Show summary before starting backup", isOn: $preferences.showPreflightSummary)
                                .font(.system(size: 13))
                                .help("Display a summary of what will be backed up before starting. You can also toggle this directly from the summary dialog.")

                            if preferences.skipLargeBackupWarning {
                                HStack(spacing: 8) {
                                    Text("Note: You've disabled large backup warnings")
                                        .font(.system(size: 12))
                                        .foregroundColor(.orange)

                                    Button("Re-enable") {
                                        preferences.skipLargeBackupWarning = false
                                    }
                                    .controlSize(.small)
                                }
                                .padding(.leading, 20)
                            }
                        }
                    }

                    Spacer(minLength: 20)

                    Divider()
                        .padding(.vertical, 8)

                    HStack {
                        Spacer()
                        Button("Reset to Defaults") {
                            preferences.resetToDefaults()
                        }
                        .controlSize(.regular)
                    }
                }
                .padding(.horizontal, 100)
                .padding(.top, 20)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}
