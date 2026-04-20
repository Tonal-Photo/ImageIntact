//
//  DriveAnalyzerTests.swift
//  ImageIntactTests
//
//  Tests for DriveAnalyzer: drive type detection, time estimation, cache behavior
//

import XCTest
@testable import ImageIntact

final class DriveAnalyzerTests: XCTestCase {

    // MARK: - Drive Type Detection

    func testDetectDriveType_cameraInName_returnsInCamera() {
        let result = DriveAnalyzer.detectDriveType(
            deviceName: "Canon EOS R5",
            deviceModel: nil,
            connectionType: .usb30,
            isSSD: false,
            capacity: 64_000_000_000,
            bsdName: "disk2"
        )
        XCTAssertEqual(result, .inCamera)
    }

    func testDetectDriveType_hasselblad_returnsInCamera() {
        let result = DriveAnalyzer.detectDriveType(
            deviceName: "Hasselblad X2D",
            deviceModel: nil,
            connectionType: .usb30,
            isSSD: false,
            capacity: 64_000_000_000,
            bsdName: "disk2"
        )
        XCTAssertEqual(result, .inCamera)
    }

    func testDetectDriveType_sdCard_returnsCameraCard() {
        let result = DriveAnalyzer.detectDriveType(
            deviceName: "SDXC Card",
            deviceModel: nil,
            connectionType: .usb30,
            isSSD: false,
            capacity: 128_000_000_000,
            bsdName: "disk2"
        )
        XCTAssertEqual(result, .cameraCard)
    }

    func testDetectDriveType_cardReader_returnsCardReader() {
        let result = DriveAnalyzer.detectDriveType(
            deviceName: "USB Card Reader",
            deviceModel: nil,
            connectionType: .usb30,
            isSSD: false,
            capacity: 64_000_000_000,
            bsdName: "disk2"
        )
        XCTAssertEqual(result, .cardReader)
    }

    func testDetectDriveType_samsungT7_returnsPortableSSD() {
        let result = DriveAnalyzer.detectDriveType(
            deviceName: "Samsung T7",
            deviceModel: nil,
            connectionType: .usb31Gen2,
            isSSD: true,
            capacity: 1_000_000_000_000,
            bsdName: "disk2"
        )
        XCTAssertEqual(result, .portableSSD)
    }

    func testDetectDriveType_thunderboltSSD_returnsPortableSSD() {
        let result = DriveAnalyzer.detectDriveType(
            deviceName: "External Drive",
            deviceModel: nil,
            connectionType: .thunderbolt4,
            isSSD: true,
            capacity: 2_000_000_000_000,
            bsdName: "disk2"
        )
        XCTAssertEqual(result, .portableSSD)
    }

    func testDetectDriveType_internalDrive_returnsInternal() {
        let result = DriveAnalyzer.detectDriveType(
            deviceName: "APPLE SSD",
            deviceModel: nil,
            connectionType: .internalDrive,
            isSSD: true,
            capacity: 1_000_000_000_000,
            bsdName: "disk0"
        )
        XCTAssertEqual(result, .internalDrive)
    }

    func testDetectDriveType_networkDrive_returnsNetwork() {
        let result = DriveAnalyzer.detectDriveType(
            deviceName: "NAS Share",
            deviceModel: nil,
            connectionType: .network,
            isSSD: false,
            capacity: 10_000_000_000_000,
            bsdName: "disk2"
        )
        XCTAssertEqual(result, .networkDrive)
    }

    func testDetectDriveType_usbHDD_returnsExternalHDD() {
        let result = DriveAnalyzer.detectDriveType(
            deviceName: "WD Elements",
            deviceModel: nil,
            connectionType: .usb30,
            isSSD: false,
            capacity: 4_000_000_000_000,
            bsdName: "disk2"
        )
        XCTAssertEqual(result, .externalHDD)
    }

    func testDetectDriveType_cfexpress_returnsCameraCard() {
        let result = DriveAnalyzer.detectDriveType(
            deviceName: "CFexpress Card",
            deviceModel: nil,
            connectionType: .usb31Gen2,
            isSSD: true,
            capacity: 256_000_000_000,
            bsdName: "disk2"
        )
        XCTAssertEqual(result, .cameraCard)
    }

    func testDetectDriveType_sandiskModel_returnsCameraCard() {
        let result = DriveAnalyzer.detectDriveType(
            deviceName: "External",
            deviceModel: "SanDisk Extreme Pro 128GB",
            connectionType: .usb30,
            isSSD: true,
            capacity: 128_000_000_000,
            bsdName: "disk2"
        )
        XCTAssertEqual(result, .cameraCard)
    }

    // MARK: - Backup Time Estimation

    func testEstimateBackupTime_thunderbolt4_1GB() {
        let info = makeDriveInfo(connectionType: .thunderbolt4, isSSD: true)
        let time = info.estimateBackupTime(totalBytes: 1_000_000_000)
        // 1 GB at ~500 MB/s * 0.95 = ~475 MB/s copy + 35% verify
        // Copy: 1000/475 = ~2.1s, Verify: ~0.7s, Total: ~2.8s
        XCTAssertGreaterThan(time, 1.0)
        XCTAssertLessThan(time, 10.0)
    }

    func testEstimateBackupTime_usb2_10GB() {
        let info = makeDriveInfo(connectionType: .usb2, isSSD: false)
        let time = info.estimateBackupTime(totalBytes: 10_000_000_000)
        // 10 GB at ~20 MB/s = ~500s copy + verify
        XCTAssertGreaterThan(time, 400.0)
        XCTAssertLessThan(time, 1000.0)
    }

