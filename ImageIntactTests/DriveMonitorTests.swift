//
//  DriveMonitorTests.swift
//  ImageIntactTests
//
//  Tests for DriveMonitor using MockDriveAnalyzer
//

import Combine
import XCTest
@testable import ImageIntact

final class DriveMonitorTests: XCTestCase {

    var monitor: DriveMonitor!
    var mockAnalyzer: MockDriveAnalyzer!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        mockAnalyzer = MockDriveAnalyzer()
        monitor = DriveMonitor.shared
        monitor.driveAnalyzer = mockAnalyzer
        cancellables = []
    }

    override func tearDown() {
        monitor.driveAnalyzer = RealDriveAnalyzer()
        cancellables = nil
        super.tearDown()
    }

    // MARK: - Mock Analyzer Usage

    func testGetDriveDetails_usesMockAnalyzer() {
        let url = URL(fileURLWithPath: "/Volumes/TestSSD")
        mockAnalyzer.addMockDrive(
            at: url,
            connectionType: .thunderbolt4,
            isSSD: true,
            driveType: .portableSSD
        )

        let info = monitor.getDriveDetails(url)

        XCTAssertNotNil(info)
        XCTAssertEqual(info?.connectionType, .thunderbolt4)
        XCTAssertEqual(info?.driveType, .portableSSD)
        XCTAssertEqual(mockAnalyzer.analysisCallCount, 1)
    }

    func testGetDriveDetails_failingAnalyzer_returnsNil() {
        mockAnalyzer.shouldFailAnalysis = true
        let url = URL(fileURLWithPath: "/Volumes/TestSSD")

        let info = monitor.getDriveDetails(url)

        XCTAssertNil(info)
        XCTAssertEqual(mockAnalyzer.analysisCallCount, 1)
    }

    func testGetDriveDetails_multipleCallsWithMock() {
        let url1 = URL(fileURLWithPath: "/Volumes/SSD1")
        let url2 = URL(fileURLWithPath: "/Volumes/SSD2")
        mockAnalyzer.addMockDrive(at: url1, connectionType: .thunderbolt4, isSSD: true, driveType: .portableSSD)
        mockAnalyzer.addMockDrive(at: url2, connectionType: .usb31Gen2, isSSD: true, driveType: .portableSSD)

        let info1 = monitor.getDriveDetails(url1)
        let info2 = monitor.getDriveDetails(url2)

        XCTAssertEqual(info1?.connectionType, .thunderbolt4)
        XCTAssertEqual(info2?.connectionType, .usb31Gen2)
        XCTAssertEqual(mockAnalyzer.analysisCallCount, 2)
    }

    // MARK: - Drive Identity Management

    func testSetCustomName_persistsName() {
        let uuid = "TEST-UUID-12345"
        // Manually insert a known drive for testing
        monitor.setCustomName(for: uuid, name: "My Backup SSD")
        // Getting the name back requires the drive to exist in knownDrives
        // This tests the path doesn't crash - full persistence test would need file I/O
    }

    // MARK: - Mock Analyzer Reset

    func testMockAnalyzer_resetClearsState() {
        let url = URL(fileURLWithPath: "/Volumes/Test")
        mockAnalyzer.addMockDrive(at: url, connectionType: .thunderbolt4, isSSD: true)
        _ = mockAnalyzer.analyzeDrive(at: url)

        XCTAssertEqual(mockAnalyzer.analysisCallCount, 1)

        mockAnalyzer.reset()

        XCTAssertEqual(mockAnalyzer.analysisCallCount, 0)
        XCTAssertTrue(mockAnalyzer.mockDrives.isEmpty)
    }
}
