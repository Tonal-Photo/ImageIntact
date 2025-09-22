//
//  TroubleshootingWindowManager.swift
//  ImageIntact
//
//  Manages the troubleshooting window
//

import SwiftUI
import AppKit

class TroubleshootingWindowManager: ObservableObject {
    static let shared = TroubleshootingWindowManager()
    private var troubleshootingWindow: NSWindow?

    private init() {}

    func showTroubleshooting() {
        if let existingWindow = troubleshootingWindow {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        let contentView = TroubleshootingView()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Troubleshooting Guide"
        window.contentView = NSHostingView(rootView: contentView)
        window.center()
        window.setFrameAutosaveName("TroubleshootingWindow")
        window.isReleasedWhenClosed = false

        // Set minimum size
        window.minSize = NSSize(width: 700, height: 500)

        window.makeKeyAndOrderFront(nil)
        self.troubleshootingWindow = window
    }
}