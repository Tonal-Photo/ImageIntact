import DiskArbitration
import Foundation
import IOKit
import IOKit.storage
import IOKit.usb

// MARK: - IOKit and DiskArbitration queries (extracted for file-size limit)

extension DriveAnalyzer {

    static func isNetworkVolume(url: URL) -> Bool {
        do {
            let resourceValues = try url.resourceValues(forKeys: [.volumeIsLocalKey])
            if let isLocal = resourceValues.volumeIsLocal {
                return !isLocal
            }
        } catch {
            ApplicationLogger.shared.debug("Error checking if volume is network: \(error)", category: .hardware)
        }
        return false
    }

    static func getBSDName(for url: URL) -> String? {
        guard let session = DASessionCreate(kCFAllocatorDefault) else {
            ApplicationLogger.shared.debug("Failed to create DA session", category: .hardware)
            return nil
        }

        guard let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, url as CFURL) else {
            ApplicationLogger.shared.debug("Failed to create disk from path: \(url.path)", category: .hardware)

            if url.path.hasPrefix("/System") || url.path.hasPrefix("/Users") || url.path == "/" {
                ApplicationLogger.shared.debug("Detected system path, using fallback", category: .hardware)
                return getSystemVolumeBSDName()
            }
            return nil
        }

        guard let diskInfo = DADiskCopyDescription(disk) as? [String: Any] else {
            ApplicationLogger.shared.debug("Failed to get disk description", category: .hardware)
            return nil
        }

        ApplicationLogger.shared.debug("Disk info: \(diskInfo)", category: .hardware)

        if let bsdName = diskInfo["DAMediaBSDName"] as? String {
            ApplicationLogger.shared.debug("Found BSD name: \(bsdName)", category: .hardware)
            return bsdName
        } else if let volumePath = diskInfo["DAVolumePath"] as? URL {
            ApplicationLogger.shared.debug("Volume path: \(volumePath)", category: .hardware)
            if volumePath.path == "/" || url.path.hasPrefix(volumePath.path) {
                return getSystemVolumeBSDName()
            }
        }

