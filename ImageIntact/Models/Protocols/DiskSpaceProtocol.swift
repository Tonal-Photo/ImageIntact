import Foundation

/// Protocol abstraction for disk space checking operations
protocol DiskSpaceProtocol {
    func checkDestinationSpace(destination: URL, requiredBytes: Int64, additionalBuffer: Int64) -> DiskSpaceChecker.SpaceCheckResult
    func checkAllDestinations(destinations: [URL], requiredBytes: Int64) -> [DiskSpaceChecker.SpaceCheckResult]
    func getDiskSpaceInfo(for url: URL) -> DiskSpaceChecker.DiskSpaceInfo?
    func formatCheckResult(_ result: DiskSpaceChecker.SpaceCheckResult) -> String
    func evaluateSpaceChecks(_ results: [DiskSpaceChecker.SpaceCheckResult]) -> (canProceed: Bool, warnings: [String], errors: [String])
}

/// Real implementation using FileManager and system calls
final class RealDiskSpaceChecker: DiskSpaceProtocol {
    
    func checkDestinationSpace(destination: URL, requiredBytes: Int64, additionalBuffer: Int64 = 100_000_000) -> DiskSpaceChecker.SpaceCheckResult {
        return DiskSpaceChecker.checkDestinationSpace(destination: destination, requiredBytes: requiredBytes, additionalBuffer: additionalBuffer)
    }
    
    func checkAllDestinations(destinations: [URL], requiredBytes: Int64) -> [DiskSpaceChecker.SpaceCheckResult] {
        return DiskSpaceChecker.checkAllDestinations(destinations: destinations, requiredBytes: requiredBytes)
    }
    
    func getDiskSpaceInfo(for url: URL) -> DiskSpaceChecker.DiskSpaceInfo? {
        // This is currently private in DiskSpaceChecker, we'll need to make it internal
        // For now, we'll use checkDestinationSpace and extract the info
        let result = checkDestinationSpace(destination: url, requiredBytes: 0, additionalBuffer: 0)
        if result.spaceInfo.totalSpace > 0 {
            return result.spaceInfo
        }
        return nil
    }
    
    func formatCheckResult(_ result: DiskSpaceChecker.SpaceCheckResult) -> String {
        return DiskSpaceChecker.formatCheckResult(result)
    }
    
    func evaluateSpaceChecks(_ results: [DiskSpaceChecker.SpaceCheckResult]) -> (canProceed: Bool, warnings: [String], errors: [String]) {
        return DiskSpaceChecker.evaluateSpaceChecks(results)
    }
}

/// Mock implementation for testing
final class MockDiskSpaceChecker: DiskSpaceProtocol {
    
    /// Mock configurations
    var mockSpaceInfo: [URL: DiskSpaceChecker.DiskSpaceInfo] = [:]
    var mockHasEnoughSpace: [URL: Bool] = [:]
    var mockWarnings: [URL: String?] = [:]
    var mockErrors: [URL: String?] = [:]
    
    /// Control behavior
    var shouldFailCheck = false
    var checkCallCount = 0
    var evaluationResult: (canProceed: Bool, warnings: [String], errors: [String]) = (true, [], [])
    
