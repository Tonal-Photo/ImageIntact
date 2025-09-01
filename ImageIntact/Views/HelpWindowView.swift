//
//  HelpWindowView.swift
//  ImageIntact
//
//  Modern help window with sidebar navigation
//

import SwiftUI

struct HelpWindowView: View {
    @State private var selectedSection: HelpSectionID = .whatsNew
    @State private var searchText = ""
    var scrollToSection: String? = nil
    
    enum HelpSectionID: String, CaseIterable {
        case whatsNew = "What's New"
        case gettingStarted = "Getting Started"
        case organization = "Smart Organization"
        case duplicates = "Duplicate Detection"
        case presets = "Backup Presets"
        case safety = "Safety Features"
        case fileTypes = "File Types"
        case performance = "Performance"
        case notifications = "Notifications"
        case updates = "Auto Updates"
        case shortcuts = "Shortcuts"
        case manual = "User Manual"
        case faq = "FAQ"
        case troubleshooting = "Troubleshooting"
        case privacy = "Privacy"
        
        var icon: String {
            switch self {
            case .whatsNew: return "sparkles"
            case .gettingStarted: return "play.circle"
            case .organization: return "folder.badge.plus"
            case .duplicates: return "doc.on.doc"
            case .presets: return "star"
            case .safety: return "shield"
            case .fileTypes: return "doc.text"
            case .performance: return "speedometer"
            case .notifications: return "bell"
            case .updates: return "arrow.triangle.2.circlepath"
            case .shortcuts: return "keyboard"
            case .manual: return "book"
            case .faq: return "questionmark.circle"
            case .troubleshooting: return "wrench.and.screwdriver"
            case .privacy: return "lock"
            }
        }
        
        var searchTerms: [String] {
            switch self {
            case .whatsNew: return ["new", "features", "latest", "version"]
            case .gettingStarted: return ["start", "begin", "setup", "first"]
            case .organization: return ["organize", "folder", "structure", "migration"]
            case .duplicates: return ["duplicate", "dedup", "skip", "existing"]
            case .presets: return ["preset", "save", "template", "configuration"]
            case .safety: return ["safe", "protect", "quarantine", "checksum", "verify"]
            case .fileTypes: return ["raw", "jpeg", "video", "sidecar", "format", "capture one", "lightroom"]
            case .performance: return ["speed", "fast", "slow", "eta", "workers"]
            case .notifications: return ["notify", "alert", "complete", "sleep"]
            case .updates: return ["update", "upgrade", "download", "version"]
            case .shortcuts: return ["keyboard", "shortcut", "key", "command"]
            case .manual: return ["guide", "workflow", "task", "import", "memory card"]
            case .faq: return ["question", "why", "symlink", "symbolic", "link", "alias", "skip", "not copying"]
            case .troubleshooting: return ["problem", "error", "fix", "issue", "debug"]
            case .privacy: return ["privacy", "security", "anonymous", "log", "data"]
            }
        }
    }
    
    var filteredSections: [HelpSectionID] {
        if searchText.isEmpty {
            return HelpSectionID.allCases
        }
        
        let search = searchText.lowercased()
        return HelpSectionID.allCases.filter { section in
            section.rawValue.lowercased().contains(search) ||
            section.searchTerms.contains { $0.contains(search) }
        }
    }
    
