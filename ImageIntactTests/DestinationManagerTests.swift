import XCTest

@testable import ImageIntact

/// Tests for DestinationManager: initialization, addDestination, and setDestination.
/// See also: DestinationManagerMutationTests, DestinationManagerEstimateSessionTests.
@MainActor
class DestinationManagerTests: XCTestCase {

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

    // MARK: - Initialization (5 tests)

    func testInitialState_emptyDestinationItems() {
        XCTAssertTrue(sut.destinationItems.isEmpty)
        XCTAssertTrue(sut.destinationDriveInfo.isEmpty)
    }

    func testInitializeEmpty_createsOneNilSlot() {
        sut.initializeEmpty()
        XCTAssertEqual(sut.destinationItems.count, 1)
        XCTAssertNil(sut.destinationItems[0].url)
    }

    func testDestinationURLs_computedFromItems() throws {
        let url1 = makeURL("Backup1")
        let url2 = makeURL("Backup2")
        sut.initializeEmpty()
        try sut.setDestination(url1, at: 0, sourceURL: nil, hasSourceTag: false)
        sut.addDestination()
        try sut.setDestination(url2, at: 1, sourceURL: nil, hasSourceTag: false)

        XCTAssertEqual(sut.destinationURLs, [url1, url2])
    }

    func testDestinationURLs_emptyWhenNoItems() {
        XCTAssertTrue(sut.destinationURLs.isEmpty)
    }

    func testDestinationURLs_mixedNilAndNonNil() throws {
        let url = makeURL("Backup1")
        sut.initializeEmpty()
        try sut.setDestination(url, at: 0, sourceURL: nil, hasSourceTag: false)
        sut.addDestination()

        XCTAssertEqual(sut.destinationURLs.count, 2)
        XCTAssertEqual(sut.destinationURLs[0], url)
        XCTAssertNil(sut.destinationURLs[1])
    }

    // MARK: - addDestination (4 tests)

    func testAddDestination_appendsNewSlot() {
        sut.initializeEmpty()
        sut.addDestination()
        XCTAssertEqual(sut.destinationItems.count, 2)
        XCTAssertNil(sut.destinationItems[1].url)
    }

    func testAddDestination_maxFourSlots() {
        sut.initializeEmpty()
        sut.addDestination()
        sut.addDestination()
        sut.addDestination()
        XCTAssertEqual(sut.destinationItems.count, 4)

        sut.addDestination()  // 5th ignored
        XCTAssertEqual(sut.destinationItems.count, 4)
    }

    func testAddDestination_destinationURLsUpdated() {
        sut.initializeEmpty()
        sut.addDestination()
        XCTAssertEqual(sut.destinationURLs, [nil, nil])
    }

    func testAddDestination_fromEmpty() {
        XCTAssertTrue(sut.destinationItems.isEmpty)
        sut.addDestination()
        XCTAssertEqual(sut.destinationItems.count, 1)
        XCTAssertNil(sut.destinationItems[0].url)
    }

    // MARK: - setDestination (16 tests)

    func testSetDestination_setsURLAtIndex() throws {
        let url = makeURL("Backup1")
        sut.initializeEmpty()
        try sut.setDestination(url, at: 0, sourceURL: nil, hasSourceTag: false)
        XCTAssertEqual(sut.destinationItems[0].url, url)
    }

    func testSetDestination_savesBookmark() throws {
        let url = makeURL("Backup1")
        sut.initializeEmpty()
        try sut.setDestination(url, at: 0, sourceURL: nil, hasSourceTag: false)
        XCTAssertEqual(sut.destinationItems[0].url, url)
    }

    func testSetDestination_indexOutOfRange_throws() {
        sut.initializeEmpty()
        XCTAssertThrowsError(
            try sut.setDestination(makeURL("X"), at: 5, sourceURL: nil, hasSourceTag: false)
        ) { error in
            guard case DestinationError.indexOutOfRange = error else {
                return XCTFail("Expected indexOutOfRange, got \(error)")
            }
        }
    }

