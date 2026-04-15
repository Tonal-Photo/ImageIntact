//
//  GeneralPreferencesView.swift
//  ImageIntact
//
//  General tab of the Preferences window.
//

import SwiftUI

struct GeneralPreferencesView: View {
    @Bindable var preferences: PreferencesManager = .shared
    @State private var selectedSourceURL: URL?
    @State private var selectedDestinationURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Default Paths Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Default Paths")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)

                        VStack(spacing: 12) {
                            HStack(alignment: .center, spacing: 12) {
                                Text("Default Source:")
                                    .font(.system(size: 13))
                                    .frame(alignment: .leading)

                                Text(
                                    preferences.defaultSourcePath.isEmpty
                                        ? "Not set"
                                        : URL(fileURLWithPath: preferences.defaultSourcePath).lastPathComponent
                                )
                                .font(.system(size: 13))
                                .foregroundColor(preferences.defaultSourcePath.isEmpty ? .secondary : .primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(1)
                                .truncationMode(.middle)

                                Spacer()

                                Button("Choose...") {
                                    selectSourceFolder()
                                }
                                .controlSize(.small)

                                if !preferences.defaultSourcePath.isEmpty {
                                    Button("Clear") {
                                        preferences.defaultSourcePath = ""
                                    }
                                    .controlSize(.small)
                                }
                            }

                            HStack(alignment: .center, spacing: 12) {
                                Text("Default Destination:")
                                    .font(.system(size: 13))
                                    .frame(alignment: .leading)

                                Text(
                                    preferences.defaultDestinationPath.isEmpty
                                        ? "Not set"
                                        : URL(fileURLWithPath: preferences.defaultDestinationPath).lastPathComponent
                                )
                                .font(.system(size: 13))
                                .foregroundColor(preferences.defaultDestinationPath.isEmpty ? .secondary : .primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(1)
                                .truncationMode(.middle)

                                Spacer()

                                Button("Choose...") {
                                    selectDestinationFolder()
                                }
                                .controlSize(.small)

                                if !preferences.defaultDestinationPath.isEmpty {
                                    Button("Clear") {
                                        preferences.defaultDestinationPath = ""
                                    }
                                    .controlSize(.small)
                                }
                            }
                        }
                    }

                    Divider()
                        .padding(.vertical, 8)

                    // Startup Behavior Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Startup Behavior")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)

                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Check for updates automatically", isOn: .constant(true))
                                .font(.system(size: 13))
                                .disabled(true)
                                .help("Updates are checked every 24 hours")

                            Toggle("Restore last session paths on launch", isOn: $preferences.restoreLastSession)
                                .font(.system(size: 13))
                                .help("Automatically reload the source and destination folders from your last session")

                            Toggle("Show welcome screen on first launch", isOn: $preferences.showWelcomeOnLaunch)
                                .font(.system(size: 13))
                                .help("Display the welcome guide for new users")
                        }
                    }

                    Divider()
                        .padding(.vertical, 8)

                    // File Handling Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("File Handling")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)

                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Exclude cache files by default", isOn: $preferences.excludeCacheFiles)
                                .font(.system(size: 13))
                                .help("Skip Adobe cache files, Lightroom previews, .DS_Store, thumbnails, and other temporary files")

                            Toggle("Skip hidden files", isOn: $preferences.skipHiddenFiles)
                                .font(.system(size: 13))
                                .help("Ignore .DS_Store, ._* files, and other system files")

                            HStack(spacing: 6) {
                                Text("Default file type filter:")
                                    .font(.system(size: 13))

                                Picker("", selection: $preferences.defaultFileTypeFilter) {
                                    Text("All Files").tag("all")
                                    Text("Photos Only").tag("photos")
                                    Text("RAW Only").tag("raw")
                                    Text("Videos Only").tag("videos")
                                }
                                .pickerStyle(MenuPickerStyle())
                                .frame(width: 150)
                                .help("Default filter applied when starting a new backup")

                                Spacer()
                            }
                        }
                    }

                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 100)
                .padding(.top, 20)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    func selectSourceFolder() {
        let dialog = NSOpenPanel()
        dialog.canChooseFiles = false
        dialog.canChooseDirectories = true
        dialog.allowsMultipleSelection = false

        if dialog.runModal() == .OK {
            if let url = dialog.url {
                preferences.defaultSourcePath = url.path
            }
        }
    }

    func selectDestinationFolder() {
        let dialog = NSOpenPanel()
        dialog.canChooseFiles = false
        dialog.canChooseDirectories = true
        dialog.allowsMultipleSelection = false

        if dialog.runModal() == .OK {
            if let url = dialog.url {
                preferences.defaultDestinationPath = url.path
            }
        }
    }
}
