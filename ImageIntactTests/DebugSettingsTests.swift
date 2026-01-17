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

    func testVerboseLoggingChangesApplicationLoggerLevel() {
        let settings = DebugSettings.shared
        let logger = ApplicationLogger.shared

        // Start with verbose off
        settings.verboseLogging = false
        XCTAssertNotEqual(logger.minimumLogLevel, .debug, "Should not be debug when verbose is off")

        // Turn verbose on
        settings.verboseLogging = true

        // Give Combine time to propagate
        let expectation = XCTestExpectation(description: "Log level changes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(logger.minimumLogLevel, .debug, "Should be debug when verbose is on")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        // Clean up
        settings.verboseLogging = false
    }
}
