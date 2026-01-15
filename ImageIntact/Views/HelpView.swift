import SwiftUI

// Help view
struct HelpView: View {
    @Binding var isPresented: Bool
    var scrollToSection: String?

    init(isPresented: Binding<Bool> = .constant(true), scrollToSection: String? = nil) {
        _isPresented = isPresented
        self.scrollToSection = scrollToSection
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("ImageIntact Help")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Spacer()

                Button("Close") {
                    isPresented = false
                }
                .keyboardShortcut(.escape)
            }
            .padding(20)

            Divider()

            // Content
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // What's New
                        HelpSection(title: "What's New in v1.3.1") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("• **Subdirectory Control** - Choose whether to scan nested folders")
                                Text("• **Test Suite Improvements** - Better test isolation and stability")
                                Text("• **Code Quality** - Refactored architecture with improved separation of concerns")
                            }
                            .font(.subheadline)
                        }

                        HelpSection(title: "Recent Features (v1.2.7)") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("• **Smart Backup Organization** - Automatically organize files in folders")
                                Text("• **Backup Presets** - Save and restore backup configurations")
                                Text("• **Sleep Prevention** - Mac stays awake during backups")
                                Text("• **Completion Notifications** - Get notified when backup finishes")
                                Text("• **Smart Drive Detection** - Warnings for memory cards")
                            }
                            .font(.subheadline)
                        }

                        HelpSection(title: "Recent Features (v1.2)") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("• **Independent destinations** - Each runs at full speed")
                                Text("• **Real-time ETA** - See time remaining per destination")
                                Text("• **Automatic updates** - Daily checks for new versions")
                                Text("• **Better progress** - Per-destination tracking")
                                Text("• **Adaptive performance** - 1-8 workers per destination")
                            }
                            .font(.subheadline)
                        }

                        // Getting Started
                        HelpSection(title: "Getting Started") {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(
                                    "ImageIntact is designed to safely backup your photos to multiple destinations with verification."
                                )

                                Text("**Basic workflow:**")
                                    .fontWeight(.medium)

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("1. **Select Source**: Choose the folder containing your photos")
                                    Text("2. **Add Destinations**: Select up to 4 backup locations")
                                    Text("3. **Run Backup**: Click the backup button to start")
                                    Text("4. **Monitor Progress**: Watch real-time progress for each destination")
                                }
                                .font(.subheadline)
                            }
                        }

                        // Smart Backup Organization
                        HelpSection(title: "Smart Backup Organization") {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("ImageIntact can organize your backups into a structured folder:")

                                VStack(alignment: .leading, spacing: 8) {
                                    HelpPoint(
                                        title: "Organization Folder",
                                        description:
                                        "Files are organized into a folder you specify (e.g., 'Photos 2025')"
                                    )

                                    HelpPoint(
                                        title: "Automatic Migration",
                                        description:
                                        "Existing loose files are automatically moved into the organized folder"
                                    )

                                    HelpPoint(
                                        title: "Smart Detection",
                                        description:
                                        "Recognizes files that were previously backed up without organization"
                                    )

                                    HelpPoint(
                                        title: "Safe Migration",
                                        description: "Files are moved, not copied, to save time and disk space"
                                    )
                                }

                                Text("**How it works:**")
                                    .fontWeight(.medium)

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("1. Enter a folder name (defaults to your source folder name)")
                                    Text("2. Files are copied to: Destination → Organization Folder → Files")
                                    Text("3. Existing files outside the folder are migrated automatically")
                                }
                                .font(.caption)
                            }
                        }

                        // Backup Presets
                        HelpSection(title: "Backup Presets") {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Save time by creating presets for common backup scenarios:")

                                VStack(alignment: .leading, spacing: 8) {
                                    HelpPoint(
                                        title: "Built-in Presets",
                                        description: "Choose from Daily Workflow, Client Shoot, or Archive presets"
                                    )

                                    HelpPoint(
                                        title: "Custom Presets",
                                        description: "Save your current configuration as a reusable preset"
                                    )

                                    HelpPoint(
                                        title: "Complete Configuration",
                                        description: "Presets save source, destinations, filters, and all settings"
                                    )

                                    HelpPoint(
                                        title: "Quick Apply",
                                        description: "Select a preset to instantly configure your backup"
                                    )
                                }

                                Text("**Creating a preset:**")
                                    .fontWeight(.medium)

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("1. Configure your backup (source, destinations, filters)")
                                    Text("2. Click 'Save as Preset' under the source field")
                                    Text("3. Name your preset and choose an icon")
                                    Text("4. Apply it anytime from the Presets menu")
                                }
                                .font(.caption)
                            }
                        }

                        // Safety Features
                        HelpSection(title: "Safety Features") {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("ImageIntact prioritizes data safety above all else:")

                                VStack(alignment: .leading, spacing: 8) {
                                    HelpPoint(
                                        title: "Never Deletes Files",
                                        description: "Files are never deleted from any destination"
                                    )

                                    HelpPoint(
                                        title: "Checksum Verification",
                                        description:
                                        "Every file is verified with SHA-256 checksums to ensure perfect copies"
                                    )

                                    HelpPoint(
                                        title: "Smart Quarantine",
                                        description:
                                        "If a file exists with different content, it's moved to a quarantine folder before copying the new version"
                                    )

                                    HelpPoint(
                                        title: "Source Protection",
                                        description:
                                        "Source folders are tagged to prevent accidental selection as destinations"
                                    )
                                }
                            }
                        }

                        // File Type Support
                        HelpSection(title: "File Type Support") {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("ImageIntact intelligently filters and backs up photography-related files:")

                                VStack(alignment: .leading, spacing: 8) {
                                    HelpPoint(
                                        title: "30+ RAW Formats",
                                        description: "Supports RAW files from all major camera manufacturers"
                                    )

                                    HelpPoint(
                                        title: "Video Files",
                                        description: "Backs up MOV, MP4, AVI and other video formats"
                                    )

                                    HelpPoint(
                                        title: "Sidecar Files",
                                        description: "Preserves XMP, AAE and other metadata sidecar files"
                                    )

                                    HelpPoint(
                                        title: "Smart Cache Exclusion",
                                        description: "Automatically skips Lightroom and Capture One preview caches"
                                    )

                                    HelpPoint(
                                        title: "Symbolic Links",
                                        description:
                                        "Symbolic links (aliases) are skipped for security - only actual files are backed up"
                                    )

                                    HelpPoint(
                                        title: "Subdirectory Control",
                                        description:
                                        "Toggle 'Include subdirectories' to scan only the top-level folder or all nested folders"
                                    )
                                }
                            }
                        }

                        // Privacy and Security
                        HelpSection(title: "Privacy & Security", id: "privacy") {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("ImageIntact protects your privacy and data:")

                                VStack(alignment: .leading, spacing: 8) {
                                    HelpPoint(
                                        title: "Path Anonymization",
                                        description: "Automatically removes personal information from exported logs"
                                    )

                                    HelpPoint(
                                        title: "Local Processing Only",
                                        description:
                                        "All operations happen on your Mac - no cloud services or internet required"
                                    )

                                    HelpPoint(
                                        title: "Backup History",
                                        description: "Your backup records stay on your Mac and are never shared"
                                    )

                                    HelpPoint(
                                        title: "Secure Verification",
                                        description: "Uses SHA-256 checksums to ensure data integrity"
                                    )
                                }

                                GroupBox {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("About Path Anonymization")
                                            .font(.caption)
                                            .fontWeight(.semibold)

                                        Text(
                                            "When you export diagnostic logs, ImageIntact can automatically replace sensitive information like usernames and drive names with generic placeholders. This protects your privacy when sharing logs for support."
                                        )
                                        .font(.caption2)
                                        .foregroundColor(.secondary)

                                        HStack(spacing: 8) {
                                            Text("Example:")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)

                                            Text("/Users/john → /Users/[USER]")
                                                .font(.system(size: 10, design: .monospaced))
                                                .foregroundColor(.accentColor)
                                        }
                                    }
                                    .padding(8)
                                }
                            }
                        }

                        // Notifications & System Integration
                        HelpSection(title: "Notifications & System Integration") {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("ImageIntact integrates seamlessly with macOS:")

                                VStack(alignment: .leading, spacing: 8) {
                                    HelpPoint(
                                        title: "Sleep Prevention",
                                        description:
                                        "Your Mac stays awake during backups (can be disabled in Preferences)"
                                    )

                                    HelpPoint(
                                        title: "Completion Notifications",
                                        description: "Get notified when backups complete, even if app is in background"
                                    )

                                    HelpPoint(
                                        title: "Smart Drive Detection",
                                        description: "Warns when selecting memory cards as destinations"
                                    )

                                    HelpPoint(
                                        title: "Drive Type Recognition",
                                        description: "Identifies SSDs, HDDs, network drives, and memory cards"
                                    )
                                }

                                Text("**Configuring notifications:**")
                                    .fontWeight(.medium)

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("• Enable in Preferences → Show notification on complete")
                                    Text("• Works with macOS Focus modes and Do Not Disturb")
                                    Text("• Click notification to jump to ImageIntact")
                                }
                                .font(.caption)
                            }
                        }

                        // Performance
                        HelpSection(title: "Performance (v1.2)") {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("ImageIntact automatically optimizes performance based on your destinations:")

                                VStack(alignment: .leading, spacing: 8) {
                                    HelpPoint(
                                        title: "Independent Destinations",
                                        description:
                                        "Each destination runs at full speed - fast SSDs don't wait for slow network drives"
                                    )

                                    HelpPoint(
                                        title: "Queue-Based System",
                                        description: "Smart task scheduling with 1-8 adaptive workers per destination"
                                    )

                                    HelpPoint(
                                        title: "Real-time ETA",
                                        description: "See estimated time remaining for each destination"
                                    )

                                    HelpPoint(
                                        title: "SHA-256 Checksums",
                                        description: "Cryptographically secure verification using native Swift"
                                    )
                                }
                            }
                        }

                        // Automatic Updates
                        HelpSection(title: "Automatic Updates (v1.2)") {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("ImageIntact can automatically check for updates:")

                                VStack(alignment: .leading, spacing: 8) {
                                    HelpPoint(
                                        title: "Daily Checks",
                                        description: "Automatically checks once per day on launch"
                                    )

                                    HelpPoint(
                                        title: "Manual Check",
                                        description: "Use ImageIntact menu → Check for Updates"
                                    )

                                    HelpPoint(
                                        title: "Safe Downloads",
                                        description: "Downloads to your Downloads folder with progress tracking"
                                    )

                                    HelpPoint(
                                        title: "Version Skipping",
                                        description: "You can skip specific versions if desired"
                                    )
                                }
                            }
                        }

                        // Keyboard Shortcuts
                        HelpSection(title: "Keyboard Shortcuts") {
                            VStack(alignment: .leading, spacing: 8) {
                                HelpShortcut(key: "⌘1", action: "Select source folder")
                                HelpShortcut(key: "⌘2", action: "Select first destination")
                                HelpShortcut(key: "⌘+", action: "Add destination")
                                HelpShortcut(key: "⌘R", action: "Run backup")
                                HelpShortcut(key: "⌘K", action: "Clear all selections")
                                HelpShortcut(key: "⌘?", action: "Show this help")
                            }
                        }

                        // User Manual - Step by Step Guides
                        HelpSection(title: "User Manual - Common Tasks") {
                            VStack(alignment: .leading, spacing: 16) {
                                // First Time Setup
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("**First Time Setup**")
                                        .fontWeight(.semibold)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("1. Open Preferences (⌘,) and configure:")
                                        Text("   • Enable 'Restore last session on launch' for convenience")
                                        Text("   • Set 'Show notification on complete' if desired")
                                        Text("   • Choose your default file type filter")
                                        Text("2. Select your main photo folder as Source")
                                        Text("3. Add your backup drives as Destinations")
                                        Text("4. Save this configuration as a preset for easy reuse")
                                    }
                                    .font(.caption)
                                }

                                // Daily Backup Workflow
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("**Daily Photo Backup**")
                                        .fontWeight(.semibold)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("1. Connect your backup drive(s)")
                                        Text("2. Launch ImageIntact")
                                        Text("3. Select your preset or configure manually:")
                                        Text("   • Choose source folder (e.g., today's shoot)")
                                        Text("   • Select destination drive(s)")
                                        Text("   • Set organization folder name (e.g., '2025-08-26 Wedding')")
                                        Text("4. Click 'Run Backup' (⌘R)")
                                        Text("5. Monitor progress - each destination runs independently")
                                        Text("6. Wait for completion notification")
                                    }
                                    .font(.caption)
                                }

                                // Memory Card Import
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("**Importing from Memory Cards**")
                                        .fontWeight(.semibold)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("1. Insert memory card")
                                        Text("2. Select card as Source (usually /Volumes/CARD_NAME)")
                                        Text("3. Select your photo storage drive as Destination")
                                        Text("4. Enable organization with descriptive folder name")
                                        Text("5. Consider filtering by date if card has old photos")
                                        Text("6. Run backup")
                                        Text("⚠️ Never select a memory card as destination!")
                                    }
                                    .font(.caption)
                                    .foregroundColor(Color.primary.opacity(0.9))
                                }

                                // Multi-Destination Backup
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("**Backing Up to Multiple Drives**")
                                        .fontWeight(.semibold)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("1. Add up to 4 destinations with the + button")
                                        Text("2. Mix drive types freely (SSD, HDD, Network)")
                                        Text("3. Each destination gets its own:")
                                        Text("   • Progress bar and ETA")
                                        Text("   • Worker threads (1-8 adaptive)")
                                        Text("   • Independent speed")
                                        Text("4. Fast SSDs won't wait for slow network drives")
                                        Text("5. If one fails, others continue")
                                    }
                                    .font(.caption)
                                }
                            }
                        }

                        // FAQ
                        HelpSection(title: "Frequently Asked Questions", id: "faq") {
                            VStack(alignment: .leading, spacing: 12) {
                                HelpPoint(
                                    title: "Why aren't all my files being copied?",
                                    description:
                                    "ImageIntact only backs up image, video, and sidecar files. System files, caches, and symbolic links are skipped."
                                )

                                HelpPoint(
                                    title: "What are symbolic links?",
                                    description:
                                    "Symbolic links (also called symlinks or aliases) are shortcuts that point to files in other locations. For security, ImageIntact backs up the actual files, not the shortcuts."
                                )

                                HelpPoint(
                                    title: "Why does my backup seem stuck?",
                                    description:
                                    "Large RAW files and network drives can take time. Check the progress bars for each destination - they update independently."
                                )

                                HelpPoint(
                                    title: "Can I backup to the same drive twice?",
                                    description:
                                    "Yes, but each destination must be a different folder. This is useful for creating multiple organized copies."
                                )

                                HelpPoint(
                                    title: "What happens if a backup is interrupted?",
                                    description:
                                    "ImageIntact will skip already-copied files on the next run. Your data is always safe."
                                )
                            }
                        }

                        // Troubleshooting
                        HelpSection(title: "Troubleshooting") {
                            VStack(alignment: .leading, spacing: 12) {
                                HelpPoint(
                                    title: "Network Timeouts",
                                    description:
                                    "Network destinations have special handling - be patient with SMB/AFP volumes"
                                )

                                HelpPoint(
                                    title: "Bookmark Errors",
                                    description: "If folders become inaccessible, clear and re-select them"
                                )

                                HelpPoint(
                                    title: "Slow Performance",
                                    description: "Check Activity Monitor - other apps may be using disk heavily"
                                )

                                HelpPoint(
                                    title: "Debug Information",
                                    description: "Use ImageIntact menu → Show Debug Log for detailed operation logs"
                                )

                                HelpPoint(
                                    title: "Export Logs",
                                    description: "Use Debug Log → Export for support (paths are anonymized)"
                                )
                            }
                        }
                    }
                    .padding(20)
                }
                .onAppear {
                    if let section = scrollToSection {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation {
                                proxy.scrollTo(section, anchor: .top)
                            }
                        }
                    }
                }
            }
        }
        .frame(width: 600, height: 700)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// Help section container
struct HelpSection<Content: View>: View {
    let title: String
    let id: String?
    let content: Content

    init(title: String, id: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.id = id
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .id(id)

            content
        }
    }
}

// Help point for features
struct HelpPoint: View {
    let title: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)

            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// Help shortcut row
struct HelpShortcut: View {
    let key: String
    let action: String

    var body: some View {
        HStack {
            Text(key)
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(4)

            Text(action)
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
    }
}