    var body: some View {
        NavigationSplitView {
            // Sidebar
            List(filteredSections, id: \.self, selection: $selectedSection) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 250)
            .searchable(text: $searchText, prompt: "Search Help")
        } detail: {
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    contentForSection(selectedSection)
                }
                .padding(30)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(selectedSection.rawValue)
            .navigationSubtitle(subtitleForSection(selectedSection))
        }
        .frame(minWidth: 700, minHeight: 500)
    }
    
    func subtitleForSection(_ section: HelpSectionID) -> String {
        switch section {
        case .whatsNew: return "Version 1.2.7"
        case .gettingStarted: return "Quick start guide"
        case .organization: return "Automatic folder organization"
        case .duplicates: return "Smart duplicate handling"
        case .presets: return "Save and reuse configurations"
        case .safety: return "Data protection features"
        case .fileTypes: return "Supported formats"
        case .performance: return "Speed optimization"
        case .notifications: return "System integration"
        case .updates: return "Stay up to date"
        case .shortcuts: return "Keyboard commands"
        case .manual: return "Step-by-step guides"
        case .faq: return "Frequently asked questions"
        case .troubleshooting: return "Common issues"
        case .privacy: return "Your data protection"
        }
    }
    
    @ViewBuilder
    func contentForSection(_ section: HelpSectionID) -> some View {
        switch section {
        case .whatsNew:
            WhatsNewContent()
        case .gettingStarted:
            GettingStartedContent()
        case .organization:
            OrganizationContent()
        case .duplicates:
            DuplicatesContent()
        case .presets:
            PresetsContent()
        case .safety:
            SafetyContent()
        case .fileTypes:
            FileTypesContent()
        case .performance:
            PerformanceContent()
        case .notifications:
            NotificationsContent()
        case .updates:
            UpdatesContent()
        case .shortcuts:
            ShortcutsContent()
        case .manual:
            ManualContent()
        case .faq:
            FAQContent()
        case .troubleshooting:
            TroubleshootingContent()
        case .privacy:
            PrivacyContent()
        }
    }
}

// MARK: - Content Views

struct WhatsNewContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Latest Features")
                .font(.title2)
                .fontWeight(.semibold)
            
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HelpFeatureRow(icon: "doc.on.doc.fill", 
                                   title: "Duplicate Detection",
                                   description: "Intelligently skip files that already exist at destinations")
                    
                    HelpFeatureRow(icon: "arrow.triangle.2.circlepath", 
                                   title: "Enhanced Error Handling",
                                   description: "Automatic retry with exponential backoff for transient errors")
                    
                    HelpFeatureRow(icon: "photo.badge.plus", 
                                   title: "Capture One Sessions",
                                   description: "Full support for .cosessiondb files with cache exclusion")
                    
                    HelpFeatureRow(icon: "folder.badge.gear", 
                                   title: "Smart Organization",
                                   description: "Organize backups into a named folder structure")
                    
                    HelpFeatureRow(icon: "star.fill", 
                                   title: "Backup Presets",
                                   description: "Save and quickly apply backup configurations")
                }
            }
            
            Text("Recent Improvements")
                .font(.title3)
                .fontWeight(.medium)
                .padding(.top)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("• Independent destination processing for maximum speed")
                Text("• Real-time ETA calculations per destination")
                Text("• Sleep prevention during backups")
                Text("• Completion notifications")
                Text("• Memory card detection and warnings")
            }
            .font(.callout)
        }
    }
}

struct GettingStartedContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // App branding header
            HStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 36))
                    .foregroundColor(.accentColor)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to ImageIntact")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Professional Photo Backup for Mac")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.bottom, 8)
            
            Text("ImageIntact safely backs up your photos to multiple destinations with verification.")
                .font(.callout)
            
            Text("Basic Workflow")
                .font(.title3)
                .fontWeight(.medium)
                .padding(.top)
            
            VStack(alignment: .leading, spacing: 12) {
                WorkflowStep(number: "1", 
                            title: "Select Source",
                            description: "Choose the folder containing your photos")
                
                WorkflowStep(number: "2", 
                            title: "Add Destinations",
                            description: "Select up to 4 backup locations")
                
                WorkflowStep(number: "3", 
                            title: "Configure Options",
                            description: "Set organization folder, filters, and preferences")
                
                WorkflowStep(number: "4", 
                            title: "Run Backup",
                            description: "Click backup button or press ⌘R")
                
                WorkflowStep(number: "5", 
                            title: "Monitor Progress",
                            description: "Watch real-time progress for each destination")
            }
            
            Divider()
                .padding(.vertical)
            
            Text("Pro Tip")
                .font(.headline)
            
            Text("Save your configuration as a preset for quick access next time!")
                .font(.callout)
                .foregroundColor(.secondary)
        }
    }
}

