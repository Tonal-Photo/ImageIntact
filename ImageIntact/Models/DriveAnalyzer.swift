import DiskArbitration
import Foundation
import IOKit
import IOKit.storage
import IOKit.usb

class DriveAnalyzer {
    enum ConnectionType: Equatable {
        case usb2
        case usb30
        case usb31Gen1
        case usb31Gen2
        case usb32Gen2x2
        case thunderbolt3
        case thunderbolt4
        case thunderbolt5
        case internalDrive
        case network
        case sdCard
        case cfCard
        case unknown

        var displayName: String {
            switch self {
            case .usb2: return "USB 2.0"
            case .usb30: return "USB 3.0"
            case .usb31Gen1: return "USB 3.1 Gen 1"
            case .usb31Gen2: return "USB 3.1 Gen 2"
            case .usb32Gen2x2: return "USB 3.2 Gen 2x2"
            case .thunderbolt3: return "Thunderbolt 3"
            case .thunderbolt4: return "Thunderbolt 4"
            case .thunderbolt5: return "Thunderbolt 5"
            case .internalDrive: return "Internal"
            case .network: return "Network"
            case .sdCard: return "SD Card"
            case .cfCard: return "CFexpress"
            case .unknown: return "Unknown"
            }
        }

        var estimatedWriteSpeedMBps: Double {
            switch self {
            case .usb2: return 20
            case .usb30: return 100
            case .usb31Gen1: return 120
            case .usb31Gen2: return 200
            case .usb32Gen2x2: return 300
            case .thunderbolt3: return 400
            case .thunderbolt4: return 500
            case .thunderbolt5: return 600
            case .internalDrive: return 300
            case .network: return 50
            case .sdCard: return 80
            case .cfCard: return 150
            case .unknown: return 80
            }
        }

        var estimatedReadSpeedMBps: Double {
            return estimatedWriteSpeedMBps * 1.1
        }
    }

    enum DriveType: Equatable {
        case portableSSD
        case externalHDD
        case cameraCard
        case cardReader
        case inCamera
        case networkDrive
        case internalDrive
        case generic

        var suggestedLocation: String {
            switch self {
            case .portableSSD: return "Portable"
            case .externalHDD: return "External Drive"
            case .cameraCard, .cardReader: return "Memory Card"
            case .inCamera: return "In Camera"
            case .networkDrive: return "Network"
            case .internalDrive: return "Internal"
            case .generic: return ""
            }
        }

        var suggestedEmoji: String {
            switch self {
            case .portableSSD: return "💾"
            case .externalHDD: return "🗄️"
            case .cameraCard, .cardReader, .inCamera: return "📷"
            case .networkDrive: return "☁️"
            case .internalDrive: return "💻"
            case .generic: return "💾"
            }
        }

        var autoBackupRecommended: Bool {
            switch self {
            case .cameraCard, .cardReader, .inCamera:
                return false
            default:
                return true
            }
        }
    }

    struct DriveInfo {
        let mountPath: URL
        let connectionType: ConnectionType
        let isSSD: Bool
        let deviceName: String
        let protocolDetails: String
        let estimatedWriteSpeed: Double
        let estimatedReadSpeed: Double
        let checksumSpeed: Double = 100

        let volumeUUID: String?
        let hardwareSerial: String?
        let deviceModel: String?

        let totalCapacity: Int64
        let freeSpace: Int64

        let driveType: DriveType

        func withFreshVolumeAttributes(url: URL, totalCapacity: Int64, freeSpace: Int64) -> DriveInfo {
            DriveInfo(mountPath: url, connectionType: connectionType, isSSD: isSSD, deviceName: deviceName,
                      protocolDetails: protocolDetails, estimatedWriteSpeed: estimatedWriteSpeed,
                      estimatedReadSpeed: estimatedReadSpeed, volumeUUID: volumeUUID,
                      hardwareSerial: hardwareSerial, deviceModel: deviceModel,
                      totalCapacity: totalCapacity, freeSpace: freeSpace, driveType: driveType)
        }

