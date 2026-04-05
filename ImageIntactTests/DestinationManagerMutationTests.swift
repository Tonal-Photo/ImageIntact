import XCTest

@testable import ImageIntact

/// Tests for DestinationManager: clearDestination, removeDestination, clearAll.
@MainActor
class DestinationManagerMutationTests: XCTestCase {

    var mockFileOps: MockFileOperations!
    var mockDriveAnalyzer: MockDriveAnalyzer!
    var mockDiskSpace: MockDiskSpaceChecker!
    var sut: DestinationManager!

    override func setUp() async throws {
        try await super.setUp()
        mockFileOps = MockFileOperations()
        mockDriveAnalyzer = MockDriveAnalyzer()
        mockDiskSpace = MockDiskSpaceChecker()
        sut = DestinationManager(
            fileOperations: mockFileOps,
            driveAnalyzer: mockDriveAnalyzer,
            diskSpaceChecker: mockDiskSpace
        )
    }

    override func tearDown() async throws {
        for key in BookmarkManager.destinationKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        sut = nil
        mockFileOps = nil
        mockDriveAnalyzer = nil
        mockDiskSpace = nil
        try await super.tearDown()
    }

    private func makeURL(_ name: String) -> URL {
        URL(fileURLWithPath: "/Volumes/\(name)")
    }

    private func makeUnavailableDriveInfo(at url: URL) -> DriveAnalyzer.DriveInfo {
        DriveAnalyzer.DriveInfo(
            mountPath: url, connectionType: .unknown, isSSD: false,
            deviceName: url.lastPathComponent, protocolDetails: "Not Connected",
            estimatedWriteSpeed: 0, estimatedReadSpeed: 0,
            volumeUUID: nil, hardwareSerial: nil, deviceModel: nil,
            totalCapacity: 0, freeSpace: 0, driveType: .generic
        )
    }

    // MARK: - clearDestination (4 tests)

    func testClearDestination_setsURLToNil() throws {
        sut.initializeEmpty()
        try sut.setDestination(makeURL("Backup1"), at: 0, sourceURL: nil, hasSourceTag: false)

        sut.clearDestination(at: 0)

        XCTAssertNil(sut.destinationItems[0].url)
    }

    func testClearDestination_clearsDriveInfo() throws {
        let url = makeURL("Backup1")
        sut.initializeEmpty()
        try sut.setDestination(url, at: 0, sourceURL: nil, hasSourceTag: false)
        let itemID = sut.destinationItems[0].id
        sut.setDriveInfo(makeUnavailableDriveInfo(at: url), for: itemID)

        sut.clearDestination(at: 0)

        XCTAssertNil(sut.destinationDriveInfo[itemID])
    }

    func testClearDestination_removesBookmark() throws {
        sut.initializeEmpty()
        try sut.setDestination(makeURL("Backup1"), at: 0, sourceURL: nil, hasSourceTag: false)

        sut.clearDestination(at: 0)

        XCTAssertNil(UserDefaults.standard.data(forKey: BookmarkManager.destinationKeys[0]))
    }

    func testClearDestination_indexOutOfRange_noOp() {
        sut.initializeEmpty()
        sut.clearDestination(at: 99)
        XCTAssertEqual(sut.destinationItems.count, 1)
    }

    // MARK: - removeDestination (8 tests)

    func testRemoveDestination_removesFromArray() throws {
        sut.initializeEmpty()
        sut.addDestination()
        try sut.setDestination(makeURL("A"), at: 0, sourceURL: nil, hasSourceTag: false)
        try sut.setDestination(makeURL("B"), at: 1, sourceURL: nil, hasSourceTag: false)

        sut.removeDestination(at: 0)

        XCTAssertEqual(sut.destinationItems.count, 1)
        XCTAssertEqual(sut.destinationItems[0].url, makeURL("B"))
    }

    func testRemoveDestination_clearsDriveInfo() throws {
        let url = makeURL("Backup1")
        sut.initializeEmpty()
        sut.addDestination()
        try sut.setDestination(url, at: 0, sourceURL: nil, hasSourceTag: false)
        let itemID = sut.destinationItems[0].id
        sut.setDriveInfo(makeUnavailableDriveInfo(at: url), for: itemID)
        try sut.setDestination(makeURL("B"), at: 1, sourceURL: nil, hasSourceTag: false)

        sut.removeDestination(at: 0)

        XCTAssertNil(sut.destinationDriveInfo[itemID])
    }