struct OrganizationContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Smart Backup Organization")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Automatically organize your backups into clean, dated folder structures.")
                .font(.callout)
            
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Organization Folder", systemImage: "folder")
                        .font(.headline)
                    Text("Files are organized into a folder you specify (e.g., 'Photos 2025')")
                        .font(.callout)
                    
                    Label("Automatic Migration", systemImage: "arrow.right.doc.on.clipboard")
                        .font(.headline)
                    Text("Existing loose files are automatically moved into the organized folder")
                        .font(.callout)
                    
                    Label("Smart Detection", systemImage: "sparkles")
                        .font(.headline)
                    Text("Recognizes files that were previously backed up without organization")
                        .font(.callout)
                    
                    Label("Safe Migration", systemImage: "checkmark.shield")
                        .font(.headline)
                    Text("Files are moved, not copied, to save time and disk space")
                        .font(.callout)
                }
            }
            
            Text("How It Works")
                .font(.title3)
                .fontWeight(.medium)
                .padding(.top)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("1. Enter a folder name (defaults to your source folder name)")
                Text("2. Files are copied to: Destination → Organization Folder → Files")
                Text("3. Existing files outside the folder are migrated automatically")
                Text("4. Duplicate files are intelligently handled based on your preferences")
            }
            .font(.callout)
        }
    }
}

struct DuplicatesContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Duplicate Detection")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Save time and space by intelligently handling duplicate files.")
                .font(.callout)
            
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Pre-flight Analysis", systemImage: "magnifyingglass")
                        .font(.headline)
                    Text("Scans destinations before backup to identify existing files")
                        .font(.callout)
                    
                    Label("SHA-256 Verification", systemImage: "checkmark.seal")
                        .font(.headline)
                    Text("Uses cryptographic checksums to identify exact duplicates")
                        .font(.callout)
                    
                    Label("Renamed File Detection", systemImage: "doc.badge.arrow.up")
                        .font(.headline)
                    Text("Finds files with same content but different names")
                        .font(.callout)
                    
                    Label("Smart Skipping", systemImage: "forward.fill")
                        .font(.headline)
                    Text("Optionally skip exact duplicates or renamed files")
                        .font(.callout)
                }
            }
            
            Text("Configuration Options")
                .font(.title3)
                .fontWeight(.medium)
                .padding(.top)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("• **Skip exact duplicates**: Don't copy files that already exist")
                Text("• **Skip renamed duplicates**: Don't copy files with same content")
                Text("• **Show analysis**: View detailed duplicate report before backup")
                Text("• **Per-destination analysis**: Each destination analyzed independently")
            }
            .font(.callout)
        }
    }
}

// Additional content views would follow similar patterns...

// MARK: - Helper Views

struct HelpFeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

struct WorkflowStep: View {
    let number: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.accentColor)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

// MARK: - Remaining Content Sections

struct PresetsContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Backup Presets")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Save time by creating presets for common backup scenarios.")
                .font(.callout)
            
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Built-in Presets", systemImage: "star.circle")
                        .font(.headline)
                    Text("Choose from Daily Workflow, Client Shoot, or Archive presets")
                        .font(.callout)
                    
                    Label("Custom Presets", systemImage: "plus.circle")
                        .font(.headline)
                    Text("Save your current configuration as a reusable preset")
                        .font(.callout)
                    
                    Label("Complete Configuration", systemImage: "doc.badge.gearshape")
                        .font(.headline)
                    Text("Presets save source, destinations, filters, and all settings")
                        .font(.callout)
                    
                    Label("Quick Apply", systemImage: "bolt.circle")
                        .font(.headline)
                    Text("Select a preset to instantly configure your backup")
                        .font(.callout)
                }
            }
            
            Text("Creating a Preset")
                .font(.title3)
                .fontWeight(.medium)
                .padding(.top)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("1. Configure your backup (source, destinations, filters)")
                Text("2. Click 'Save as Preset' under the source field")
                Text("3. Name your preset and choose an icon")
                Text("4. Apply it anytime from the Presets menu")
            }
            .font(.callout)
            
            Divider()
                .padding(.vertical)
            
            Text("Preset Management")
                .font(.headline)
            
            Text("Edit or delete presets in Preferences → Presets tab")
                .font(.callout)
                .foregroundColor(.secondary)
        }
    }
}

