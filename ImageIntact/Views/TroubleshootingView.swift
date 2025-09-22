//
//  TroubleshootingView.swift
//  ImageIntact
//
//  Troubleshooting guide for common issues
//

import SwiftUI

struct TroubleshootingView: View {
    @State private var searchText = ""
    @State private var selectedSection: String? = "common"

    var body: some View {
        HSplitView {
            // Sidebar with sections
            List(selection: $selectedSection) {
                Section("Issues") {
                    Label("Common Errors", systemImage: "exclamationmark.triangle")
                        .tag("common")
                    Label("Performance", systemImage: "speedometer")
                        .tag("performance")
                    Label("Permissions", systemImage: "lock.shield")
                        .tag("permissions")
                    Label("Disk Space", systemImage: "internaldrive")
                        .tag("diskspace")
                    Label("Network Drives", systemImage: "network")
                        .tag("network")
                }

                Section("Prevention") {
                    Label("Best Practices", systemImage: "checkmark.seal")
                        .tag("bestpractices")
                    Label("Drive Health", systemImage: "heart.text.square")
                        .tag("drivehealth")
                }

                Section("Recovery") {
                    Label("Interrupted Backups", systemImage: "arrow.clockwise")
                        .tag("recovery")
                }
            }
            .listStyle(SidebarListStyle())
            .frame(minWidth: 200, idealWidth: 250)

            // Content area
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let section = selectedSection {
                        contentForSection(section)
                    } else {
                        Text("Select a topic from the sidebar")
                            .font(.title2)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .searchable(text: $searchText, prompt: "Search troubleshooting...")
        .frame(width: 900, height: 600)
    }

    @ViewBuilder
    func contentForSection(_ section: String) -> some View {
        switch section {
        case "common":
            CommonErrorsSection()
        case "performance":
            PerformanceSection()
        case "permissions":
            PermissionsSection()
        case "diskspace":
            DiskSpaceSection()
        case "network":
            NetworkDrivesSection()
        case "bestpractices":
            BestPracticesSection()
        case "drivehealth":
            DriveHealthSection()
        case "recovery":
            RecoverySection()
        default:
            EmptyView()
        }
    }
}

// MARK: - Content Sections

struct CommonErrorsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Common Error Messages")
                .font(.largeTitle)
                .bold()

            ErrorCard(
                title: "Permission denied",
                icon: "lock.slash",
                explanation: "macOS is blocking ImageIntact from accessing your files.",
                solution: """
                1. Open System Settings
                2. Go to Privacy & Security > Full Disk Access
                3. Click the + button and add ImageIntact
                4. Restart ImageIntact
                """,
                iconColor: .orange
            )

            ErrorCard(
                title: "Checksum mismatch",
                icon: "exclamationmark.shield",
                explanation: "A file was corrupted during transfer.",
                causes: """
                • Faulty USB cable
                • Drive disconnected during copy
                • Bad sectors on drive
                • RAM issues (rare)
                """,
                solution: """
                1. Try a different cable
                2. Check drive health (see Drive Health section)
                3. Run the backup again - the file will be retried
                """,
                iconColor: .red
            )

            ErrorCard(
                title: "Source folder is tagged as destination",
                icon: "arrow.triangle.2.circlepath",
                explanation: "Safety feature preventing infinite backup loops.",
                solution: """
                1. Choose a different source folder
                2. Or remove the .imageintact_destination file from the source
                3. This prevents accidentally backing up into the same folder
                """,
                iconColor: .yellow
            )

            ErrorCard(
                title: "File in use by another process",
                icon: "lock.doc",
                explanation: "The file is open in another application.",
                solution: """
                1. Close any apps that might have the file open
                2. Wait a moment and retry
                3. The file will be automatically retried
                """,
                iconColor: .blue
            )
        }
    }
}

struct PerformanceSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Performance Issues")
                .font(.largeTitle)
                .bold()

            Group {
                Text("Backup Running Slowly?")
                    .font(.title2)
                    .bold()

                Text("Expected speeds by connection type:")
                    .font(.headline)

                SpeedTable()

                Text("Factors affecting speed:")
                    .font(.headline)
                    .padding(.top)

                VStack(alignment: .leading, spacing: 8) {
                    BulletPoint("Many small files are slower than few large files")
                    BulletPoint("Multiple destinations will share bandwidth")
                    BulletPoint("Other apps using the disk will slow transfers")
                    BulletPoint("Spotlight indexing can impact performance")
                    BulletPoint("Thermal throttling on laptops when hot")
                }
            }

            Group {
                Text("App Seems Frozen?")
                    .font(.title2)
                    .bold()
                    .padding(.top)

                VStack(alignment: .leading, spacing: 8) {
                    BulletPoint("Large files (>1GB) may take time without visible progress")
                    BulletPoint("Check Activity Monitor - if CPU is active, it's working")
                    BulletPoint("Network drives may pause during authentication")
                    BulletPoint("Wait at least 5 minutes before force quitting")
                }
            }
        }
    }
}

