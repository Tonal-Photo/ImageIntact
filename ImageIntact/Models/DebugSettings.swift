//
//  DebugSettings.swift
//  ImageIntact
//
//  In-memory debug settings that reset on app restart
//

import Combine
import Foundation

class DebugSettings: ObservableObject {
    static let shared = DebugSettings()

    /// When true, forces ApplicationLogger to show debug-level messages.
    /// Resets to false on app restart (in-memory only, not persisted).
    @Published var verboseLogging: Bool = false
}
