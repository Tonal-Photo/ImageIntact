//
//  TimeIntervalExtensions.swift
//  ImageIntact
//
//  Shared time formatting utilities to replace duplicate formatTime() implementations.
//

import Foundation

extension TimeInterval {
    /// Verbose format: "12.5 seconds", "5m 30s", "2h 15m"
    /// Used for detailed timing displays (e.g., operation summaries)
    var formattedVerbose: String {
        if self < 60 {
            return String(format: "%.1f seconds", self)
        } else if self < 3600 {
            let minutes = Int(self / 60)
            let secs = Int(truncatingRemainder(dividingBy: 60))
            return "\(minutes)m \(secs)s"
        } else {
            let hours = Int(self / 3600)
            let minutes = Int(truncatingRemainder(dividingBy: 3600) / 60)
            return "\(hours)h \(minutes)m"
        }
    }

    /// Compact format: "< 1 min", "5 min", "2h 15m"
    /// Used for ETA displays and progress indicators
    var formattedCompact: String {
        if self < 60 {
            return "< 1 min"
        } else if self < 3600 {
            let minutes = Int(self / 60)
            return "\(minutes) min"
        } else {
            let hours = Int(self / 3600)
            let minutes = Int(truncatingRemainder(dividingBy: 3600) / 60)
            return "\(hours)h \(minutes)m"
        }
    }

    /// Minimal format: "30s", "5m 30s", "2h 15m"
    /// Used for space-constrained displays
    var formattedMinimal: String {
        if self < 60 {
            return "\(Int(self))s"
        } else if self < 3600 {
            let minutes = Int(self / 60)
            let secs = Int(truncatingRemainder(dividingBy: 60))
            return "\(minutes)m \(secs)s"
        } else {
            let hours = Int(self / 3600)
            let minutes = Int(truncatingRemainder(dividingBy: 3600) / 60)
            return "\(hours)h \(minutes)m"
        }
    }
}
