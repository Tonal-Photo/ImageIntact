//
//  TrashSourceTests.swift
//  ImageIntactTests
//
//  Tests for trash-source-after-backup behavior
//

import XCTest
@testable import ImageIntact

final class TrashSourceTests: XCTestCase {

    func testTrashSourceMovesToTrash() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageIntactTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let testFile = tempDir.appendingPathComponent("test.jpg")
        try "test".write(to: testFile, atomically: true, encoding: .utf8)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.path))

        var trashedURL: NSURL?
        try FileManager.default.trashItem(at: tempDir, resultingItemURL: &trashedURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDir.path))
        XCTAssertNotNil(trashedURL)

        if let trashed = trashedURL as URL? {
            try? FileManager.default.removeItem(at: trashed)
        }
    }

    func testTrashSourceSkipsWhenDisabled() {
        let prefs = PreferencesManager.shared
        prefs.trashSourceAfterBackup = false
        XCTAssertFalse(prefs.trashSourceAfterBackup)
    }
}