struct PermissionsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Permission Issues")
                .font(.largeTitle)
                .bold()

            Text("macOS Security Requirements")
                .font(.title2)
                .bold()

            VStack(alignment: .leading, spacing: 15) {
                PermissionStep(
                    number: 1,
                    title: "Grant Full Disk Access",
                    description: "Required for accessing all your photos",
                    steps: [
                        "Open System Settings",
                        "Privacy & Security > Full Disk Access",
                        "Enable ImageIntact"
                    ]
                )

                PermissionStep(
                    number: 2,
                    title: "Allow Folder Access",
                    description: "When prompted, click 'Allow' for folder access",
                    steps: [
                        "Click 'Select Folder' in ImageIntact",
                        "Choose your folder",
                        "Click 'Allow' if macOS asks"
                    ]
                )

                PermissionStep(
                    number: 3,
                    title: "External Drive Access",
                    description: "External drives should work automatically",
                    steps: [
                        "Ensure drive is mounted in Finder",
                        "If issues persist, reformat as APFS or ExFAT",
                        "Avoid NTFS drives (read-only on macOS)"
                    ]
                )
            }
        }
    }
}

struct DiskSpaceSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Disk Space Issues")
                .font(.largeTitle)
                .bold()

            ErrorCard(
                title: "Insufficient space",
                icon: "externaldrive.badge.exclamationmark",
                explanation: "Not enough room on the destination drive.",
                solution: """
                To check space:
                1. Open Finder
                2. Select the drive
                3. Press Cmd+I to Get Info

                Tips for freeing space:
                • Empty Trash (Cmd+Shift+Delete)
                • Delete old backups
                • Use Disk Utility to check for errors
                • Consider a larger drive

                Recommended sizing:
                • Have 2-3x your source size available
                • Keep 10% of drive free for best performance
                """,
                iconColor: .red
            )

            Text("Drive Format Compatibility")
                .font(.title2)
                .bold()
                .padding(.top)

            VStack(alignment: .leading, spacing: 8) {
                FormatRow(format: "APFS", compatibility: "Best for macOS", speed: "Fastest")
                FormatRow(format: "ExFAT", compatibility: "Works with Windows", speed: "Good")
                FormatRow(format: "HFS+", compatibility: "Older Macs", speed: "Good")
                FormatRow(format: "NTFS", compatibility: "Read-only", speed: "Not recommended")
            }
        }
    }
}

struct NetworkDrivesSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Network Drive Issues")
                .font(.largeTitle)
                .bold()

            Text("Common Problems")
                .font(.title2)
                .bold()

            VStack(alignment: .leading, spacing: 15) {
                NetworkIssue(
                    issue: "Connection drops",
                    solutions: [
                        "Use wired Ethernet instead of Wi-Fi",
                        "Ensure NAS doesn't sleep during backup",
                        "Check router settings for timeout values"
                    ]
                )

                NetworkIssue(
                    issue: "Slow performance",
                    solutions: [
                        "Expected: 10-100 MB/s on Gigabit Ethernet",
                        "Wi-Fi will be slower (10-50 MB/s)",
                        "Check for other network traffic"
                    ]
                )

                NetworkIssue(
                    issue: "Authentication issues",
                    solutions: [
                        "Mount the drive in Finder first",
                        "Save credentials in Keychain",
                        "Try SMB instead of AFP or vice versa"
                    ]
                )
            }
        }
    }
}

struct BestPracticesSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Best Practices")
                .font(.largeTitle)
                .bold()

            Group {
                Text("For Reliable Backups")
                    .font(.title2)
                    .bold()

                VStack(alignment: .leading, spacing: 8) {
                    BulletPoint("Use quality cables (USB 3.0 or better)")
                    BulletPoint("Don't disconnect drives during backup")
                    BulletPoint("Keep drives in cool, ventilated areas")
                    BulletPoint("Run backups when computer won't sleep")
                    BulletPoint("Verify first backup manually")
                }
            }

            Group {
                Text("Drive Recommendations")
                    .font(.title2)
                    .bold()
                    .padding(.top)

                VStack(alignment: .leading, spacing: 8) {
                    BulletPoint("SSD for speed, HDD for capacity")
                    BulletPoint("Thunderbolt > USB 3.0 > USB 2.0")
                    BulletPoint("RAID for redundancy (advanced users)")
                    BulletPoint("Keep one backup offsite")
                    BulletPoint("Replace drives every 3-5 years")
                }
            }

            Group {
                Text("Scheduling Tips")
                    .font(.title2)
                    .bold()
                    .padding(.top)

                VStack(alignment: .leading, spacing: 8) {
                    BulletPoint("Run after photo shoots")
                    BulletPoint("Weekly for active photographers")
                    BulletPoint("Before formatting cards")
                    BulletPoint("After organizing sessions")
                }
            }
        }
    }
}

