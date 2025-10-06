//
//  ProgressPerformanceMonitor.swift
//  ImageIntact
//
//  Performance monitoring for ProgressPublisher updates
//

import Foundation
import Combine

/// Monitors performance metrics of the progress system
@MainActor
final class ProgressPerformanceMonitor: ObservableObject {
    static let shared = ProgressPerformanceMonitor()

    // MARK: - Metrics
    @Published private(set) var updateFrequency: Double = 0.0 // Updates per second
    @Published private(set) var peakUpdateFrequency: Double = 0.0
    @Published private(set) var totalUpdates: Int = 0
    @Published private(set) var droppedUpdates: Int = 0
    @Published private(set) var averageUpdateInterval: TimeInterval = 0.0

    // MARK: - Private State
    private var updateTimes: [Date] = []
    private let maxUpdateHistory = 100
    private var lastUpdateTime: Date?
    private var cancellables = Set<AnyCancellable>()
    private var isMonitoring = false
    private var startTime: Date?

    // Update intervals tracking
    private var updateIntervals: [TimeInterval] = []
    private let maxIntervalHistory = 50

    private init() {}

    /// Start monitoring ProgressPublisher
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        startTime = Date()
        resetMetrics()

        // Monitor all published properties of ProgressPublisher
        let publisher = ProgressPublisher.shared

        // Track overall progress updates
        publisher.$overallProgress
            .sink { [weak self] _ in
                self?.recordUpdate(type: "overallProgress")
            }
            .store(in: &cancellables)

        // Track file progress updates
        publisher.$processedFiles
            .sink { [weak self] _ in
                self?.recordUpdate(type: "processedFiles")
            }
            .store(in: &cancellables)

        // Track destination updates
        publisher.$destinations
            .sink { [weak self] _ in
                self?.recordUpdate(type: "destinations")
            }
            .store(in: &cancellables)

        // Track phase changes
        publisher.$currentPhase
            .sink { [weak self] phase in
                self?.recordUpdate(type: "phase:\(phase)")
            }
            .store(in: &cancellables)

        print("📊 Performance monitoring started")
    }

    /// Stop monitoring
    func stopMonitoring() {
        isMonitoring = false
        cancellables.removeAll()
        print("📊 Performance monitoring stopped")
        printReport()
    }

    /// Record an update event
    private func recordUpdate(type: String) {
        let now = Date()
        totalUpdates += 1

        // Track update time
        updateTimes.append(now)
        if updateTimes.count > maxUpdateHistory {
            updateTimes.removeFirst()
        }

        // Calculate update interval
        if let last = lastUpdateTime {
            let interval = now.timeIntervalSince(last)
            updateIntervals.append(interval)
            if updateIntervals.count > maxIntervalHistory {
                updateIntervals.removeFirst()
            }

            // Update average interval
            if !updateIntervals.isEmpty {
                averageUpdateInterval = updateIntervals.reduce(0, +) / Double(updateIntervals.count)
            }
        }
        lastUpdateTime = now

        // Calculate current frequency (updates in last second)
        let oneSecondAgo = now.addingTimeInterval(-1)
        let recentUpdates = updateTimes.filter { $0 > oneSecondAgo }
        updateFrequency = Double(recentUpdates.count)

        // Track peak frequency
        if updateFrequency > peakUpdateFrequency {
            peakUpdateFrequency = updateFrequency
        }

        // Log high-frequency updates (potential performance issue)
        if updateFrequency > 30 {
            print("⚠️ High update frequency detected: \(Int(updateFrequency)) updates/sec for \(type)")
            droppedUpdates += 1 // Consider this a potential issue
        }
    }

    /// Reset all metrics
    private func resetMetrics() {
        updateFrequency = 0
        peakUpdateFrequency = 0
        totalUpdates = 0
        droppedUpdates = 0
        averageUpdateInterval = 0
        updateTimes.removeAll()
        updateIntervals.removeAll()
        lastUpdateTime = nil
    }

    /// Generate a performance report
    func generateReport() -> String {
        var report: [String] = []

        report.append("=== Progress System Performance Report ===")
        report.append("")

        if let start = startTime {
            let duration = Date().timeIntervalSince(start)
            report.append("Monitoring Duration: \(String(format: "%.1f", duration)) seconds")
        }

        report.append("Total Updates: \(totalUpdates)")
        report.append("Current Frequency: \(String(format: "%.1f", updateFrequency)) updates/sec")
        report.append("Peak Frequency: \(String(format: "%.1f", peakUpdateFrequency)) updates/sec")
        report.append("Average Interval: \(String(format: "%.3f", averageUpdateInterval)) seconds")

        if droppedUpdates > 0 {
            report.append("⚠️ Potential Issues: \(droppedUpdates) high-frequency bursts")
        }

        // Calculate efficiency
        if totalUpdates > 0 && startTime != nil {
            let duration = Date().timeIntervalSince(startTime!)
            let avgFrequency = Double(totalUpdates) / duration
            report.append("Average Frequency: \(String(format: "%.1f", avgFrequency)) updates/sec")

            // Determine health status
            let health: String
            if avgFrequency < 1 {
                health = "❄️ Too Infrequent (may appear frozen)"
            } else if avgFrequency < 5 {
                health = "✅ Optimal"
            } else if avgFrequency < 15 {
                health = "⚡ Good (slightly high)"
            } else if avgFrequency < 30 {
                health = "⚠️ High (may impact performance)"
            } else {
                health = "🔥 Excessive (performance impact likely)"
            }
            report.append("Health Status: \(health)")
        }

        report.append("")
        report.append("=== End Performance Report ===")

        return report.joined(separator: "\n")
    }

    /// Print report to console
    func printReport() {
        print(generateReport())
    }
}

// MARK: - Debug Commands
#if DEBUG
extension ProgressPerformanceMonitor {

    /// Start monitoring from console
    /// Usage: po ProgressPerformanceMonitor.start()
    static func start() {
        Task { @MainActor in
            shared.startMonitoring()
        }
    }

    /// Stop and print report
    /// Usage: po ProgressPerformanceMonitor.stop()
    static func stop() {
        Task { @MainActor in
            shared.stopMonitoring()
        }
    }

    /// Get current metrics
    /// Usage: po ProgressPerformanceMonitor.metrics()
    static func metrics() {
        Task { @MainActor in
            let m = shared
            print("📊 Current Metrics:")
            print("  Frequency: \(String(format: "%.1f", m.updateFrequency)) updates/sec")
            print("  Total: \(m.totalUpdates) updates")
            print("  Peak: \(String(format: "%.1f", m.peakUpdateFrequency)) updates/sec")
            print("  Avg Interval: \(String(format: "%.3f", m.averageUpdateInterval))s")
        }
    }
}
#endif