struct SafetyContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Safety Features")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("ImageIntact prioritizes data safety above all else.")
                .font(.callout)
            
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Never Deletes Files", systemImage: "xmark.shield")
                        .font(.headline)
                    Text("Files are never deleted from any destination")
                        .font(.callout)
                    
                    Label("SHA-256 Verification", systemImage: "checkmark.seal")
                        .font(.headline)
                    Text("Every file is verified with cryptographic checksums")
                        .font(.callout)
                    
                    Label("Smart Quarantine", systemImage: "exclamationmark.triangle")
                        .font(.headline)
                    Text("Conflicting files are quarantined, not overwritten")
                        .font(.callout)
                    
                    Label("Source Protection", systemImage: "lock.shield")
                        .font(.headline)
                    Text("Source folders are tagged to prevent selection as destinations")
                        .font(.callout)
                }
            }
            
            Text("Quarantine System")
                .font(.title3)
                .fontWeight(.medium)
                .padding(.top)
            
            Text("When a file exists at the destination with different content:")
                .font(.callout)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("1. The existing file is moved to a Quarantine folder")
                Text("2. The quarantine folder includes timestamp and checksum")
                Text("3. The new file is then copied to the destination")
                Text("4. You can review quarantined files at any time")
            }
            .font(.callout)
            
            GroupBox {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                    Text("Quarantine folders are never automatically deleted")
                        .font(.caption)
                }
            }
        }
    }
}

struct FileTypesContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Supported File Types")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("ImageIntact intelligently handles photography and video files.")
                .font(.callout)
            
            GroupBox("RAW Formats") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("**Canon**: CR2, CR3, CRW")
                    Text("**Nikon**: NEF, NRW")
                    Text("**Sony**: ARW, SRF, SR2")
                    Text("**Fujifilm**: RAF")
                    Text("**Others**: DNG, ORF, RW2, PEF, IIQ, and 20+ more")
                }
                .font(.callout)
            }
            
            GroupBox("Standard Formats") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("**Images**: JPEG, TIFF, PNG, HEIC, HEIF, WebP, BMP, GIF")
                    Text("**Video**: MOV, MP4, AVI, MTS, M2TS, MKV, WebM")
                }
                .font(.callout)
            }
            
            GroupBox("Professional Software") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("**Adobe**: XMP sidecars, DNG")
                    Text("**Lightroom**: Catalogs (.lrcat), Preview data (.lrdata)")
                    Text("**Capture One**: Catalogs (.cocatalog), Sessions (.cosessiondb), Settings (.cos)")
                    Text("**Apple**: AAE sidecars")
                    Text("**Others**: DxO (.dop), RawTherapee (.pp3)")
                }
                .font(.callout)
            }
            
            Text("Smart Cache Exclusion")
                .font(.title3)
                .fontWeight(.medium)
                .padding(.top)
            
            Text("These are automatically skipped to save space:")
                .font(.callout)
            
            VStack(alignment: .leading, spacing: 6) {
                Text("• Lightroom preview caches")
                Text("• Capture One Session caches (Cache/, Proxies/, Thumbnails/)")
                Text("• Photos.app database files")
                Text("• Adobe Bridge caches")
                Text("• System files (.DS_Store, Thumbs.db)")
            }
            .font(.callout)
            .foregroundColor(.secondary)
        }
    }
}

struct PerformanceContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Performance Optimization")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("ImageIntact automatically optimizes for your hardware.")
                .font(.callout)
            
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Independent Destinations", systemImage: "arrow.triangle.branch")
                        .font(.headline)
                    Text("Each destination runs at full speed independently")
                        .font(.callout)
                    
                    Label("Adaptive Workers", systemImage: "cpu")
                        .font(.headline)
                    Text("1-8 worker threads per destination based on drive speed")
                        .font(.callout)
                    
                    Label("Queue System", systemImage: "list.number")
                        .font(.headline)
                    Text("Smart task scheduling prevents bottlenecks")
                        .font(.callout)
                    
                    Label("Real-time ETA", systemImage: "clock")
                        .font(.headline)
                    Text("Accurate time estimates per destination")
                        .font(.callout)
                }
            }
            
            Text("Drive Detection")
                .font(.title3)
                .fontWeight(.medium)
                .padding(.top)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "internaldrive")
                    Text("**SSD**: Maximum 8 workers for parallel processing")
                }
                HStack {
                    Image(systemName: "externaldrive")
                    Text("**HDD**: 2-4 workers to avoid thrashing")
                }
                HStack {
                    Image(systemName: "network")
                    Text("**Network**: 1-2 workers with timeout handling")
                }
                HStack {
                    Image(systemName: "sdcard")
                    Text("**Memory Card**: Warning when selected as destination")
                }
            }
            .font(.callout)
            
            Text("Tips for Best Performance")
                .font(.title3)
                .fontWeight(.medium)
                .padding(.top)
            
            VStack(alignment: .leading, spacing: 6) {
                Text("• Use SSDs for fastest backup speeds")
                Text("• Connect drives directly (avoid USB hubs)")
                Text("• Close other disk-intensive applications")
                Text("• Use wired network connections when possible")
            }
            .font(.callout)
        }
    }
}