    func testEstimateBackupTime_zeroBytes() {
        let info = makeDriveInfo(connectionType: .thunderbolt4, isSSD: true)
        let time = info.estimateBackupTime(totalBytes: 0)
        XCTAssertEqual(time, 0.0, accuracy: 0.001)
    }

    // MARK: - Formatted Estimate

    func testFormattedEstimate_underOneMinute() {
        let info = makeDriveInfo(connectionType: .thunderbolt4, isSSD: true)
        let formatted = info.formattedEstimate(totalBytes: 100_000_000) // 100 MB
        XCTAssertEqual(formatted, "< 1 minute")
    }

    func testFormattedEstimate_minutes() {
        let info = makeDriveInfo(connectionType: .usb2, isSSD: false)
        let formatted = info.formattedEstimate(totalBytes: 5_000_000_000) // 5 GB over USB 2
        XCTAssertTrue(formatted.contains("minute"))
    }

    func testFormattedEstimate_hours() {
        let info = makeDriveInfo(connectionType: .usb2, isSSD: false)
        let formatted = info.formattedEstimate(totalBytes: 500_000_000_000) // 500 GB over USB 2
        XCTAssertTrue(formatted.contains("hour"))
    }

    // MARK: - Connection Type Properties

    func testConnectionType_writeSpeedOrdering() {
        let types: [ConnectionType] = [.usb2, .usb30, .usb31Gen1, .usb31Gen2, .thunderbolt3, .thunderbolt4, .thunderbolt5]
        for i in 0..<(types.count - 1) {
            XCTAssertLessThan(
                types[i].estimatedWriteSpeedMBps,
                types[i + 1].estimatedWriteSpeedMBps,
                "\(types[i].displayName) should be slower than \(types[i + 1].displayName)"
            )
        }
    }

    func testConnectionType_readFasterThanWrite() {
        let types: [ConnectionType] = [.usb30, .thunderbolt4, .internalDrive, .network]
        for type in types {
            XCTAssertGreaterThan(
                type.estimatedReadSpeedMBps,
                type.estimatedWriteSpeedMBps,
                "\(type.displayName) read should be faster than write"
            )
        }
    }

    // MARK: - DriveInfo Cache

    func testDriveInfoCache_hitOnSameUUID() {
        let cache = DriveInfoCache()
        let info = makeDriveInfo(connectionType: .thunderbolt4, isSSD: true, volumeUUID: "UUID-123")
        cache.store(info)

        let cached = cache.get(volumeUUID: "UUID-123")
        XCTAssertNotNil(cached)
        XCTAssertEqual(cached?.connectionType, .thunderbolt4)
    }

    func testDriveInfoCache_missOnDifferentUUID() {
        let cache = DriveInfoCache()
        let info = makeDriveInfo(connectionType: .thunderbolt4, isSSD: true, volumeUUID: "UUID-123")
        cache.store(info)

        let cached = cache.get(volumeUUID: "UUID-999")
        XCTAssertNil(cached)
    }

    func testDriveInfoCache_invalidateByUUID() {
        let cache = DriveInfoCache()
        let info = makeDriveInfo(connectionType: .thunderbolt4, isSSD: true, volumeUUID: "UUID-123")
        cache.store(info)

        cache.invalidate(volumeUUID: "UUID-123")

        let cached = cache.get(volumeUUID: "UUID-123")
        XCTAssertNil(cached)
    }

    func testDriveInfoCache_invalidateAll() {
        let cache = DriveInfoCache()
        cache.store(makeDriveInfo(connectionType: .thunderbolt4, isSSD: true, volumeUUID: "UUID-1"))
        cache.store(makeDriveInfo(connectionType: .usb30, isSSD: false, volumeUUID: "UUID-2"))

        cache.invalidateAll()

        XCTAssertNil(cache.get(volumeUUID: "UUID-1"))
        XCTAssertNil(cache.get(volumeUUID: "UUID-2"))
    }

    func testDriveInfoCache_nilUUID_notCached() {
        let cache = DriveInfoCache()
        let info = makeDriveInfo(connectionType: .thunderbolt4, isSSD: true, volumeUUID: nil)
        cache.store(info)

        // Can't retrieve without a UUID
        XCTAssertEqual(cache.count, 0)
    }

    func testDriveInfoCache_updateExisting() {
        let cache = DriveInfoCache()
        cache.store(makeDriveInfo(connectionType: .usb30, isSSD: false, volumeUUID: "UUID-1"))
        cache.store(makeDriveInfo(connectionType: .thunderbolt4, isSSD: true, volumeUUID: "UUID-1"))

        let cached = cache.get(volumeUUID: "UUID-1")
        XCTAssertEqual(cached?.connectionType, .thunderbolt4)
        XCTAssertEqual(cache.count, 1)
    }

    // MARK: - Helpers

    private func makeDriveInfo(
        connectionType: ConnectionType,
        isSSD: Bool,
        volumeUUID: String? = "TEST-UUID"
    ) -> DriveInfo {
        DriveInfo(
            mountPath: URL(fileURLWithPath: "/Volumes/TestDrive"),
            connectionType: connectionType,
            isSSD: isSSD,
            deviceName: "Test Drive",
            protocolDetails: connectionType.displayName,
            estimatedWriteSpeed: connectionType.estimatedWriteSpeedMBps,
            estimatedReadSpeed: connectionType.estimatedReadSpeedMBps,
            volumeUUID: volumeUUID,
            hardwareSerial: "SERIAL-123",
            deviceModel: "Test Model",
            totalCapacity: 1_000_000_000_000,
            freeSpace: 500_000_000_000,
            driveType: isSSD ? .portableSSD : .externalHDD
        )
    }
}
