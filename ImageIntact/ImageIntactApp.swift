//
//  ImageIntactApp.swift
//  ImageIntact
//
//  Created by Konrad Michels on 8/1/25.
//

import SwiftUI

@main
struct ImageIntactApp: App {
    @State private var showPreferences = false
    
    init() {
        // Initialize logging system first
        _ = ApplicationLogger.shared
        
        // Check for UI test mode
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--uitest") {
            ApplicationLogger.shared.info("🧪 UI Test mode detected", category: .app)
            // Note: BackupManager.isRunningTests is automatically true when running tests
            
            // Setup test environment if needed
            setupTestEnvironment()
        }
        
        // Initialize system capabilities detection on app launch
        _ = SystemCapabilities.shared
        ApplicationLogger.shared.info("🚀 ImageIntact starting on \(SystemCapabilities.shared.displayName)", category: .app)
        
        // Start drive monitoring
        DriveMonitor.shared.startMonitoring()
        ApplicationLogger.shared.info("📱 Drive monitoring started", category: .app)
    }
    
    private func setupTestEnvironment() {
        // Process test arguments for UI tests
        let arguments = ProcessInfo.processInfo.arguments
        
        // These will be processed by BackupManager when it initializes
        for (index, arg) in arguments.enumerated() {
            switch arg {
            case "--testSource":
                if index + 1 < arguments.count {
                    UserDefaults.standard.set(arguments[index + 1], forKey: "TestSourcePath")
                }
            case "--testDest1":
                if index + 1 < arguments.count {
                    UserDefaults.standard.set(arguments[index + 1], forKey: "TestDest1Path")
                }
            case "--testDest2":
                if index + 1 < arguments.count {
                    UserDefaults.standard.set(arguments[index + 1], forKey: "TestDest2Path")
                }
            case "--testOrganization":
                if index + 1 < arguments.count {
                    UserDefaults.standard.set(arguments[index + 1], forKey: "TestOrganizationName")
                }
            default:
                break
            }
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .sheet(isPresented: $showPreferences) {
                    PreferencesView()
                }
                .onAppear {
                    // Listen for preferences notification
                    NotificationCenter.default.addObserver(
                        forName: NSNotification.Name("ShowPreferences"),
                        object: nil,
                        queue: .main
                    ) { _ in
                        Task { @MainActor in
                            showPreferences = true
                        }
                    }
                }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 600, height: 400)
        .commands {
            // Add Preferences to the app menu
            CommandGroup(after: .appInfo) {
                Button("Preferences...") {
                    NotificationCenter.default.post(name: NSNotification.Name("ShowPreferences"), object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            // Replace the standard File menu items
            CommandGroup(replacing: .newItem) {
                Button("Select Source Folder") {
                    NotificationCenter.default.post(name: NSNotification.Name("SelectSourceFolder"), object: nil)
                }
                .keyboardShortcut("1", modifiers: .command)
                
                Button("Select First Destination") {
                    NotificationCenter.default.post(name: NSNotification.Name("SelectDestination1"), object: nil)
                }
                .keyboardShortcut("2", modifiers: .command)
                
                Button("Add Destination") {
                    NotificationCenter.default.post(name: NSNotification.Name("AddDestination"), object: nil)
                }
                .keyboardShortcut("+", modifiers: .command)
                
                Divider()
                
                Button("Run Backup") {
                    NotificationCenter.default.post(name: NSNotification.Name("RunBackup"), object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            
            // Add to Edit menu after the standard items
            CommandGroup(after: .pasteboard) {
                Divider()
                
                Button("Clear All Selections") {
                    NotificationCenter.default.post(name: NSNotification.Name("ClearAll"), object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)
            }
            
            // Add a custom ImageIntact menu
            CommandMenu("ImageIntact") {
                Button("Run Backup") {
                    NotificationCenter.default.post(name: NSNotification.Name("RunBackup"), object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
                
                Divider()
                
                // Premium Feature Test Items
                Menu("Premium Features") {
                    Button("Automated Backup (Pro)") {
                        PremiumFeatureManager.shared.performPremiumAction(.automatedBackups) {
                            // This would open automated backup settings
                            print("✅ Opening automated backup settings...")
                            NotificationCenter.default.post(name: NSNotification.Name("ShowAutomatedBackupSettings"), object: nil)
                        } fallback: {
                            // Show upgrade prompt
                            print("🔒 Automated Backup is a Pro feature")
                            NotificationCenter.default.post(name: NSNotification.Name("ShowUpgradePrompt"), object: nil)
                        }
                    }
                    .disabled(!PremiumFeatureManager.shared.isUnlocked(.automatedBackups))
                    
                    Button("Cloud Destinations (Pro)") {
                        PremiumFeatureManager.shared.performPremiumAction(.cloudBackup) {
                            print("✅ Opening cloud destination settings...")
                            NotificationCenter.default.post(name: NSNotification.Name("ShowCloudSettings"), object: nil)
                        } fallback: {
                            print("🔒 Cloud Destinations is a Pro feature")
                            NotificationCenter.default.post(name: NSNotification.Name("ShowUpgradePrompt"), object: nil)
                        }
                    }
                    .disabled(!PremiumFeatureManager.shared.isUnlocked(.cloudBackup))
                    
                    Divider()
                    
                    if BuildConfiguration.isAppStoreBuild {
                        if StoreManager.shared.hasPro {
                            Text("✅ Pro Version Active")
                        } else {
                            Button("Upgrade to Pro...") {
                                NotificationCenter.default.post(name: NSNotification.Name("ShowPurchaseView"), object: nil)
                            }
                        }
                    } else {
                        Text("Open Source Edition")
                        Text("Pro features available in App Store version")
                    }
                }
                
                Divider()
                
                Button("Select Source Folder") {
                    NotificationCenter.default.post(name: NSNotification.Name("SelectSourceFolder"), object: nil)
                }
                .keyboardShortcut("1", modifiers: .command)
                
                Button("Select First Destination") {
                    NotificationCenter.default.post(name: NSNotification.Name("SelectDestination1"), object: nil)
                }
                .keyboardShortcut("2", modifiers: .command)
                
                Button("Add Destination") {
                    NotificationCenter.default.post(name: NSNotification.Name("AddDestination"), object: nil)
                }
                .keyboardShortcut("+", modifiers: .command)
                
                Divider()
                
                Button("Clear All Selections") {
                    NotificationCenter.default.post(name: NSNotification.Name("ClearAll"), object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)
                
                Divider()
                
                Button("Show Debug Log") {
                    NotificationCenter.default.post(name: NSNotification.Name("ShowDebugLog"), object: nil)
                }
                
                Button("Export Debug Log...") {
                    NotificationCenter.default.post(name: NSNotification.Name("ExportDebugLog"), object: nil)
                }
                
                Button("Verify Core Data Storage") {
                    NotificationCenter.default.post(name: NSNotification.Name("VerifyCoreData"), object: nil)
                }

                Divider()

                Button("Vision Analysis Results...") {
                    Task { @MainActor in
                        VisionResultsWindowManager.shared.showVisionResults()
                    }
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])
                .help("View AI-analyzed photo metadata")

                Divider()

                Button("Check for Updates...") {
                    NotificationCenter.default.post(name: NSNotification.Name("CheckForUpdates"), object: nil)
                }
                
            }
            
            // Add Debug menu (only in debug builds)
            #if DEBUG
            CommandMenu("Debug") {
                Button("Test Update Flow") {
                    NotificationCenter.default.post(name: NSNotification.Name("TestUpdateFlow"), object: nil)
                }
                .keyboardShortcut("u", modifiers: [.command, .shift, .option])
                
                Divider()
                
                Button("Enable Test Mode") {
                    UpdateManager.testMode = true
                    UpdateManager.mockVersion = "1.0.0"
                    print("🧪 Test mode enabled with version 1.0.0")
                }
                
                Button("Disable Test Mode") {
                    UpdateManager.testMode = false
                    UpdateManager.mockVersion = nil
                    print("🧪 Test mode disabled")
                }
            }
            #endif
            
            // Replace the default Help menu with our custom one
            CommandGroup(replacing: .help) {
                Button("ImageIntact Help") {
                    Task { @MainActor in
                        HelpWindowManager.shared.showHelp()
                    }
                }
                .keyboardShortcut("?", modifiers: .command)

                Button("Troubleshooting Guide") {
                    Task { @MainActor in
                        TroubleshootingWindowManager.shared.showTroubleshooting()
                    }
                }

                Divider()

                Button("Report a Bug...") {
                    Task { @MainActor in
                        HelpWindowManager.shared.showBugReport()
                    }
                }
                .keyboardShortcut("B", modifiers: [.command, .shift])
            }
        }
    }
}
