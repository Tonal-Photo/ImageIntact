//
//  HelpWindowManager.swift
//  ImageIntact
//
//  Manages the help window as a separate panel
//

import SwiftUI
import AppKit

class HelpWindowManager {
    static let shared = HelpWindowManager()
    private var helpWindow: NSWindow?
    
    private init() {}
    
    func showHelp(scrollToSection: String? = nil) {
        // If window already exists, bring it to front
        if let existingWindow = helpWindow {
            // Make it key and bring to front without forcing app activation
            // This is less disruptive if user is working in another app
            existingWindow.makeKeyAndOrderFront(nil)
            // Only activate our app if the window was minimized or hidden
            if existingWindow.isMiniaturized || !existingWindow.isVisible {
                NSApp.activate(ignoringOtherApps: true)
            }
            
            // If we need to scroll to a section, update the view
            if let section = scrollToSection {
                // Post notification to scroll to section
                NotificationCenter.default.post(
                    name: NSNotification.Name("ScrollToHelpSection"),
                    object: nil,
                    userInfo: ["section": section]
                )
            }
            return
        }
        
        // Create the help content view
        let helpView = HelpWindowView(scrollToSection: scrollToSection)
        let hostingController = NSHostingController(rootView: helpView)
        
        // Create window with appropriate style
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        // Configure window
        window.title = "ImageIntact Help"
        window.contentViewController = hostingController
        window.center()
        window.setFrameAutosaveName("HelpWindow")
        window.isReleasedWhenClosed = false
        // Use normal window level - it can still be brought to front when needed
        // but won't annoyingly float above all other apps
        window.level = .normal
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .managed]
        
        // Set minimum size
        window.minSize = NSSize(width: 700, height: 500)
        
        // Store reference and show
        helpWindow = window
        window.makeKeyAndOrderFront(nil)
        // Don't force activation - let the window appear normally
        // This is less disruptive to user's workflow
        NSApp.activate(ignoringOtherApps: false)
        
        // Clean up reference when window closes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose),
            name: NSWindow.willCloseNotification,
            object: window
        )
    }
    
    @objc private func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === helpWindow {
            helpWindow = nil
        }
    }
    
    func closeHelp() {
        helpWindow?.close()
        helpWindow = nil
    }
}