struct NotificationsContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("System Integration")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("ImageIntact integrates seamlessly with macOS.")
                .font(.callout)
            
            GroupBox("Features") {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Sleep Prevention", systemImage: "wake")
                        .font(.headline)
                    Text("Mac stays awake during backups (configurable)")
                        .font(.callout)
                    
                    Label("Completion Notifications", systemImage: "bell.badge")
                        .font(.headline)
                    Text("Get notified when backups complete")
                        .font(.callout)
                    
                    Label("Background Operation", systemImage: "app.badge")
                        .font(.headline)
                    Text("Continue working while backing up")
                        .font(.callout)
                    
                    Label("Focus Mode Compatible", systemImage: "moon.circle")
                        .font(.headline)
                    Text("Respects Do Not Disturb settings")
                        .font(.callout)
                }
            }
            
            Text("Configuring Notifications")
                .font(.title3)
                .fontWeight(.medium)
                .padding(.top)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("1. Open Preferences (⌘,)")
                Text("2. Enable 'Show notification on complete'")
                Text("3. Optionally enable sound alerts")
                Text("4. Grant notification permission if prompted")
            }
            .font(.callout)
            
            GroupBox {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                    VStack(alignment: .leading) {
                        Text("Notification Permissions")
                            .font(.caption)
                            .fontWeight(.medium)
                        Text("Check System Settings → Notifications → ImageIntact")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

struct UpdatesContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Automatic Updates")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Stay up to date with the latest features and fixes.")
                .font(.callout)
            
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Daily Checks", systemImage: "arrow.clockwise.circle")
                        .font(.headline)
                    Text("Automatically checks once per day on launch")
                        .font(.callout)
                    
                    Label("Manual Check", systemImage: "hand.tap")
                        .font(.headline)
                    Text("ImageIntact menu → Check for Updates")
                        .font(.callout)
                    
                    Label("Safe Downloads", systemImage: "lock.shield")
                        .font(.headline)
                    Text("Downloads from GitHub with progress tracking")
                        .font(.callout)
                    
                    Label("Version Skipping", systemImage: "forward")
                        .font(.headline)
                    Text("Skip specific versions if desired")
                        .font(.callout)
                }
            }
            
            Text("Update Settings")
                .font(.title3)
                .fontWeight(.medium)
                .padding(.top)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("**Auto-check**: Preferences → Check for updates daily")
                Text("**Channel**: Choose stable or beta releases")
                Text("**Downloads**: Saved to your Downloads folder")
                Text("**Installation**: Double-click downloaded DMG to install")
            }
            .font(.callout)
            
            Divider()
                .padding(.vertical)
            
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.yellow)
                Text("Current version: 1.2.8")
                    .font(.callout)
                    .fontWeight(.medium)
            }
        }
    }
}