    func testRemoveDestination_onlyOneItemLeft_clearsInsteadOfRemoves() throws {
        sut.initializeEmpty()
        try sut.setDestination(makeURL("A"), at: 0, sourceURL: nil, hasSourceTag: false)

        sut.removeDestination(at: 0)

        XCTAssertEqual(sut.destinationItems.count, 1)
        XCTAssertNil(sut.destinationItems[0].url)
    }

    func testRemoveDestination_reindexesBookmarks() throws {
        sut.initializeEmpty()
        sut.addDestination()
        sut.addDestination()
        try sut.setDestination(makeURL("A"), at: 0, sourceURL: nil, hasSourceTag: false)
        try sut.setDestination(makeURL("B"), at: 1, sourceURL: nil, hasSourceTag: false)
        try sut.setDestination(makeURL("C"), at: 2, sourceURL: nil, hasSourceTag: false)

        sut.removeDestination(at: 1)

        XCTAssertEqual(sut.destinationItems.count, 2)
        XCTAssertEqual(sut.destinationItems[0].url, makeURL("A"))
        XCTAssertEqual(sut.destinationItems[1].url, makeURL("C"))
    }

    func testRemoveDestination_clearsTrailingBookmarkKeys() throws {
        sut.initializeEmpty()
        sut.addDestination()
        sut.addDestination()
        try sut.setDestination(makeURL("A"), at: 0, sourceURL: nil, hasSourceTag: false)
        try sut.setDestination(makeURL("B"), at: 1, sourceURL: nil, hasSourceTag: false)
        try sut.setDestination(makeURL("C"), at: 2, sourceURL: nil, hasSourceTag: false)

        sut.removeDestination(at: 0)

        // 3 items -> 2 items. dest3Bookmark (index 2) should be cleared.
        XCTAssertNil(
            UserDefaults.standard.data(forKey: BookmarkManager.destinationKeys[2]),
            "Trailing bookmark key should be cleared after shift"
        )
    }

    func testRemoveDestination_updatesDestinationURLs() throws {
        sut.initializeEmpty()
        sut.addDestination()
        try sut.setDestination(makeURL("A"), at: 0, sourceURL: nil, hasSourceTag: false)
        try sut.setDestination(makeURL("B"), at: 1, sourceURL: nil, hasSourceTag: false)

        sut.removeDestination(at: 0)

        XCTAssertEqual(sut.destinationURLs, [makeURL("B")])
    }

    func testRemoveDestination_indexOutOfRange_noOp() {
        sut.initializeEmpty()
        sut.removeDestination(at: 99)
        XCTAssertEqual(sut.destinationItems.count, 1)
    }

    func testRemoveDestination_middleIndex() throws {
        sut.initializeEmpty()
        sut.addDestination()
        sut.addDestination()
        try sut.setDestination(makeURL("A"), at: 0, sourceURL: nil, hasSourceTag: false)
        try sut.setDestination(makeURL("B"), at: 1, sourceURL: nil, hasSourceTag: false)
        try sut.setDestination(makeURL("C"), at: 2, sourceURL: nil, hasSourceTag: false)

        sut.removeDestination(at: 1)

        XCTAssertEqual(sut.destinationItems.count, 2)
        XCTAssertEqual(sut.destinationItems[0].url, makeURL("A"))
        XCTAssertEqual(sut.destinationItems[1].url, makeURL("C"))
    }

    // MARK: - clearAll (3 tests)

    func testClearAll_resetsToSingleEmptySlot() throws {
        sut.initializeEmpty()
        sut.addDestination()
        try sut.setDestination(makeURL("A"), at: 0, sourceURL: nil, hasSourceTag: false)
        try sut.setDestination(makeURL("B"), at: 1, sourceURL: nil, hasSourceTag: false)

        sut.clearAll()

        XCTAssertEqual(sut.destinationItems.count, 1)
        XCTAssertNil(sut.destinationItems[0].url)
    }

    func testClearAll_removesDriveInfo() throws {
        sut.initializeEmpty()
        try sut.setDestination(makeURL("A"), at: 0, sourceURL: nil, hasSourceTag: false)
        let itemID = sut.destinationItems[0].id
        sut.setDriveInfo(makeUnavailableDriveInfo(at: makeURL("A")), for: itemID)

        sut.clearAll()

        XCTAssertTrue(sut.destinationDriveInfo.isEmpty)
    }

    func testClearAll_removesBookmarks() throws {
        sut.initializeEmpty()
        try sut.setDestination(makeURL("A"), at: 0, sourceURL: nil, hasSourceTag: false)

        sut.clearAll()

        for key in BookmarkManager.destinationKeys {
            XCTAssertNil(
                UserDefaults.standard.data(forKey: key),
                "Bookmark key \(key) should be cleared"
            )
        }
    }
}