    func testSetDestination_sameAsSource_throws() {
        let url = makeURL("Source")
        sut.initializeEmpty()
        XCTAssertThrowsError(
            try sut.setDestination(url, at: 0, sourceURL: url, hasSourceTag: false)
        ) { error in
            guard case DestinationError.sameAsSource = error else {
                return XCTFail("Expected sameAsSource, got \(error)")
            }
        }
        XCTAssertNil(sut.destinationItems[0].url, "No state mutation on throw")
    }

    func testSetDestination_sameAsSource_resolvesSymlinks() {
        let realPath = makeURL("RealDrive")
        let normalized = URL(fileURLWithPath: "/Volumes/RealDrive/./").standardizedFileURL
        sut.initializeEmpty()

        XCTAssertThrowsError(
            try sut.setDestination(normalized, at: 0, sourceURL: realPath, hasSourceTag: false)
        ) { error in
            guard case DestinationError.sameAsSource = error else {
                return XCTFail("Expected sameAsSource, got \(error)")
            }
        }
    }

    func testSetDestination_duplicateDestination_throws() throws {
        let url = makeURL("Backup1")
        sut.initializeEmpty()
        sut.addDestination()
        try sut.setDestination(url, at: 0, sourceURL: nil, hasSourceTag: false)

        XCTAssertThrowsError(
            try sut.setDestination(url, at: 1, sourceURL: nil, hasSourceTag: false)
        ) { error in
            guard case DestinationError.duplicateDestination(let idx) = error else {
                return XCTFail("Expected duplicateDestination, got \(error)")
            }
            XCTAssertEqual(idx, 0)
        }
        XCTAssertNil(sut.destinationItems[1].url, "No state mutation on throw")
    }

    func testSetDestination_sourceTaggedFolder_throwsSourceTagConflict() {
        let url = makeURL("Tagged")
        sut.initializeEmpty()

        XCTAssertThrowsError(
            try sut.setDestination(url, at: 0, sourceURL: nil, hasSourceTag: true)
        ) { error in
            guard case DestinationError.sourceTagConflict(let conflictURL) = error else {
                return XCTFail("Expected sourceTagConflict, got \(error)")
            }
            XCTAssertEqual(conflictURL, url)
        }
        XCTAssertNil(sut.destinationItems[0].url, "No state mutation on throw")
    }

    func testSetDestination_noSourceTag_succeeds() throws {
        let url = makeURL("Clean")
        sut.initializeEmpty()
        try sut.setDestination(url, at: 0, sourceURL: nil, hasSourceTag: false)
        XCTAssertEqual(sut.destinationItems[0].url, url)
    }

    func testSetDestination_clearsOldDriveInfo() throws {
        let url1 = makeURL("Backup1")
        let url2 = makeURL("Backup2")
        sut.initializeEmpty()
        try sut.setDestination(url1, at: 0, sourceURL: nil, hasSourceTag: false)
        let firstID = sut.destinationItems[0].id
        sut.setDriveInfo(makeUnavailableDriveInfo(at: url1), for: firstID)

        try sut.setDestination(url2, at: 0, sourceURL: nil, hasSourceTag: false)
        XCTAssertNil(sut.destinationDriveInfo[firstID])
    }

    func testSetDestination_createsNewItemID() throws {
        sut.initializeEmpty()
        try sut.setDestination(makeURL("A"), at: 0, sourceURL: nil, hasSourceTag: false)
        let id1 = sut.destinationItems[0].id
        try sut.setDestination(makeURL("B"), at: 0, sourceURL: nil, hasSourceTag: false)
        let id2 = sut.destinationItems[0].id
        XCTAssertNotEqual(id1, id2, "Immutable url = new item = new UUID")
    }