        func estimateBackupTime(totalBytes: Int64) -> TimeInterval {
            let totalMB = Double(totalBytes) / (1000 * 1000)
            let realWorldFactor = 0.95
            let effectiveCopySpeed = estimatedWriteSpeed * realWorldFactor
            let copyTime = totalMB / effectiveCopySpeed
            let verifyTime = copyTime * 0.35
            return copyTime + verifyTime
        }

        func formattedEstimate(totalBytes: Int64) -> String {
            let totalSeconds = estimateBackupTime(totalBytes: totalBytes)
            let minSeconds = totalSeconds * 0.8
            let maxSeconds = totalSeconds * 1.2

            if maxSeconds < 60 {
                return "< 1 minute"
            } else if maxSeconds < 3600 {
                let minMinutes = Int(minSeconds / 60)
                let maxMinutes = Int(ceil(maxSeconds / 60))
                if minMinutes == maxMinutes {
                    return "~\(minMinutes) minute\(minMinutes == 1 ? "" : "s")"
                } else {
                    return "\(minMinutes)-\(maxMinutes) minutes"
                }
            } else {
                let minHours = minSeconds / 3600
                let maxHours = maxSeconds / 3600
                if maxHours < 1.5 {
                    let minMinutes = Int(minSeconds / 60)
                    let maxMinutes = Int(ceil(maxSeconds / 60))
                    return "\(minMinutes)-\(maxMinutes) minutes"
                } else if maxHours < 10 {
                    return String(format: "%.1f-%.1f hours", minHours, maxHours)
                } else {
                    return String(format: "%.0f-%.0f hours", minHours, maxHours)
                }
            }
        }
    }

    // MARK: - Cache

    static let cache = DriveInfoCache()

    // MARK: - Drive Analysis

    static func analyzeDrive(at url: URL) -> DriveInfo? {
        let volumeAttributes = getVolumeAttributes(for: url)

        if let uuid = volumeAttributes.uuid, let cached = cache.get(volumeUUID: uuid) {
            return cached.withFreshVolumeAttributes(
                url: url, totalCapacity: volumeAttributes.totalCapacity, freeSpace: volumeAttributes.freeSpace
            )
        }

        if isNetworkVolume(url: url) {
            let info = DriveInfo(
                mountPath: url,
                connectionType: .network,
                isSSD: false,
                deviceName: url.lastPathComponent,
                protocolDetails: "Network Share",
                estimatedWriteSpeed: ConnectionType.network.estimatedWriteSpeedMBps,
                estimatedReadSpeed: ConnectionType.network.estimatedReadSpeedMBps,
                volumeUUID: volumeAttributes.uuid,
                hardwareSerial: nil,
                deviceModel: nil,
                totalCapacity: volumeAttributes.totalCapacity,
                freeSpace: volumeAttributes.freeSpace,
                driveType: .networkDrive
            )
            cache.store(info)
            return info
        }

        guard let bsdName = getBSDName(for: url) else {
            return nil
        }

        let props = gatherDriveProperties(bsdName: bsdName, fallbackName: url.lastPathComponent)

        let driveType = detectDriveType(
            deviceName: props.deviceName,
            deviceModel: props.deviceModel,
            connectionType: props.connectionType,
            isSSD: props.isSSD,
            capacity: volumeAttributes.totalCapacity,
            bsdName: bsdName
        )

        var finalConnectionType = props.connectionType
        if driveType == .cameraCard || driveType == .cardReader {
            if let model = props.deviceModel?.lowercased() {
                if model.contains("cfexpress") || model.contains("cfe") {
                    finalConnectionType = .cfCard
                } else if model.contains("sd") || volumeAttributes.totalCapacity <= 512_000_000_000 {
                    finalConnectionType = .sdCard
                }
            } else if volumeAttributes.totalCapacity <= 512_000_000_000 {
                finalConnectionType = .sdCard
            }
        }

        let info = DriveInfo(
            mountPath: url,
            connectionType: finalConnectionType,
            isSSD: props.isSSD,
            deviceName: props.deviceName,
            protocolDetails: props.protocolDetails,
            estimatedWriteSpeed: props.connectionType.estimatedWriteSpeedMBps,
            estimatedReadSpeed: props.connectionType.estimatedReadSpeedMBps,
            volumeUUID: volumeAttributes.uuid,
            hardwareSerial: props.hardwareSerial,
            deviceModel: props.deviceModel,
            totalCapacity: volumeAttributes.totalCapacity,
            freeSpace: volumeAttributes.freeSpace,
            driveType: driveType
        )
        cache.store(info)
        return info
    }

