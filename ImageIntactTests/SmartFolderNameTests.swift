//
//  SmartFolderNameTests.swift
//  ImageIntactTests
//
//  Direct tests for SmartFolderName, extracted from BackupManager
//  (#103 / AMUX-18). The original `extractSmartFolderName` was private;
//  these are equivalent assertions to the indirect coverage in
//  BackupOrganizationTests, now exercised on the pure helper directly.
//

import XCTest

@testable import ImageIntact

final class SmartFolderNameTests: XCTestCase {
    func testReturnsLastComponentForSimplePath() {
        let url = URL(fileURLWithPath: "/Users/me/Photos/Vacation")
        XCTAssertEqual(SmartFolderName.from(url: url), "Vacation")
    }

    func testReturnsVolumeNameForVolumePath() {
        let url = URL(fileURLWithPath: "/Volumes/Card01/DCIM")
        XCTAssertEqual(SmartFolderName.from(url: url), "Card01")
    }

    func testSkipsGenericFolderNames() {
        // The deepest non-generic component should be picked even if the
        // last component is generic.
        let url = URL(fileURLWithPath: "/Users/me/Vacation/Photos")
        XCTAssertEqual(SmartFolderName.from(url: url), "Vacation")
    }

    func testSkipsAllGenericNames() {
        // Generic at every level: photos, dcim, images, files, pictures, documents.
        // No single component is meaningful — function falls back to the last
        // component (which is still generic but at least non-empty).
        let url = URL(fileURLWithPath: "/Pictures/Photos/Images")
        // First non-generic walking backwards is the last component itself, but
        // every component is generic, so the fallback (lastPathComponent = "Images")
        // wins. Either "Images" or one of the other generics is acceptable —
        // we mainly want to assert no crash and a non-empty result.
        let result = SmartFolderName.from(url: url)
        XCTAssertFalse(result.isEmpty)
    }

    func testReplacesSpacesWithUnderscores() {
        let url = URL(fileURLWithPath: "/Users/me/My Photo Shoot")
        XCTAssertEqual(SmartFolderName.from(url: url), "My_Photo_Shoot")
    }

    func testCollapsesMultipleUnderscores() {
        let url = URL(fileURLWithPath: "/Users/me/My  Double  Spaces")
        // Two spaces → two underscores → collapsed to one.
        XCTAssertEqual(SmartFolderName.from(url: url), "My_Double_Spaces")
    }

    func testWalksBackwardsForMeaningfulName() {
        // ~/Pictures/2025/Q3/Clients/Johnson — last non-generic walking
        // backwards from the end is "Johnson".
        let url = URL(fileURLWithPath: "/Users/me/Pictures/2025/Q3/Clients/Johnson")
        XCTAssertEqual(SmartFolderName.from(url: url), "Johnson")
    }

    func testSkipsHiddenComponents() {
        // .hidden component should be skipped; previous component picked.
        let url = URL(fileURLWithPath: "/Users/me/Backups/.tmpdir")
        XCTAssertEqual(SmartFolderName.from(url: url), "Backups")
    }
}
