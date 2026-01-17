//
//  DebugSettingsTests.swift
//  ImageIntactTests
//

@testable import ImageIntact
import XCTest

final class DebugSettingsTests: XCTestCase {
    func testDefaultValueIsFalse() {
        let settings = DebugSettings()
        XCTAssertFalse(settings.verboseLogging, "verboseLogging should default to false")
    }

    func testToggleChangesValue() {
        let settings = DebugSettings()
        settings.verboseLogging = true
        XCTAssertTrue(settings.verboseLogging)
        settings.verboseLogging = false
        XCTAssertFalse(settings.verboseLogging)
    }

    func testSharedInstanceExists() {
        XCTAssertNotNil(DebugSettings.shared)
    }

    func testNewInstanceAlwaysStartsFalse() {
        // Simulate "restart" by creating new instance
        let settings1 = DebugSettings()
        settings1.verboseLogging = true

        let settings2 = DebugSettings()
        XCTAssertFalse(settings2.verboseLogging, "New instance should always start false (in-memory only)")
    }
}