    // MARK: - Consolidated IOKit Lookup

    private struct DriveProperties {
        let connectionType: ConnectionType
        let isSSD: Bool
        let deviceName: String
        let protocolDetails: String
        let hardwareSerial: String?
        let deviceModel: String?
    }

    /// Single IOKit lookup replacing 4 separate IOServiceGetMatchingServices("IOMedia") scans.
    private static func gatherDriveProperties(bsdName: String, fallbackName: String) -> DriveProperties {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOBSDNameMatching(kIOMainPortDefault, 0, bsdName)
        )

        guard service != 0 else {
            return DriveProperties(
                connectionType: .unknown,
                isSSD: false,
                deviceName: fallbackName,
                protocolDetails: "Direct Attached",
                hardwareSerial: nil,
                deviceModel: nil
            )
        }

        defer { IOObjectRelease(service) }

        var serial: String?
        var model: String?
        var properties: Unmanaged<CFMutableDictionary>?
        if IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
           let props = properties?.takeRetainedValue() as? [String: Any] {
            serial = props["Serial Number"] as? String
                ?? props["USB Serial Number"] as? String
                ?? props["Device Serial"] as? String
            model = props["Model"] as? String
                ?? props["Device Model"] as? String
                ?? props["Product Name"] as? String
        }

        var isSSD = false
        if let characteristics = IORegistryEntryCreateCFProperty(
            service, "Device Characteristics" as CFString, kCFAllocatorDefault, 0
        ) {
            if let dict = characteristics.takeRetainedValue() as? [String: Any],
               let mediumType = dict["Medium Type"] as? String {
                let lower = mediumType.lowercased()
                isSSD = lower.contains("solid state") || lower.contains("ssd")
            }
        }

        var deviceName = fallbackName
        var protocolDetails = "Direct Attached"

        var parent: io_object_t = 0
        if IORegistryEntryGetParentEntry(service, kIOServicePlane, &parent) == KERN_SUCCESS {
            defer { IOObjectRelease(parent) }

            let nameKeys = ["Product Name", "USB Product Name", "Model", "kUSBProductString"]
            for key in nameKeys {
                if let prop = IORegistryEntryCreateCFProperty(parent, key as CFString, kCFAllocatorDefault, 0),
                   let name = prop.takeRetainedValue() as? String {
                    deviceName = name
                    break
                }
            }

            if !isSSD {
                if let modelProp = IORegistryEntryCreateCFProperty(parent, "Model" as CFString, kCFAllocatorDefault, 0),
                   let modelString = modelProp.takeRetainedValue() as? String {
                    let lower = modelString.lowercased()
                    isSSD = lower.contains("ssd") || lower.contains("solid") || lower.contains("nvme")
                }
            }

            if let linkSpeed = IORegistryEntryCreateCFProperty(parent, "Link Speed" as CFString, kCFAllocatorDefault, 0),
               let speed = linkSpeed.takeRetainedValue() as? String {
                protocolDetails = speed
            }
            if let negotiatedSpeed = IORegistryEntryCreateCFProperty(parent, "Negotiated Link Speed" as CFString, kCFAllocatorDefault, 0),
               let speed = negotiatedSpeed.takeRetainedValue() as? Int {
                let gbps = Double(speed) / 1000.0
                protocolDetails = String(format: "%.1f Gbps", gbps)
            }
        }

        let connectionType = findConnectionType(for: service)