struct ShortcutsContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Keyboard Shortcuts")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Work faster with keyboard commands.")
                .font(.callout)
            
            GroupBox("Essential Shortcuts") {
                VStack(alignment: .leading, spacing: 8) {
                    ShortcutRow(keys: "⌘R", action: "Run backup")
                    ShortcutRow(keys: "⌘.", action: "Cancel backup")
                    ShortcutRow(keys: "⌘K", action: "Clear all selections")
                    ShortcutRow(keys: "⌘,", action: "Open Preferences")
                    ShortcutRow(keys: "⌘?", action: "Show Help")
                }
            }
            
            GroupBox("Selection Shortcuts") {
                VStack(alignment: .leading, spacing: 8) {
                    ShortcutRow(keys: "⌘1", action: "Select source folder")
                    ShortcutRow(keys: "⌘2", action: "Select first destination")
                    ShortcutRow(keys: "⌘3", action: "Select second destination")
                    ShortcutRow(keys: "⌘+", action: "Add destination")
                    ShortcutRow(keys: "⌘-", action: "Remove destination")
                }
            }
            
            GroupBox("Window Management") {
                VStack(alignment: .leading, spacing: 8) {
                    ShortcutRow(keys: "⌘W", action: "Close window")
                    ShortcutRow(keys: "⌘M", action: "Minimize")
                    ShortcutRow(keys: "⌘Q", action: "Quit ImageIntact")
                    ShortcutRow(keys: "Esc", action: "Close dialog/sheet")
                }
            }
            
            GroupBox("Debug & Support") {
                VStack(alignment: .leading, spacing: 8) {
                    ShortcutRow(keys: "⌘D", action: "Show debug log")
                    ShortcutRow(keys: "⌘⇧C", action: "Copy debug info")
                    ShortcutRow(keys: "⌘⇧E", action: "Export logs")
                }
            }
        }
    }
}

struct ManualContent: View {
    @State private var expandedSection: String? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("User Manual")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Step-by-step guides for common tasks.")
                .font(.callout)
            
            DisclosureGroup("First Time Setup", isExpanded: Binding(
                get: { expandedSection == "setup" },
                set: { _ in expandedSection = expandedSection == "setup" ? nil : "setup" }
            )) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("1. Open Preferences (⌘,)")
                    Text("2. Enable 'Restore last session on launch'")
                    Text("3. Set 'Show notification on complete'")
                    Text("4. Choose your default file type filter")
                    Text("5. Select your main photo folder as Source")
                    Text("6. Add your backup drives as Destinations")
                    Text("7. Save configuration as a preset")
                }
                .font(.callout)
                .padding(.top, 8)
            }
            
            DisclosureGroup("Daily Photo Backup", isExpanded: Binding(
                get: { expandedSection == "daily" },
                set: { _ in expandedSection = expandedSection == "daily" ? nil : "daily" }
            )) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("1. Connect your backup drive(s)")
                    Text("2. Launch ImageIntact")
                    Text("3. Select your preset or configure manually")
                    Text("4. Set organization folder (e.g., '2025-01-26 Wedding')")
                    Text("5. Click 'Run Backup' (⌘R)")
                    Text("6. Monitor progress for each destination")
                    Text("7. Wait for completion notification")
                }
                .font(.callout)
                .padding(.top, 8)
            }
            
            DisclosureGroup("Memory Card Import", isExpanded: Binding(
                get: { expandedSection == "card" },
                set: { _ in expandedSection = expandedSection == "card" ? nil : "card" }
            )) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("1. Insert memory card")
                    Text("2. Select card as Source (/Volumes/CARD_NAME)")
                    Text("3. Select photo storage drive as Destination")
                    Text("4. Enable organization with descriptive name")
                    Text("5. Consider date filter if card has old photos")
                    Text("6. Run backup")
                    
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        Text("Never select memory card as destination!")
                            .fontWeight(.medium)
                    }
                    .padding(.top, 4)
                }
                .font(.callout)
                .padding(.top, 8)
            }
            
            DisclosureGroup("Multi-Destination Backup", isExpanded: Binding(
                get: { expandedSection == "multi" },
                set: { _ in expandedSection = expandedSection == "multi" ? nil : "multi" }
            )) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("1. Add up to 4 destinations with + button")
                    Text("2. Mix drive types (SSD, HDD, Network)")
                    Text("3. Each destination runs independently:")
                    Text("   • Own progress bar and ETA")
                    Text("   • 1-8 adaptive worker threads")
                    Text("   • Independent speed")
                    Text("4. Fast drives won't wait for slow ones")
                    Text("5. If one fails, others continue")
                }
                .font(.callout)
                .padding(.top, 8)
            }
            
            DisclosureGroup("Using Presets", isExpanded: Binding(
                get: { expandedSection == "presets" },
                set: { _ in expandedSection = expandedSection == "presets" ? nil : "presets" }
            )) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("**Creating a Preset:**")
                        .fontWeight(.medium)
                    Text("1. Configure backup as desired")
                    Text("2. Click 'Save as Preset'")
                    Text("3. Name and choose icon")
                    Text("")
                    Text("**Using a Preset:**")
                        .fontWeight(.medium)
                    Text("1. Click Presets button")
                    Text("2. Select desired preset")
                    Text("3. Configuration loads instantly")
                    Text("4. Make any adjustments needed")
                    Text("5. Run backup")
                }
                .font(.callout)
                .padding(.top, 8)
            }
        }
    }
}

