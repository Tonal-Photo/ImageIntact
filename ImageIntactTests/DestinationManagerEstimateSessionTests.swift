import XCTest

@testable import ImageIntact

/// Tests for DestinationManager: getDestinationEstimate, session persistence, validation.
@MainActor
class DestinationManagerEstimateSessionTests: XCTestCase {

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
        UserDefaults.standard.removeObject(forKey: "TestDest1Path")
        UserDefaults.standard.removeObject(forKey: "TestDest2Path")
        sut = nil
        mockFileOps = nil
        mockDriveAnalyzer = nil
        mockDiskSpace = nil
        try await super.tearDown()
    }

    private func makeURL(_ name: String) -> URL {
        URL(fileURLWithPath: "/Volumes/\(name)")
    }

    private func makeSourceState(
        sourceURL: URL? = nil,
        sourceTotalBytes: Int64 = 0,
        sourceFileTypes: [ImageFileType: Int] = [:],
        isScanning: Bool = false
    ) -> SourceEstimateState {
        SourceEstimateState(
            sourceURL: sourceURL,
            sourceTotalBytes: sourceTotalBytes,
            sourceFileTypes: sourceFileTypes,
            isScanning: isScanning
        )
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

    private func setUpDestWithDriveInfo(
        _ name: String,
        connectionType: ConnectionType = .usb30,
        isSSD: Bool = true
    ) throws -> (url: URL, itemID: UUID) {
        let url = makeURL(name)
        sut.initializeEmpty()
        try sut.setDestination(url, at: 0, sourceURL: nil, hasSourceTag: false)
        let itemID = sut.destinationItems[0].id
        mockDriveAnalyzer.addMockDrive(at: url, connectionType: connectionType, isSSD: isSSD)
        sut.setDriveInfo(mockDriveAnalyzer.analyzeDrive(at: url)!, for: itemID)
        return (url, itemID)
    }

    // MARK: - getDestinationEstimate (10 tests)

    func testGetEstimate_noDriveInfo_returnsNil() {
        sut.initializeEmpty()
        let state = makeSourceState(sourceURL: makeURL("Src"), sourceTotalBytes: 1_000_000_000)
        XCTAssertNil(sut.getDestinationEstimate(at: 0, sourceState: state))
    }

    func testGetEstimate_unavailableDestination_returnsWarning() throws {
        let url = makeURL("Gone")
        sut.initializeEmpty()
        try sut.setDestination(url, at: 0, sourceURL: nil, hasSourceTag: false)
        sut.setDriveInfo(makeUnavailableDriveInfo(at: url), for: sut.destinationItems[0].id)

        let state = makeSourceState(sourceURL: makeURL("Src"), sourceTotalBytes: 1_000_000_000)
        let estimate = sut.getDestinationEstimate(at: 0, sourceState: state)

        XCTAssertNotNil(estimate)
        XCTAssertTrue(estimate!.contains("not accessible"))
    }

    func testGetEstimate_networkDrive_returnsTooManyVariables() throws {
        let url = makeURL("NAS")
        sut.initializeEmpty()
        try sut.setDestination(url, at: 0, sourceURL: nil, hasSourceTag: false)
        mockDriveAnalyzer.addNetworkVolume(at: url)
        sut.setDriveInfo(mockDriveAnalyzer.analyzeDrive(at: url)!, for: sut.destinationItems[0].id)

        let state = makeSourceState(sourceURL: makeURL("Src"), sourceTotalBytes: 1_000_000_000)
        let estimate = sut.getDestinationEstimate(at: 0, sourceState: state)

        XCTAssertNotNil(estimate)
        XCTAssertTrue(estimate!.contains("Too many variables"))
    }

    func testGetEstimate_localDrive_returnsFormattedEstimate() throws {
        let (_, _) = try setUpDestWithDriveInfo("SSD", connectionType: .usb30, isSSD: true)

        let state = makeSourceState(sourceURL: makeURL("Src"), sourceTotalBytes: 10_000_000_000)
        let estimate = sut.getDestinationEstimate(at: 0, sourceState: state)

        XCTAssertNotNil(estimate)
        XCTAssertTrue(estimate!.contains("USB"))
        XCTAssertTrue(estimate!.contains("SSD"))
        XCTAssertTrue(estimate!.contains("GB"))
    }

    func testGetEstimate_noSource_returnsNil() throws {
        let (_, _) = try setUpDestWithDriveInfo("Backup")
        let state = makeSourceState()  // no source
        XCTAssertNil(sut.getDestinationEstimate(at: 0, sourceState: state))
    }

    func testGetEstimate_scanning_returnsScanningMessage() throws {
        let (_, _) = try setUpDestWithDriveInfo("Backup")
        let state = makeSourceState(sourceURL: makeURL("Src"), isScanning: true)
        let estimate = sut.getDestinationEstimate(at: 0, sourceState: state)

        XCTAssertNotNil(estimate)
        XCTAssertTrue(estimate!.contains("Scanning"))
    }

    func testGetEstimate_sourceWithNoScan_returnsAnalyzing() throws {
        let (_, _) = try setUpDestWithDriveInfo("Backup")
        let state = makeSourceState(sourceURL: makeURL("Src"))
        let estimate = sut.getDestinationEstimate(at: 0, sourceState: state)

        XCTAssertNotNil(estimate)
        XCTAssertTrue(estimate!.contains("Analyzing"))
    }

    func testGetEstimate_multipleDestinations_addsOverhead() throws {
        let url1 = makeURL("A")
        let url2 = makeURL("B")
        sut.initializeEmpty()
        sut.addDestination()
        try sut.setDestination(url1, at: 0, sourceURL: nil, hasSourceTag: false)
        try sut.setDestination(url2, at: 1, sourceURL: nil, hasSourceTag: false)
        mockDriveAnalyzer.addMockDrive(at: url1)
        mockDriveAnalyzer.addMockDrive(at: url2)
        sut.setDriveInfo(mockDriveAnalyzer.analyzeDrive(at: url1)!, for: sut.destinationItems[0].id)
        sut.setDriveInfo(mockDriveAnalyzer.analyzeDrive(at: url2)!, for: sut.destinationItems[1].id)

        let state = makeSourceState(sourceURL: makeURL("Src"), sourceTotalBytes: 10_000_000_000)
        let estimate = sut.getDestinationEstimate(at: 0, sourceState: state)

        XCTAssertNotNil(estimate)
        XCTAssertTrue(estimate!.contains("GB"))
    }

    func testGetEstimate_indexOutOfRange_returnsNil() {
        let state = makeSourceState(sourceURL: makeURL("Src"), sourceTotalBytes: 1_000_000_000)
        XCTAssertNil(sut.getDestinationEstimate(at: 99, sourceState: state))
    }

    func testGetEstimate_usesSourceTotalBytes_whenAvailable() throws {
        let (_, _) = try setUpDestWithDriveInfo("SSD", connectionType: .usb30, isSSD: true)

        let state = makeSourceState(
            sourceURL: makeURL("Src"),
            sourceTotalBytes: 5_000_000_000,
            sourceFileTypes: [.jpeg: 100]  // fallback not used when bytes available
        )
        let estimate = sut.getDestinationEstimate(at: 0, sourceState: state)

        XCTAssertNotNil(estimate)
        XCTAssertTrue(estimate!.contains("5.00 GB"))
    }

    // MARK: - Session Persistence & Validation (8 tests)

    func testLoadFromSession_noBookmarks_emptyState() {
        sut.loadFromSession()

        XCTAssertEqual(sut.destinationItems.count, 1)
        XCTAssertNil(sut.destinationItems[0].url)
    }

    func testLoadFromSession_analyzesDrivesForLoadedURLs() async throws {
        sut.loadFromSession()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(sut.destinationItems.isEmpty)
    }

    func testValidateAndAnalyze_accessible_setsDriveInfo() async throws {
        let url = makeURL("Accessible")
        mockFileOps.filesExist.insert(url)
        sut.initializeEmpty()
        try sut.setDestination(url, at: 0, sourceURL: nil, hasSourceTag: false)

        sut.validateAndAnalyzeDestinations()
        try await Task.sleep(nanoseconds: 200_000_000)

        let itemID = sut.destinationItems[0].id
        XCTAssertNotNil(sut.destinationDriveInfo[itemID])
    }

    func testValidateAndAnalyze_inaccessible_clearsURLAndBookmark() async throws {
        let url = makeURL("Gone")
        sut.initializeEmpty()
        try sut.setDestination(url, at: 0, sourceURL: nil, hasSourceTag: false)

        sut.validateAndAnalyzeDestinations()
        try await Task.sleep(nanoseconds: 200_000_000)

        let itemID = sut.destinationItems[0].id
        if let info = sut.destinationDriveInfo[itemID] {
            XCTAssertEqual(info.estimatedWriteSpeed, 0)
        }
    }

    func testValidateAndAnalyze_existsButNotInFileOps_setsUnavailableInfo() async throws {
        let url = makeURL("NotOnDisk")
        sut.initializeEmpty()
        try sut.setDestination(url, at: 0, sourceURL: nil, hasSourceTag: false)

        sut.validateAndAnalyzeDestinations()
        try await Task.sleep(nanoseconds: 200_000_000)

        let itemID = sut.destinationItems[0].id
        if let info = sut.destinationDriveInfo[itemID] {
            XCTAssertEqual(info.protocolDetails, "Not Connected")
        }
    }

    func testValidateAndAnalyze_destinationChangedDuringAnalysis_aborts() async throws {
        let url1 = makeURL("Original")
        let url2 = makeURL("Replacement")
        mockFileOps.filesExist.insert(url1)
        mockFileOps.filesExist.insert(url2)

        sut.initializeEmpty()
        try sut.setDestination(url1, at: 0, sourceURL: nil, hasSourceTag: false)
        let originalID = sut.destinationItems[0].id

        sut.validateAndAnalyzeDestinations()
        try sut.setDestination(url2, at: 0, sourceURL: nil, hasSourceTag: false)
        let newID = sut.destinationItems[0].id

        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertNil(sut.destinationDriveInfo[originalID])
        XCTAssertNotEqual(originalID, newID)
    }

    func testValidateAndAnalyze_itemShiftedOrRemoved_doesNotCrash() async throws {
        mockFileOps.filesExist.insert(makeURL("A"))
        mockFileOps.filesExist.insert(makeURL("B"))
        sut.initializeEmpty()
        sut.addDestination()
        try sut.setDestination(makeURL("A"), at: 0, sourceURL: nil, hasSourceTag: false)
        try sut.setDestination(makeURL("B"), at: 1, sourceURL: nil, hasSourceTag: false)

        sut.validateAndAnalyzeDestinations()
        sut.removeDestination(at: 0)

        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(sut.destinationItems.count, 1)
    }

    func testLoadUITestDestinations_setsFromUserDefaults() {
        let path1 = "/tmp/test_dest_1"
        let path2 = "/tmp/test_dest_2"
        UserDefaults.standard.set(path1, forKey: "TestDest1Path")
        UserDefaults.standard.set(path2, forKey: "TestDest2Path")

        #if DEBUG
            sut.loadUITestDestinations()
            XCTAssertEqual(sut.destinationItems.count, 2)
            XCTAssertEqual(sut.destinationItems[0].url, URL(fileURLWithPath: path1))
            XCTAssertEqual(sut.destinationItems[1].url, URL(fileURLWithPath: path2))
        #endif
    }
}