struct DriveHealthSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Drive Health")
                .font(.largeTitle)
                .bold()

            Text("Checking Drive Health")
                .font(.title2)
                .bold()

            VStack(alignment: .leading, spacing: 15) {
                HealthCheck(
                    step: 1,
                    title: "Use Disk Utility",
                    instructions: [
                        "Open Disk Utility (in Applications/Utilities)",
                        "Select your drive",
                        "Click 'First Aid'",
                        "Run the check"
                    ]
                )

                HealthCheck(
                    step: 2,
                    title: "Check SMART Status",
                    instructions: [
                        "In Disk Utility, select the drive",
                        "Look for 'SMART Status'",
                        "Should say 'Verified'",
                        "If 'Failing', replace immediately"
                    ]
                )

                HealthCheck(
                    step: 3,
                    title: "Warning Signs",
                    instructions: [
                        "Unusual noises (clicking, grinding)",
                        "Frequent disconnections",
                        "Very slow performance",
                        "Files mysteriously corrupted",
                        "Drive not mounting reliably"
                    ]
                )
            }
        }
    }
}

struct RecoverySection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Recovery Procedures")
                .font(.largeTitle)
                .bold()

            Text("Backup Was Interrupted?")
                .font(.title2)
                .bold()

            InfoCard(
                icon: "checkmark.circle",
                title: "It's Safe to Restart",
                content: """
                ImageIntact uses smart-skip technology:
                • Already copied files are verified
                • Verified files won't be copied again
                • Just run the backup again
                • Only missing files will be copied
                """,
                color: .green
            )

            Text("Accidentally Deleted Source Files?")
                .font(.title2)
                .bold()
                .padding(.top)

            InfoCard(
                icon: "folder.badge.questionmark",
                title: "Check These Locations",
                content: """
                1. Check the Trash (may still be there)
                2. Check your backup destination
                3. Time Machine if enabled
                4. Cloud backups (iCloud, Google Photos)

                ImageIntact never deletes source files.
                """,
                color: .blue
            )

            Text("Backup Verification Failed?")
                .font(.title2)
                .bold()
                .padding(.top)

            InfoCard(
                icon: "arrow.clockwise",
                title: "Automatic Retry",
                content: """
                If verification fails:
                • File is automatically retried
                • Up to 3 attempts are made
                • Check cable connections
                • Try a different destination

                Failed files are listed at the end.
                """,
                color: .orange
            )
        }
    }
}

// MARK: - Helper Views

struct ErrorCard: View {
    let title: String
    let icon: String
    let explanation: String
    var causes: String? = nil
    let solution: String
    let iconColor: Color

    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundColor(iconColor)
                .frame(width: 50)

            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.headline)
                    .bold()

                Text(explanation)
                    .foregroundColor(.secondary)

                if let causes = causes {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Possible causes:")
                            .font(.subheadline)
                            .bold()
                        Text(causes)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Solution:")
                        .font(.subheadline)
                        .bold()
                    Text(solution)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct InfoCard: View {
    let icon: String
    let title: String
    let content: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundColor(color)
                .frame(width: 50)

            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.headline)
                    .bold()

                Text(content)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct SpeedTable: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            SpeedRow(connection: "Thunderbolt SSD", speed: "400-500 MB/s")
            SpeedRow(connection: "USB 3.0 SSD", speed: "300-400 MB/s")
            SpeedRow(connection: "USB 3.0 HDD", speed: "80-120 MB/s")
            SpeedRow(connection: "Gigabit Ethernet", speed: "50-100 MB/s")
            SpeedRow(connection: "Wi-Fi", speed: "10-50 MB/s")
            SpeedRow(connection: "USB 2.0", speed: "20-30 MB/s")
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct SpeedRow: View {
    let connection: String
    let speed: String

    var body: some View {
        HStack {
            Text(connection)
                .frame(width: 150, alignment: .leading)
            Text(speed)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct FormatRow: View {
    let format: String
    let compatibility: String
    let speed: String

    var body: some View {
        HStack(spacing: 20) {
            Text(format)
                .bold()
                .frame(width: 80, alignment: .leading)
            Text(compatibility)
                .frame(width: 150, alignment: .leading)
            Text(speed)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct BulletPoint: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
            Text(text)
        }
    }
}

struct PermissionStep: View {
    let number: Int
    let title: String
    let description: String
    let steps: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("\(number)")
                    .font(.title2)
                    .bold()
                    .foregroundColor(.white)
                    .frame(width: 30, height: 30)
                    .background(Color.blue)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(steps, id: \.self) { step in
                    HStack(spacing: 8) {
                        Text("→")
                            .foregroundColor(.blue)
                        Text(step)
                            .font(.subheadline)
                    }
                    .padding(.leading, 40)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct NetworkIssue: View {
    let issue: String
    let solutions: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(issue)
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(solutions, id: \.self) { solution in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                        Text(solution)
                            .font(.subheadline)
                    }
                }
            }
            .padding(.leading, 20)
        }
    }
}

struct HealthCheck: View {
    let step: Int
    let title: String
    let instructions: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Step \(step)")
                    .font(.headline)
                    .foregroundColor(.blue)
                Text(title)
                    .font(.headline)
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(instructions, id: \.self) { instruction in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                        Text(instruction)
                            .font(.subheadline)
                    }
                }
            }
            .padding(.leading, 20)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Preview

struct TroubleshootingView_Previews: PreviewProvider {
    static var previews: some View {
        TroubleshootingView()
    }
}