    func checkDestinationSpace(destination: URL, requiredBytes: Int64, additionalBuffer: Int64 = 100_000_000) -> DiskSpaceChecker.SpaceCheckResult {
        checkCallCount += 1
        
        if shouldFailCheck {
            return DiskSpaceChecker.SpaceCheckResult(
                destination: destination,
                spaceInfo: DiskSpaceChecker.DiskSpaceInfo(
                    totalSpace: 0,
                    freeSpace: 0,
                    availableSpace: 0,
                    percentFree: 0,
                    percentAvailable: 0
                ),
                requiredSpace: requiredBytes,
                hasEnoughSpace: false,
                willHaveLessThan10PercentFree: true,
                warning: nil,
                error: "Mock error: Check failed"
            )
        }
        
        // Return configured mock data or defaults
        let spaceInfo = mockSpaceInfo[destination] ?? DiskSpaceChecker.DiskSpaceInfo(
            totalSpace: 1_000_000_000_000,  // 1TB
            freeSpace: 500_000_000_000,      // 500GB
            availableSpace: 500_000_000_000,
            percentFree: 50.0,
            percentAvailable: 50.0
        )
        
        let hasEnoughSpace = mockHasEnoughSpace[destination] ?? (spaceInfo.availableSpace >= requiredBytes + additionalBuffer)
        let warning = mockWarnings[destination] ?? nil
        let error = mockErrors[destination] ?? nil
        
        // Calculate if will have less than 10% free
        let spaceAfterBackup = spaceInfo.freeSpace > requiredBytes ? spaceInfo.freeSpace - requiredBytes : 0
        let percentFreeAfterBackup = spaceInfo.totalSpace > 0 ? (Double(spaceAfterBackup) / Double(spaceInfo.totalSpace)) * 100 : 0.0
        let willHaveLessThan10PercentFree = percentFreeAfterBackup < 10.0
        
        return DiskSpaceChecker.SpaceCheckResult(
            destination: destination,
            spaceInfo: spaceInfo,
            requiredSpace: requiredBytes,
            hasEnoughSpace: hasEnoughSpace,
            willHaveLessThan10PercentFree: willHaveLessThan10PercentFree,
            warning: warning,
            error: error
        )
    }
    
    func checkAllDestinations(destinations: [URL], requiredBytes: Int64) -> [DiskSpaceChecker.SpaceCheckResult] {
        return destinations.map { destination in
            checkDestinationSpace(destination: destination, requiredBytes: requiredBytes)
        }
    }
    
    func getDiskSpaceInfo(for url: URL) -> DiskSpaceChecker.DiskSpaceInfo? {
        return mockSpaceInfo[url]
    }
    
    func formatCheckResult(_ result: DiskSpaceChecker.SpaceCheckResult) -> String {
        let destinationName = result.destination.lastPathComponent
        
        if let error = result.error {
            return "❌ \(destinationName): \(error)"
        } else if let warning = result.warning {
            return "⚠️ \(destinationName): \(warning)"
        } else {
            return "✅ \(destinationName): \(result.spaceInfo.formattedAvailable) available"
        }
    }
    
    func evaluateSpaceChecks(_ results: [DiskSpaceChecker.SpaceCheckResult]) -> (canProceed: Bool, warnings: [String], errors: [String]) {
        return evaluationResult
    }
    
    // MARK: - Test Helpers
    
    func reset() {
        mockSpaceInfo.removeAll()
        mockHasEnoughSpace.removeAll()
        mockWarnings.removeAll()
        mockErrors.removeAll()
        shouldFailCheck = false
        checkCallCount = 0
        evaluationResult = (true, [], [])
    }
    
    func configureMockSpace(
        for url: URL,
        totalSpace: Int64 = 1_000_000_000_000,
        freeSpace: Int64 = 500_000_000_000,
        hasEnoughSpace: Bool? = nil,
        warning: String? = nil,
        error: String? = nil
    ) {
        let percentFree = Double(freeSpace) / Double(totalSpace) * 100
        
        mockSpaceInfo[url] = DiskSpaceChecker.DiskSpaceInfo(
            totalSpace: totalSpace,
            freeSpace: freeSpace,
            availableSpace: freeSpace,
            percentFree: percentFree,
            percentAvailable: percentFree
        )
        
        if let hasSpace = hasEnoughSpace {
            mockHasEnoughSpace[url] = hasSpace
        }
        
        mockWarnings[url] = warning
        mockErrors[url] = error
    }
    
    func simulateLowSpace(for url: URL) {
        configureMockSpace(
            for: url,
            totalSpace: 1_000_000_000_000,
            freeSpace: 50_000_000_000,  // 5% free
            warning: "Low disk space warning: After backup, only 4.5% will remain free"
        )
    }
    
    func simulateInsufficientSpace(for url: URL, requiredBytes: Int64 = 100_000_000_000) {
        configureMockSpace(
            for: url,
            totalSpace: 1_000_000_000_000,
            freeSpace: 10_000_000_000,  // 10GB free
            hasEnoughSpace: false,
            error: "Insufficient space: Need \(ByteCountFormatter.string(fromByteCount: requiredBytes, countStyle: .file)) but only 10 GB available"
        )
    }
}