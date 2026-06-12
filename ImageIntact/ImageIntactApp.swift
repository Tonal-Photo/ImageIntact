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

    // Check for UI test mode (DEBUG-only; release builds never honor the seam)
    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("--uitest") {
        ApplicationLogger.shared.info("🧪 UI Test mode detected", category: .app)
        // Reset-if-requested, then auto-fixtures or explicit-path passthrough.
        // Must run before BackupManager init (ContentView) reads the seam keys.
        UITestFixtures.bootstrap()
      }
    #endif

    // Initialize system capabilities detection on app launch
    _ = SystemCapabilities.shared
    ApplicationLogger.shared.info(
      "🚀 ImageIntact starting on \(SystemCapabilities.shared.displayName)", category: .app)

    // Start drive monitoring
    DriveMonitor.shared.startMonitoring()
    ApplicationLogger.shared.info("📱 Drive monitoring started", category: .app)
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
            showPreferences = true
          }
        }
    }
    .windowResizability(.contentSize)
    .defaultSize(width: 600, height: 400)
    .defaultPosition(.center)
    // Ensure window is visible and activates properly
    .windowStyle(.automatic)
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
          NotificationCenter.default.post(
            name: NSNotification.Name("SelectSourceFolder"), object: nil)
        }
        .keyboardShortcut("1", modifiers: .command)

        Button("Select First Destination") {
          NotificationCenter.default.post(
            name: NSNotification.Name("SelectDestination1"), object: nil)
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

        Button("Select Source Folder") {
          NotificationCenter.default.post(
            name: NSNotification.Name("SelectSourceFolder"), object: nil)
        }
        .keyboardShortcut("1", modifiers: .command)

        Button("Select First Destination") {
          NotificationCenter.default.post(
            name: NSNotification.Name("SelectDestination1"), object: nil)
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

      }

      // Replace the default Help menu with our custom one
      CommandGroup(replacing: .help) {
        Button("ImageIntact Help") {
          Task { @MainActor in
            HelpWindowManager.shared.showHelp()
          }
        }
        .keyboardShortcut("?", modifiers: .command)
      }
    }
  }
}