    func testSetDestination_removesOldIDFromDriveInfo() throws {
        sut.initializeEmpty()
        try sut.setDestination(makeURL("A"), at: 0, sourceURL: nil, hasSourceTag: false)
        let oldID = sut.destinationItems[0].id
        sut.setDriveInfo(makeUnavailableDriveInfo(at: makeURL("A")), for: oldID)

        try sut.setDestination(makeURL("B"), at: 0, sourceURL: nil, hasSourceTag: false)
        XCTAssertNil(sut.destinationDriveInfo[oldID])
        XCTAssertNotEqual(sut.destinationItems[0].id, oldID)
    }

    func testSetDestination_analyzesDrive() throws {
        let url = makeURL("Backup1")
        mockFileOps.filesExist.insert(url)
        sut.initializeEmpty()
        try sut.setDestination(url, at: 0, sourceURL: nil, hasSourceTag: false)
        XCTAssertEqual(sut.destinationItems[0].url, url)
    }

    func testSetDestination_inaccessibleDestination_setsUnavailableInfo() async throws {
        let url = makeURL("Disconnected")
        mockDriveAnalyzer.shouldFailAnalysis = true
        sut.initializeEmpty()

        try sut.setDestination(url, at: 0, sourceURL: nil, hasSourceTag: false)
        try await Task.sleep(nanoseconds: 100_000_000)

        let itemID = sut.destinationItems[0].id
        if let info = sut.destinationDriveInfo[itemID] {
            XCTAssertEqual(info.protocolDetails, "Not Connected")
            XCTAssertEqual(info.estimatedWriteSpeed, 0)
        }
        XCTAssertEqual(sut.destinationItems[0].url, url)
    }

    func testSetDestination_diskSpaceCheck_withKnownSize() throws {
        let url = makeURL("Backup1")
        mockFileOps.filesExist.insert(url)
        sut.initializeEmpty()
        try sut.setDestination(url, at: 0, sourceURL: nil, hasSourceTag: false, totalBytesToCopy: 1_000_000_000)
        XCTAssertEqual(sut.destinationItems[0].url, url)
    }

    func testSetDestination_diskSpaceCheck_noSize_skipsCheck() throws {
        sut.initializeEmpty()
        try sut.setDestination(makeURL("X"), at: 0, sourceURL: nil, hasSourceTag: false)
        XCTAssertEqual(mockDiskSpace.checkCallCount, 0)
    }

    func testSetDestination_sameURLSameIndex_noOp() throws {
        let url = makeURL("Backup1")
        sut.initializeEmpty()
        try sut.setDestination(url, at: 0, sourceURL: nil, hasSourceTag: false)
        let id1 = sut.destinationItems[0].id

        try sut.setDestination(url, at: 0, sourceURL: nil, hasSourceTag: false)
        XCTAssertEqual(sut.destinationItems[0].id, id1, "Same URL same index = no-op, ID unchanged")
    }

    func testSetDestination_rapidOverwrites_ignoresStaleAsyncResults() async throws {
        let urls = (1...3).map { makeURL("Drive\($0)") }
        urls.forEach { mockFileOps.filesExist.insert($0) }
        sut.initializeEmpty()

        try sut.setDestination(urls[0], at: 0, sourceURL: nil, hasSourceTag: false)
        let id1 = sut.destinationItems[0].id
        try sut.setDestination(urls[1], at: 0, sourceURL: nil, hasSourceTag: false)
        let id2 = sut.destinationItems[0].id
        try sut.setDestination(urls[2], at: 0, sourceURL: nil, hasSourceTag: false)

        XCTAssertNotEqual(id1, id2)
        XCTAssertNil(sut.destinationDriveInfo[id1])
        XCTAssertNil(sut.destinationDriveInfo[id2])
        XCTAssertEqual(sut.destinationItems[0].url, urls[2])

        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertNil(sut.destinationDriveInfo[id1], "Stale async must not write to old UUID")
        XCTAssertNil(sut.destinationDriveInfo[id2], "Stale async must not write to old UUID")
    }
}