        return DriveProperties(
            connectionType: connectionType,
            isSSD: isSSD,
            deviceName: deviceName,
            protocolDetails: protocolDetails,
            hardwareSerial: serial,
            deviceModel: model
        )
    }

    // MARK: - Smart Drive Type Detection (internal for testing)

    static func detectDriveType(
        deviceName: String,
        deviceModel: String?,
        connectionType: ConnectionType,
        isSSD: Bool,
        capacity: Int64,
        bsdName _: String
    ) -> DriveType {
        let lowerName = deviceName.lowercased()
        let lowerModel = deviceModel?.lowercased() ?? ""

        let camerabrands = [
            "canon", "nikon", "sony", "fujifilm", "fuji", "olympus", "panasonic", "leica", "hasselblad",
            "pentax",
        ]
        for brand in camerabrands {
            if lowerName.contains(brand) || lowerModel.contains(brand) {
                return .inCamera
            }
        }

        let cardKeywords = [
            "sd card", "sdxc", "sdhc", "cfexpress", "cfe", "compactflash", "cf card", "memory card",
            "memstick",
        ]
        for keyword in cardKeywords {
            if lowerName.contains(keyword) || lowerModel.contains(keyword) {
                return .cameraCard
            }
        }

        let readerKeywords = [
            "card reader", "cardreader", "sd reader", "cf reader", "multi-card", "multicard",
        ]
        for keyword in readerKeywords {
            if lowerName.contains(keyword) || lowerModel.contains(keyword) {
                return .cardReader
            }
        }

        let cardManufacturers = [
            "sandisk", "lexar", "prograde", "angelbird", "delkin", "sony tough", "transcend",
        ]
        for manufacturer in cardManufacturers {
            if lowerModel.contains(manufacturer) {
                if capacity <= 2_000_000_000_000 {
                    return .cameraCard
                }
            }
        }

        if capacity >= 32_000_000_000 && capacity <= 1_000_000_000_000 {
            let gbSize = capacity / 1_000_000_000
            let commonCardSizes: [Int64] = [32, 64, 128, 256, 512, 1024]
            for size in commonCardSizes {
                if gbSize >= size - 5 && gbSize <= size + 5 {
                    if connectionType == .usb2 || connectionType == .usb30 {
                        return .cardReader
                    }
                }
            }
        }

        let portableSSDKeywords = [
            "t5", "t7", "t9", "extreme pro", "extreme portable", "portable ssd", "nvme", "thunderbolt",
        ]
        for keyword in portableSSDKeywords {
            if lowerName.contains(keyword) || lowerModel.contains(keyword) {
                return .portableSSD
            }
        }

        let portableDriveManufacturers = [
            "samsung portable", "sandisk extreme", "lacie", "g-drive", "g drive", "wd passport",
            "wd my passport", "seagate backup",
        ]
        for manufacturer in portableDriveManufacturers {
            if lowerModel.contains(manufacturer) {
                return isSSD ? .portableSSD : .externalHDD
            }
        }

        switch connectionType {
        case .internalDrive:
            return .internalDrive
        case .network:
            return .networkDrive
        case .thunderbolt3, .thunderbolt4, .thunderbolt5:
            if isSSD {
                return .portableSSD
            }
        case .usb30, .usb31Gen1, .usb31Gen2, .usb32Gen2x2:
            if isSSD && capacity <= 4_000_000_000_000 {
                return .portableSSD
            } else if !isSSD {
                return .externalHDD
            }
        default:
            break
        }

        if connectionType == .internalDrive {
            return .internalDrive
        } else if isSSD {
            return .portableSSD
        } else {
            return .externalHDD
        }
    }

    // MARK: - Volume Attributes

    private struct VolumeAttributes {
        let uuid: String?
        let totalCapacity: Int64
        let freeSpace: Int64
    }

    private static func getVolumeAttributes(for url: URL) -> VolumeAttributes {
        var uuid: String?
        var totalCapacity: Int64 = 0
        var freeSpace: Int64 = 0

        do {
            let resourceKeys: [URLResourceKey] = [
                .volumeUUIDStringKey,
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityKey,
            ]

            let resourceValues = try url.resourceValues(forKeys: Set(resourceKeys))
            uuid = resourceValues.volumeUUIDString
            totalCapacity = Int64(resourceValues.volumeTotalCapacity ?? 0)
            freeSpace = Int64(resourceValues.volumeAvailableCapacity ?? 0)
        } catch {
            logError("Failed to get volume attributes: \(error)")
        }

        return VolumeAttributes(uuid: uuid, totalCapacity: totalCapacity, freeSpace: freeSpace)
    }
}
