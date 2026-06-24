//
//  HelpWindowViewTests.swift
//  ImageIntactTests
//
//  Tests for HelpWindowView's version-display helper and topic structure.
//

import XCTest
@testable import ImageIntact

@MainActor
final class HelpWindowViewTests: XCTestCase {

    // MARK: - displayVersion(shortVersion:)

    func testDisplayVersionReturnsShortVersionWhenPresent() {
        XCTAssertEqual(HelpWindowView.displayVersion(shortVersion: "1.4.0"), "1.4.0")
    }

    func testDisplayVersionFallsBackWhenNil() {
        XCTAssertEqual(HelpWindowView.displayVersion(shortVersion: nil), "Unknown")
    }

    func testDisplayVersionFallsBackWhenEmpty() {
        XCTAssertEqual(HelpWindowView.displayVersion(shortVersion: ""), "Unknown")
    }

    // MARK: - Topic structure

    /// The Updates topic is retained (now documents Mac App Store updates), so users
    /// searching "update"/"version" still find it.
    func testUpdatesTopicIsPreserved() {
        XCTAssertTrue(HelpWindowView.HelpSectionID.allCases.contains(.updates))
    }
}