        return nil
    }

    static func getSystemVolumeBSDName() -> String? {
        var statInfo = statfs()
        if statfs("/", &statInfo) == 0 {
            let device = withUnsafePointer(to: &statInfo.f_mntfromname) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { cString in
                    String(cString: cString)
                }
            }
            ApplicationLogger.shared.debug("System volume device from statfs: \(device)", category: .hardware)

            if device.hasPrefix("/dev/") {
                let bsdName = String(device.dropFirst(5))
                if let baseRange = bsdName.range(of: "s[0-9]+$", options: .regularExpression) {
                    return String(bsdName[..<baseRange.lowerBound])
                }
                return bsdName
            }
        }

        ApplicationLogger.shared.debug("Using fallback BSD name for system volume", category: .hardware)
        return "disk0"
    }

    // MARK: - Connection Type Detection

    static func findConnectionType(for service: io_object_t) -> ConnectionType {
        var parent: io_object_t = 0
        var foundPCI = false
        var foundThunderbolt = false

        var currentService = service
        IOObjectRetain(currentService)

        while IORegistryEntryGetParentEntry(currentService, kIOServicePlane, &parent) == KERN_SUCCESS {
            defer {
                IOObjectRelease(currentService)
                currentService = parent
            }

            var className = [CChar](repeating: 0, count: 128)
            IOObjectGetClass(parent, &className)
            let classString = String(cString: className)

            ApplicationLogger.shared.debug("Checking class: \(classString)", category: .hardware)

            if classString.contains("Thunderbolt") || classString.contains("Thunder") {
                foundThunderbolt = true
                ApplicationLogger.shared.debug("Found Thunderbolt in class name", category: .hardware)
            }

            if let protocolChar = IORegistryEntryCreateCFProperty(
                parent, "Protocol Characteristics" as CFString, kCFAllocatorDefault, 0
            ) {
                if let dict = protocolChar.takeRetainedValue() as? [String: Any] {
                    ApplicationLogger.shared.debug("Protocol Characteristics: \(dict)", category: .hardware)

                    if let physical = dict["Physical Interconnect"] as? String {
                        ApplicationLogger.shared.debug("Physical Interconnect: \(physical)", category: .hardware)

                        if let location = dict["Physical Interconnect Location"] as? String {
                            ApplicationLogger.shared.debug("Physical Location: \(location)", category: .hardware)
                            if location == "External" && physical.contains("PCI") {
                                ApplicationLogger.shared.debug("External PCI-Express detected - this IS Thunderbolt", category: .hardware)
                                return detectThunderboltVersion(for: parent)
                            }
                        }

                        if physical.contains("Thunderbolt") || physical.contains("Thunder") {
                            ApplicationLogger.shared.debug("Detected Thunderbolt via Protocol Characteristics", category: .hardware)
                            return .thunderbolt3
                        } else if physical.contains("USB") {
                            ApplicationLogger.shared.debug("Detected USB via Protocol Characteristics", category: .hardware)
                            return detectUSBSpeed(for: parent)
                        } else if physical.contains("PCI") {
                            if let location = dict["Physical Interconnect Location"] as? String,
                               location == "Internal"
                            {
                                ApplicationLogger.shared.debug("Internal PCI-Express - Internal drive", category: .hardware)
                                return .internalDrive
                            }
                            foundPCI = true
                        } else if physical.contains("SATA") {
                            ApplicationLogger.shared.debug("Detected SATA - Internal drive", category: .hardware)
                            return .internalDrive
                        }
                    }
                }
            }

            if let deviceType = IORegistryEntryCreateCFProperty(
                parent, "Device Type" as CFString, kCFAllocatorDefault, 0
            ) {
                if let typeString = deviceType.takeRetainedValue() as? String {
                    ApplicationLogger.shared.debug("Device Type: \(typeString)", category: .hardware)
                }
            }

            if let tbSpeed = IORegistryEntryCreateCFProperty(
                parent, "Thunderbolt Speed" as CFString, kCFAllocatorDefault, 0
            ) {
                ApplicationLogger.shared.debug("Found Thunderbolt Speed property: \(tbSpeed)", category: .hardware)
                foundThunderbolt = true
            }

            if let linkSpeed = IORegistryEntryCreateCFProperty(
                parent, "Link Speed" as CFString, kCFAllocatorDefault, 0
            ) {
                ApplicationLogger.shared.debug("Found Link Speed: \(linkSpeed)", category: .hardware)
                if let speed = linkSpeed.takeRetainedValue() as? Int {
                    if speed >= 80000 {
                        ApplicationLogger.shared.debug("Detected Thunderbolt 5 (80+ Gbps)", category: .hardware)
                        return .thunderbolt5
                    } else if speed >= 40000 {
                        ApplicationLogger.shared.debug("Detected Thunderbolt 4 (40 Gbps)", category: .hardware)
                        return .thunderbolt4
                    } else if speed >= 20000 {
                        foundThunderbolt = true
                    }
                }
            }

            if classString.contains("USB") {
                ApplicationLogger.shared.debug("Detected USB via class name", category: .hardware)
                return detectUSBSpeed(for: parent)
            }

            if classString.contains("NVMe") {
                if foundThunderbolt {
                    ApplicationLogger.shared.debug("NVMe over Thunderbolt", category: .hardware)
                    return .thunderbolt3
                }
            }
        }

        IOObjectRelease(currentService)

        if foundThunderbolt {
            ApplicationLogger.shared.debug("Final decision: Thunderbolt", category: .hardware)
            return .thunderbolt3
        } else if foundPCI {
            ApplicationLogger.shared.debug("Final decision: Unknown (PCI but unclear if external)", category: .hardware)
            return .unknown
        }

        ApplicationLogger.shared.debug("Final decision: Unknown", category: .hardware)
        return .unknown
    }

    // MARK: - Thunderbolt Version Detection

    static func detectThunderboltVersion(for service: io_object_t) -> ConnectionType {
        if isThunderbolt5SystemPresent() {
            ApplicationLogger.shared.debug("TB5 controller detected in system, assuming TB5 for external PCI-Express", category: .hardware)
            return .thunderbolt5
        }

        var parent: io_object_t = 0
        var currentService = service
        IOObjectRetain(currentService)

        var foundJHL9580 = false

        while IORegistryEntryGetParentEntry(currentService, kIOServicePlane, &parent) == KERN_SUCCESS {
            defer {
                IOObjectRelease(currentService)
                currentService = parent
            }

            var className = [CChar](repeating: 0, count: 128)
            IOObjectGetClass(parent, &className)
            let classString = String(cString: className)

            if classString.contains("JHL9580") || classString.contains("JHL9480") {
                ApplicationLogger.shared.debug("Found TB5 controller (JHL9580/9480)", category: .hardware)
                foundJHL9580 = true
            }

            if let linkCap = IORegistryEntryCreateCFProperty(
                parent, "IOPCIExpressLinkCapabilities" as CFString, kCFAllocatorDefault, 0
            ) {
                if let cap = linkCap.takeRetainedValue() as? Int {
                    ApplicationLogger.shared.debug("Found PCIe Link Capabilities: \(cap)", category: .hardware)
                    let maxSpeed = cap & 0xF
                    if maxSpeed >= 5 {
                        ApplicationLogger.shared.debug("PCIe Gen 5+ detected - likely TB5", category: .hardware)
                        IOObjectRelease(currentService)
                        return .thunderbolt5
                    }
                }
            }

            if let linkSpeed = IORegistryEntryCreateCFProperty(
                parent, "Link Speed" as CFString, kCFAllocatorDefault, 0
            ) {
                ApplicationLogger.shared.debug("Found Link Speed in TB detection: \(linkSpeed)", category: .hardware)
                if let speed = linkSpeed.takeRetainedValue() as? Int {
                    if speed >= 80000 {
                        ApplicationLogger.shared.debug("Detected Thunderbolt 5 (80+ Gbps)", category: .hardware)
                        IOObjectRelease(currentService)
                        return .thunderbolt5
                    } else if speed >= 40000 {
                        ApplicationLogger.shared.debug("Detected Thunderbolt 4 (40 Gbps)", category: .hardware)
                        IOObjectRelease(currentService)
                        return .thunderbolt4
                    }
                }
            }

            if let negotiatedSpeed = IORegistryEntryCreateCFProperty(
                parent, "Negotiated Link Speed" as CFString, kCFAllocatorDefault, 0
            ) {
                ApplicationLogger.shared.debug("Found Negotiated Link Speed: \(negotiatedSpeed)", category: .hardware)
                if let speed = negotiatedSpeed.takeRetainedValue() as? Int {
                    if speed >= 80000 {
                        IOObjectRelease(currentService)
                        return .thunderbolt5
                    } else if speed >= 40000 {
                        IOObjectRelease(currentService)
                        return .thunderbolt4
                    }
                }
            }

            if let tbGen = IORegistryEntryCreateCFProperty(
                parent, "Thunderbolt Generation" as CFString, kCFAllocatorDefault, 0
            ) {
                if let gen = tbGen.takeRetainedValue() as? Int {
                    ApplicationLogger.shared.debug("Found Thunderbolt Generation: \(gen)", category: .hardware)
                    IOObjectRelease(currentService)
                    switch gen {
                    case 5: return .thunderbolt5
                    case 4: return .thunderbolt4
                    default: return .thunderbolt3
                    }
                }
            }
        }

        IOObjectRelease(currentService)

        if foundJHL9580 {
            ApplicationLogger.shared.debug("Detected TB5 based on JHL9580 controller", category: .hardware)
            return .thunderbolt5
        }

        ApplicationLogger.shared.debug("Defaulting to Thunderbolt 3", category: .hardware)
        return .thunderbolt3
    }

    static func isThunderbolt5SystemPresent() -> Bool {
        var iterator: io_iterator_t = 0

        let matching = IOServiceMatching("IOThunderboltSwitchIntelJHL9580")
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)

        guard result == KERN_SUCCESS else { return false }
        defer { IOObjectRelease(iterator) }

        if IOIteratorNext(iterator) != 0 {
            ApplicationLogger.shared.debug("Found IOThunderboltSwitchIntelJHL9580 (TB5) in system", category: .hardware)
            return true
        }

        let matching2 = IOServiceMatching("IOThunderboltSwitchIntelJHL9480")
        var iterator2: io_iterator_t = 0
        let result2 = IOServiceGetMatchingServices(kIOMainPortDefault, matching2, &iterator2)

        guard result2 == KERN_SUCCESS else { return false }
        defer { IOObjectRelease(iterator2) }

        if IOIteratorNext(iterator2) != 0 {
            ApplicationLogger.shared.debug("Found IOThunderboltSwitchIntelJHL9480 (TB5) in system", category: .hardware)
            return true
        }

        return false
    }

    // MARK: - USB Speed Detection

    static func detectUSBSpeed(for service: io_object_t) -> ConnectionType {
        if let speedProp = IORegistryEntryCreateCFProperty(
            service, "USB Speed" as CFString, kCFAllocatorDefault, 0
        ) {
            if let speed = speedProp.takeRetainedValue() as? Int {
                switch speed {
                case 0 ... 1: return .usb2
                case 2: return .usb2
                case 3: return .usb30
                case 4: return .usb31Gen2
                case 5: return .usb32Gen2x2
                default: return .usb30
                }
            }
        }

        if let deviceSpeedProp = IORegistryEntryCreateCFProperty(
            service, "Device Speed" as CFString, kCFAllocatorDefault, 0
        ) {
            if let speed = deviceSpeedProp.takeRetainedValue() as? Int {
                switch speed {
                case 0: return .usb2
                case 1: return .usb2
                case 2: return .usb2
                case 3: return .usb30
                case 4: return .usb31Gen2
                default: return .usb30
                }
            }
        }

        return .usb30
    }
}