struct TroubleshootingContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Troubleshooting")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Solutions for common issues.")
                .font(.callout)
            
            GroupBox("Common Issues") {
                VStack(alignment: .leading, spacing: 12) {
                    TroubleshootingItem(
                        issue: "Network drive timeouts",
                        solution: "Network destinations have longer timeouts. Ensure stable connection and be patient with SMB/AFP volumes."
                    )
                    
                    TroubleshootingItem(
                        issue: "Bookmark errors",
                        solution: "If folders become inaccessible, clear selections (⌘K) and re-select them."
                    )
                    
                    TroubleshootingItem(
                        issue: "Slow performance",
                        solution: "Check Activity Monitor. Other apps may be using disk heavily. Close unnecessary applications."
                    )
                    
                    TroubleshootingItem(
                        issue: "Files not copying",
                        solution: "Check file type filter settings. Ensure files aren't being skipped by duplicate detection."
                    )
                    
                    TroubleshootingItem(
                        issue: "Backup won't start",
                        solution: "Verify source folder exists and destinations are mounted. Check for disk space."
                    )
                }
            }
            
            Text("Debug Information")
                .font(.title3)
                .fontWeight(.medium)
                .padding(.top)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("1. Open Debug Log: ImageIntact menu → Show Debug Log")
                Text("2. Look for error messages (marked with ❌)")
                Text("3. Check operation details and timestamps")
                Text("4. Export logs for support (paths are anonymized)")
            }
            .font(.callout)
            
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Getting Support", systemImage: "questionmark.circle")
                        .font(.headline)
                    
                    Text("1. Export debug log (anonymized)")
                        .font(.callout)
                    Text("2. Note your macOS version and ImageIntact version")
                        .font(.callout)
                    Text("3. Describe steps to reproduce the issue")
                        .font(.callout)
                    Text("4. Submit issue on GitHub")
                        .font(.callout)
                }
            }
        }
    }
}

struct PrivacyContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Privacy & Security")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Your data stays on your Mac.")
                .font(.callout)
            
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Local Processing Only", systemImage: "lock.laptopcomputer")
                        .font(.headline)
                    Text("All operations happen on your Mac - no cloud services")
                        .font(.callout)
                    
                    Label("Path Anonymization", systemImage: "eye.slash")
                        .font(.headline)
                    Text("Personal information removed from exported logs")
                        .font(.callout)
                    
                    Label("No Analytics", systemImage: "chart.xyaxis.line")
                        .font(.headline)
                    Text("No usage data or telemetry is collected")
                        .font(.callout)
                    
                    Label("Open Source", systemImage: "chevron.left.forwardslash.chevron.right")
                        .font(.headline)
                    Text("Source code available for inspection on GitHub")
                        .font(.callout)
                }
            }
            
            Text("Log Anonymization")
                .font(.title3)
                .fontWeight(.medium)
                .padding(.top)
            
            Text("When exporting logs for support:")
                .font(.callout)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("/Users/john →")
                        .font(.system(.caption, design: .monospaced))
                    Text("/Users/[USER]")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.blue)
                }
                HStack(spacing: 8) {
                    Text("/Volumes/MyDrive →")
                        .font(.system(.caption, design: .monospaced))
                    Text("/Volumes/[DRIVE]")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.blue)
                }
                HStack(spacing: 8) {
                    Text("John's MacBook →")
                        .font(.system(.caption, design: .monospaced))
                    Text("[HOSTNAME]")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.blue)
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            
            Text("Data Storage")
                .font(.title3)
                .fontWeight(.medium)
                .padding(.top)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("• **Preferences**: ~/Library/Preferences/")
                Text("• **Backup History**: Core Data on your Mac")
                Text("• **Presets**: Stored locally in app preferences")
                Text("• **Logs**: Temporary, deleted after 30 days")
            }
            .font(.callout)
            
            GroupBox {
                HStack {
                    Image(systemName: "checkmark.shield")
                        .foregroundColor(.green)
                    Text("ImageIntact never connects to the internet except for update checks")
                        .font(.caption)
                }
            }
        }
    }
}

