import Foundation

/// Protocol abstraction for drive analysis operations
protocol DriveAnalyzerProtocol {
    func analyzeDrive(at url: URL) -> DriveInfo?
    func getBSDName(for url: URL) -> String?
    func isNetworkVolume(at url: URL) -> Bool
    func getVolumeInfo(for url: URL) -> (total: Int64, available: Int64)?
}

/// Type aliases to avoid changing all the code at once
typealias DriveInfo = DriveAnalyzer.DriveInfo
typealias ConnectionType = DriveAnalyzer.ConnectionType
typealias DriveType = DriveAnalyzer.DriveType

/// Real implementation using IOKit
final class RealDriveAnalyzer: DriveAnalyzerProtocol {
    
    func analyzeDrive(at url: URL) -> DriveInfo? {
        // Use the existing static method
        return DriveAnalyzer.analyzeDrive(at: url)
    }
    
    func getBSDName(for url: URL) -> String? {
        // Use the existing static method
        return DriveAnalyzer.getBSDName(for: url)
    }
    
    func isNetworkVolume(at url: URL) -> Bool {
        // Extract the network volume check logic
        var isNetwork = false
        
        do {
            let resourceValues = try url.resourceValues(forKeys: [.volumeIsLocalKey])
            if let isLocal = resourceValues.volumeIsLocal {
                isNetwork = !isLocal
            }
        } catch {
            print("Error checking if volume is network: \(error)")
        }
        
        return isNetwork
    }
    
    func getVolumeInfo(for url: URL) -> (total: Int64, available: Int64)? {
        do {
            let resourceValues = try url.resourceValues(forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityKey
            ])
            
            let total = Int64(resourceValues.volumeTotalCapacity ?? 0)
            let available = Int64(resourceValues.volumeAvailableCapacity ?? 0)
            
            return (total: total, available: available)
        } catch {
            print("Error getting volume info: \(error)")
            return nil
        }
    }
}

/// Mock implementation for testing
final class MockDriveAnalyzer: DriveAnalyzerProtocol {
    
    /// Mock drive configurations
    var mockDrives: [URL: DriveInfo] = [:]
    var mockBSDNames: [URL: String] = [:]
    var mockNetworkVolumes: Set<URL> = []
    var mockVolumeInfo: [URL: (total: Int64, available: Int64)] = [:]
    
    /// Control behavior
    var shouldFailAnalysis = false
    var analysisCallCount = 0
    
    func analyzeDrive(at url: URL) -> DriveInfo? {
        analysisCallCount += 1
        
        if shouldFailAnalysis {
            return nil
        }
        
        // Return mock drive info if configured
        if let mockInfo = mockDrives[url] {
            return mockInfo
        }
        
        // Generate default mock drive info
        let isNetwork = mockNetworkVolumes.contains(url)
        let volumeInfo = mockVolumeInfo[url] ?? (total: 1_000_000_000_000, available: 500_000_000_000)
        
        return DriveInfo(
            mountPath: url,
            connectionType: isNetwork ? .network : .usb30,
            isSSD: !isNetwork,
            deviceName: url.lastPathComponent,
            protocolDetails: isNetwork ? "Network Share" : "USB 3.0",
            estimatedWriteSpeed: isNetwork ? 50 : 100,
            estimatedReadSpeed: isNetwork ? 55 : 110,
            volumeUUID: "MOCK-UUID-\(url.lastPathComponent)",
            hardwareSerial: isNetwork ? nil : "MOCK-SERIAL-12345",
            deviceModel: isNetwork ? nil : "Mock Drive Model",
            totalCapacity: volumeInfo.total,
            freeSpace: volumeInfo.available,
            driveType: isNetwork ? .networkDrive : .externalHDD
        )
    }
    
    func getBSDName(for url: URL) -> String? {
        if let mockName = mockBSDNames[url] {
            return mockName
        }
        
        // Generate a mock BSD name
        if url.path == "/" {
            return "disk0"
        } else if url.path.hasPrefix("/Volumes/") {
            return "disk2"
        }
        
        return nil
    }
    
    func isNetworkVolume(at url: URL) -> Bool {
        return mockNetworkVolumes.contains(url)
    }
    
    func getVolumeInfo(for url: URL) -> (total: Int64, available: Int64)? {
        return mockVolumeInfo[url]
    }
    
    // MARK: - Test Helpers
    
    func reset() {
        mockDrives.removeAll()
        mockBSDNames.removeAll()
        mockNetworkVolumes.removeAll()
        mockVolumeInfo.removeAll()
        shouldFailAnalysis = false
        analysisCallCount = 0
    }
    
    func addMockDrive(
        at url: URL,
        connectionType: ConnectionType = .usb30,
        isSSD: Bool = true,
        totalCapacity: Int64 = 1_000_000_000_000,
        freeSpace: Int64 = 500_000_000_000,
        driveType: DriveType = .externalHDD
    ) {
        let info = DriveInfo(
            mountPath: url,
            connectionType: connectionType,
            isSSD: isSSD,
            deviceName: url.lastPathComponent,
            protocolDetails: connectionType.displayName,
            estimatedWriteSpeed: connectionType.estimatedWriteSpeedMBps,
            estimatedReadSpeed: connectionType.estimatedReadSpeedMBps,
            volumeUUID: "MOCK-\(url.lastPathComponent)",
            hardwareSerial: "SERIAL-\(url.lastPathComponent)",
            deviceModel: "Mock \(driveType.suggestedLocation)",
            totalCapacity: totalCapacity,
            freeSpace: freeSpace,
            driveType: driveType
        )
        
        mockDrives[url] = info
        mockVolumeInfo[url] = (total: totalCapacity, available: freeSpace)
        
        if connectionType == .network {
            mockNetworkVolumes.insert(url)
        }
    }
    
    func addNetworkVolume(at url: URL, totalCapacity: Int64 = 10_000_000_000_000) {
        mockNetworkVolumes.insert(url)
        mockVolumeInfo[url] = (total: totalCapacity, available: totalCapacity / 2)
        
        // Also add as mock drive
        addMockDrive(
            at: url,
            connectionType: .network,
            isSSD: false,
            totalCapacity: totalCapacity,
            freeSpace: totalCapacity / 2,
            driveType: .networkDrive
        )
    }
}