// MARK: - Additional Helper Views

struct ShortcutRow: View {
    let keys: String
    let action: String
    
    var body: some View {
        HStack {
            Text(keys)
                .font(.system(.callout, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(4)
                .frame(width: 80, alignment: .leading)
            
            Text(action)
                .font(.callout)
            
            Spacer()
        }
    }
}

struct TroubleshootingItem: View {
    let issue: String
    let solution: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(issue, systemImage: "exclamationmark.circle")
                .font(.callout)
                .fontWeight(.medium)
            
            Text(solution)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 28)
        }
    }
}

// MARK: - FAQ Content

struct FAQContent: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Frequently Asked Questions")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Common questions and answers about ImageIntact")
                    .font(.title3)
                    .foregroundColor(.secondary)
                
                Divider()
                
                FAQItem(
                    question: "Why aren't all my files being copied?",
                    answer: "ImageIntact only backs up photography-related files (images, videos, RAW files, and sidecar files). System files, application files, document files, and cache files are automatically excluded. Additionally, symbolic links (shortcuts/aliases) are skipped for security reasons."
                )
                
                FAQItem(
                    question: "What are symbolic links and why are they skipped?",
                    answer: "Symbolic links (also called symlinks or aliases on Mac) are special files that act as shortcuts pointing to other files or folders. For security and data integrity, ImageIntact backs up only the actual files, not these shortcuts. This prevents potential security issues and ensures you're backing up real data, not just pointers to data."
                )
                
                FAQItem(
                    question: "Why does my backup seem stuck or slow?",
                    answer: "Large RAW files (20-50MB each) and network drives can significantly impact speed. Check the individual progress bars for each destination - they update independently. Network drives will show a network icon and may take longer. The app adapts the number of workers (1-8) based on drive speed."
                )
                
                FAQItem(
                    question: "Can I backup to the same drive multiple times?",
                    answer: "Yes! Each destination must be a different folder. This is useful for creating multiple organized copies or different organizational structures of the same photos."
                )
                
                FAQItem(
                    question: "What happens if a backup is interrupted?",
                    answer: "ImageIntact is designed to handle interruptions safely. On the next run, it will skip files that were already successfully copied (verified by checksum) and continue with the remaining files. Your data is always safe - files are never deleted or overwritten without quarantine."
                )
                
                FAQItem(
                    question: "Why are some file types like .cosessiondb or .lrdata not being copied?",
                    answer: "These are package files (folders that appear as single files) containing cache data and previews. ImageIntact intelligently skips cache folders inside these packages while still backing up the important catalog and session files."
                )
                
                FAQItem(
                    question: "What's the difference between 'Skip Exact Duplicates' and 'Skip Renamed Duplicates'?",
                    answer: "'Skip Exact Duplicates' skips files with identical names and content. 'Skip Renamed Duplicates' also skips files with the same content but different names (useful when you've renamed files but they're the same photo)."
                )
                
                FAQItem(
                    question: "How does the checksum verification work?",
                    answer: "Every file is verified using SHA-256 checksums - a cryptographic method that creates a unique fingerprint for each file. After copying, ImageIntact verifies the destination file matches the source exactly. This ensures perfect, bit-for-bit copies."
                )
                
                FAQItem(
                    question: "Can I use ImageIntact with memory cards?",
                    answer: "Yes, but ImageIntact will warn you if you try to select a memory card as a destination (writing to cards can be slow and reduce their lifespan). Memory cards are perfectly fine as source locations."
                )
                
                FAQItem(
                    question: "Why does ImageIntact need Full Disk Access?",
                    answer: "Full Disk Access is required to read from and write to external drives and protected folders. Without it, macOS prevents access to many locations including external drives. Your privacy is protected - ImageIntact never sends data online."
                )
            }
            .padding()
        }
    }
}

struct FAQItem: View {
    let question: String
    let answer: String
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down.circle.fill" : "chevron.right.circle")
                        .foregroundColor(.accentColor)
                    
                    Text(question)
                        .font(.callout)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                    
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                Text(answer)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 28)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}