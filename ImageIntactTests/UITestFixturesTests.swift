//
//  UITestFixturesTests.swift
//  ImageIntactTests
//
//  Unit tests for the UI-test fixture seam (UITestFixtures).
//  See .planning/design/ui-test-suite.md.
//

import XCTest

@testable import ImageIntact

final class UITestFixturesTests: XCTestCase {

  private var markedRoot: URL!
  private var defaults: UserDefaults!
  private let suiteName = "UITestFixturesTests"

  override func setUpWithError() throws {
    markedRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("imageintact-uitest-unit-\(UUID().uuidString)")
    defaults = UserDefaults(suiteName: suiteName)
    defaults.removePersistentDomain(forName: suiteName)
  }

  override func tearDownWithError() throws {
    if let markedRoot { try? FileManager.default.removeItem(at: markedRoot) }
    defaults.removePersistentDomain(forName: suiteName)
  }

  // MARK: - Seam activation

  func testSeamIsActive_requiresExactUITestArgument() {
    XCTAssertTrue(UITestSeam.isActive(arguments: ["--uitest"]))
    XCTAssertTrue(UITestSeam.isActive(arguments: ["-hasSeenWelcome", "YES", "--uitest"]))
    XCTAssertFalse(UITestSeam.isActive(arguments: []))
    // Exact element match only: a flag that merely contains the prefix
    // (e.g. --uitest-reset alone) must not arm the seam.
    XCTAssertFalse(UITestSeam.isActive(arguments: ["--uitest-reset"]))
  }

  // MARK: - Spec parsing

  func testParseSpec_fullForm() {
    let spec = UITestFixtures.parseSpec("src=6,dests=2,prefill=exact")
    XCTAssertEqual(spec, UITestFixtures.Spec(sourceCount: 6, destCount: 2, prefill: .exact))
  }

  func testParseSpec_defaultsDestsToOneAndPrefillToNone() {
    let spec = UITestFixtures.parseSpec("src=3")
    XCTAssertEqual(spec, UITestFixtures.Spec(sourceCount: 3, destCount: 1, prefill: .none))
  }

  func testParseSpec_rejectsGarbage() {
    XCTAssertNil(UITestFixtures.parseSpec(""))
    XCTAssertNil(UITestFixtures.parseSpec("dests=2"))  // src is mandatory
    XCTAssertNil(UITestFixtures.parseSpec("src=zero"))
    XCTAssertNil(UITestFixtures.parseSpec("src=6,prefill=bogus"))
  }

  func testParseSpec_boundsCounts() {
    XCTAssertNil(UITestFixtures.parseSpec("src=0"))
    XCTAssertNil(UITestFixtures.parseSpec("src=10000"))
    XCTAssertNil(UITestFixtures.parseSpec("src=6,dests=0"))
    XCTAssertNil(UITestFixtures.parseSpec("src=6,dests=9"))
  }

  // MARK: - Path guard

  func testIsUITestPath_requiresMarker() {
    XCTAssertTrue(UITestFixtures.isUITestPath(markedRoot))
    XCTAssertTrue(UITestFixtures.isUITestPath(markedRoot.appendingPathComponent("source")))
    XCTAssertFalse(UITestFixtures.isUITestPath(URL(fileURLWithPath: "/tmp/plain-folder")))
  }

  func testGenerate_refusesUnmarkedDirectory() {
    let unmarked = FileManager.default.temporaryDirectory
      .appendingPathComponent("plain-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: unmarked) }
    XCTAssertThrowsError(
      try UITestFixtures.generate(
        into: unmarked, spec: .init(sourceCount: 2, destCount: 1, prefill: .none)))
  }

  // MARK: - Generation

  func testGenerate_createsSourceImagesAndEmptyDests() throws {
    let paths = try UITestFixtures.generate(
      into: markedRoot, spec: .init(sourceCount: 6, destCount: 2, prefill: .none))

    let sourceFiles = try FileManager.default.contentsOfDirectory(
      at: paths.source, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == "jpg" }
    XCTAssertEqual(sourceFiles.count, 6)
    // Every fixture is a real decodable image, not a zero-byte stub.
    for file in sourceFiles {
      XCTAssertNotNil(NSImage(contentsOf: file), "\(file.lastPathComponent) is not a valid image")
    }

    XCTAssertEqual(paths.dests.count, 2)
    for dest in paths.dests {
      let contents = try FileManager.default.contentsOfDirectory(
        at: dest, includingPropertiesForKeys: nil)
      XCTAssertTrue(contents.isEmpty, "expected empty destination, found \(contents)")
    }
  }

  func testGenerate_isIdempotent_regeneratesCleanTree() throws {
    _ = try UITestFixtures.generate(
      into: markedRoot, spec: .init(sourceCount: 4, destCount: 1, prefill: .none))
    let paths = try UITestFixtures.generate(
      into: markedRoot, spec: .init(sourceCount: 2, destCount: 1, prefill: .none))
    let sourceFiles = try FileManager.default.contentsOfDirectory(
      at: paths.source, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == "jpg" }
    XCTAssertEqual(sourceFiles.count, 2, "regeneration must not accumulate prior fixtures")
  }

  func testGenerate_prefillExact_seedsOrganizationFolderWithIdenticalCopies() throws {
    let paths = try UITestFixtures.generate(
      into: markedRoot,
      spec: .init(sourceCount: 3, destCount: 1, prefill: .exact),
      organizationName: "TestOrg")

    let orgDir = paths.dests[0].appendingPathComponent("TestOrg")
    let seeded = try FileManager.default.contentsOfDirectory(
      at: orgDir, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == "jpg" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    let sources = try FileManager.default.contentsOfDirectory(
      at: paths.source, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == "jpg" }.sorted { $0.lastPathComponent < $1.lastPathComponent }

    XCTAssertEqual(seeded.map(\.lastPathComponent), sources.map(\.lastPathComponent))
    for (s, d) in zip(sources, seeded) {
      XCTAssertEqual(try Data(contentsOf: s), try Data(contentsOf: d), "prefill copies must be byte-identical")
    }
  }

  func testGenerate_prefillLoose_seedsDestinationRootWithoutOrganizationFolder() throws {
    let paths = try UITestFixtures.generate(
      into: markedRoot,
      spec: .init(sourceCount: 3, destCount: 1, prefill: .loose),
      organizationName: "TestOrg")

    let rootFiles = try FileManager.default.contentsOfDirectory(
      at: paths.dests[0], includingPropertiesForKeys: nil)
    XCTAssertEqual(rootFiles.filter { $0.pathExtension == "jpg" }.count, 3)
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: paths.dests[0].appendingPathComponent("TestOrg").path),
      "loose prefill must NOT create the organization folder (it suppresses the migration dialog)")
  }

  // MARK: - Launch seam wiring

  func testApplyLaunchSeam_writesSeamDefaultsForGeneratedPaths() throws {
    let applied = try UITestFixtures.applyLaunchSeam(
      arguments: ["--uitest", "--testAutoFixtures", "src=2,dests=2", "--testOrganization", "Org"],
      defaults: defaults, fixturesRoot: markedRoot)

    XCTAssertTrue(applied)
    let src = defaults.string(forKey: "TestSourcePath")
    let d1 = defaults.string(forKey: "TestDest1Path")
    let d2 = defaults.string(forKey: "TestDest2Path")
    XCTAssertNotNil(src)
    XCTAssertNotNil(d1)
    XCTAssertNotNil(d2)
    XCTAssertTrue(FileManager.default.fileExists(atPath: src ?? ""))
    XCTAssertTrue(FileManager.default.fileExists(atPath: d1 ?? ""))
    XCTAssertTrue(FileManager.default.fileExists(atPath: d2 ?? ""))
  }

  func testApplyLaunchSeam_noAutoFixturesArg_returnsFalseAndWritesNothing() throws {
    let applied = try UITestFixtures.applyLaunchSeam(
      arguments: ["--uitest"], defaults: defaults, fixturesRoot: markedRoot)
    XCTAssertFalse(applied)
    XCTAssertNil(defaults.string(forKey: "TestSourcePath"))
  }

  func testApplyLaunchSeam_throwsOnMalformedSpec() {
    XCTAssertThrowsError(
      try UITestFixtures.applyLaunchSeam(
        arguments: ["--testAutoFixtures", "src=oops"],
        defaults: defaults, fixturesRoot: markedRoot))
  }

  // MARK: - Reset

  func testReset_wipesDomainAndFixtureTree() throws {
    _ = try UITestFixtures.generate(
      into: markedRoot, spec: .init(sourceCount: 1, destCount: 1, prefill: .none))
    defaults.set("leftover", forKey: "TestSourcePath")
    defaults.set(true, forKey: "hasSeenWelcome")

    UITestFixtures.reset(defaults: defaults, domainName: suiteName, fixturesRoot: markedRoot)

    XCTAssertNil(defaults.string(forKey: "TestSourcePath"))
    XCTAssertFalse(defaults.bool(forKey: "hasSeenWelcome"))
    XCTAssertFalse(FileManager.default.fileExists(atPath: markedRoot.path))
  }

  func testReset_refusesUnmarkedFixtureRoot() throws {
    let unmarked = FileManager.default.temporaryDirectory
      .appendingPathComponent("plain-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: unmarked, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: unmarked) }

    UITestFixtures.reset(defaults: defaults, domainName: suiteName, fixturesRoot: unmarked)

    XCTAssertTrue(
      FileManager.default.fileExists(atPath: unmarked.path),
      "reset must never delete a directory that lacks the imageintact-uitest marker")
  }

  // MARK: - Failure injection (failures=N)

  func testParseSpec_parsesFailuresField() {
    let spec = UITestFixtures.parseSpec("src=6,failures=2")
    XCTAssertEqual(
      spec, UITestFixtures.Spec(sourceCount: 6, destCount: 1, prefill: .none, failureCount: 2))
  }

  func testParseSpec_failuresDefaultsToZero() {
    XCTAssertEqual(UITestFixtures.parseSpec("src=3")?.failureCount, 0)
  }

  func testParseSpec_rejectsFailuresExceedingSource() {
    XCTAssertNil(UITestFixtures.parseSpec("src=2,failures=3"))
  }

  func testParseSpec_rejectsGarbageFailures() {
    XCTAssertNil(UITestFixtures.parseSpec("src=6,failures=-1"))
    XCTAssertNil(UITestFixtures.parseSpec("src=6,failures=two"))
  }

  func testGenerate_failuresMakesFirstNSourceFilesUnreadable() throws {
    let paths = try UITestFixtures.generate(
      into: markedRoot, spec: .init(sourceCount: 4, destCount: 1, prefill: .none, failureCount: 2))
    let sources = try FileManager.default.contentsOfDirectory(
      at: paths.source, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == "jpg" }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }
    XCTAssertEqual(sources.count, 4)
    // fix-01, fix-02 unreadable; the rest readable.
    for file in sources.prefix(2) {
      let mode =
        try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
      XCTAssertEqual(mode, 0, "\(file.lastPathComponent) should be mode 000")
      XCTAssertFalse(
        FileManager.default.isReadableFile(atPath: file.path),
        "\(file.lastPathComponent) should not be readable")
    }
    for file in sources.dropFirst(2) {
      XCTAssertTrue(
        FileManager.default.isReadableFile(atPath: file.path),
        "\(file.lastPathComponent) should remain readable")
    }
    // Restore so tearDown's removeItem is unhindered even if FileManager balks.
    for file in sources.prefix(2) {
      try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
    }
  }

  func testGenerate_prefillCopiesStayReadableWhenFailuresSet() throws {
    // Prefill copies are made BEFORE the source chmod, so they must be intact.
    let paths = try UITestFixtures.generate(
      into: markedRoot,
      spec: .init(sourceCount: 3, destCount: 1, prefill: .exact, failureCount: 1),
      organizationName: "Org")
    let seeded = try FileManager.default.contentsOfDirectory(
      at: paths.dests[0].appendingPathComponent("Org"), includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == "jpg" }
    XCTAssertEqual(seeded.count, 3)
    for file in seeded {
      XCTAssertTrue(
        FileManager.default.isReadableFile(atPath: file.path),
        "prefill copy \(file.lastPathComponent) must be readable")
    }
    // Restore source perms for clean teardown.
    let sources = try FileManager.default.contentsOfDirectory(
      at: paths.source, includingPropertiesForKeys: nil)
    for file in sources {
      try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
    }
  }

  func testGenerate_regeneratesOverTreeWithUnreadableFiles() throws {
    _ = try UITestFixtures.generate(
      into: markedRoot, spec: .init(sourceCount: 3, destCount: 1, prefill: .none, failureCount: 2))
    // Second generate must not throw despite the prior tree holding 000 files.
    let paths = try UITestFixtures.generate(
      into: markedRoot, spec: .init(sourceCount: 2, destCount: 1, prefill: .none))
    let sources = try FileManager.default.contentsOfDirectory(
      at: paths.source, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == "jpg" }
    XCTAssertEqual(sources.count, 2)
    for file in sources {
      XCTAssertTrue(FileManager.default.isReadableFile(atPath: file.path))
    }
  }

  func testReset_deletesTreeContainingUnreadableFiles() throws {
    _ = try UITestFixtures.generate(
      into: markedRoot, spec: .init(sourceCount: 3, destCount: 1, prefill: .none, failureCount: 2))
    UITestFixtures.reset(defaults: defaults, domainName: suiteName, fixturesRoot: markedRoot)
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: markedRoot.path),
      "reset must delete the tree even when it contains mode-000 files")
  }

  // MARK: - Mixed file types (videos=N)

  func testParseSpec_parsesVideosField() {
    let spec = UITestFixtures.parseSpec("src=4,videos=2")
    XCTAssertEqual(
      spec,
      UITestFixtures.Spec(sourceCount: 4, destCount: 1, prefill: .none, videoCount: 2))
  }

  func testParseSpec_videosDefaultsToZero() {
    XCTAssertEqual(UITestFixtures.parseSpec("src=3")?.videoCount, 0)
  }

  func testParseSpec_videosCombinesWithOtherFields() {
    let spec = UITestFixtures.parseSpec("src=4,dests=2,prefill=exact,videos=3")
    XCTAssertEqual(
      spec,
      UITestFixtures.Spec(
        sourceCount: 4, destCount: 2, prefill: .exact, videoCount: 3))
  }

  func testParseSpec_rejectsGarbageVideos() {
    XCTAssertNil(UITestFixtures.parseSpec("src=4,videos=-1"))
    XCTAssertNil(UITestFixtures.parseSpec("src=4,videos=two"))
  }

  func testParseSpec_boundsVideos() {
    XCTAssertNil(UITestFixtures.parseSpec("src=4,videos=10000"))
  }

  func testGenerate_videosWritesMovFilesAlongsidePhotos() throws {
    let paths = try UITestFixtures.generate(
      into: markedRoot, spec: .init(sourceCount: 4, destCount: 1, prefill: .none, videoCount: 2))
    let contents = try FileManager.default.contentsOfDirectory(
      at: paths.source, includingPropertiesForKeys: nil)
    let jpgs = contents.filter { $0.pathExtension == "jpg" }
    let movs = contents.filter { $0.pathExtension == "mov" }
    XCTAssertEqual(jpgs.count, 4, "expected 4 photo fixtures")
    XCTAssertEqual(movs.count, 2, "expected 2 video fixtures")
    // Videos are non-empty and byte-distinct (distinct checksums, so duplicate
    // detection — if ever enabled — never collapses them).
    let movData = try movs.map { try Data(contentsOf: $0) }
    for d in movData { XCTAssertFalse(d.isEmpty, "video fixture must be non-empty") }
    if movData.count == 2 {
      XCTAssertNotEqual(movData[0], movData[1], "video fixtures must be byte-distinct")
    }
  }

  func testGenerate_videosAreSourceOnly_notPrefilled() throws {
    let paths = try UITestFixtures.generate(
      into: markedRoot,
      spec: .init(sourceCount: 2, destCount: 1, prefill: .exact, videoCount: 2),
      organizationName: "Org")
    // Prefill seeds only the photos into the org folder; videos are source-only.
    let orgDir = paths.dests[0].appendingPathComponent("Org")
    let seeded = try FileManager.default.contentsOfDirectory(
      at: orgDir, includingPropertiesForKeys: nil)
    XCTAssertEqual(seeded.filter { $0.pathExtension == "jpg" }.count, 2)
    XCTAssertTrue(
      seeded.filter { $0.pathExtension == "mov" }.isEmpty, "videos must not be prefilled")
  }

  func testGenerate_zeroVideosWritesNoMovFiles() throws {
    let paths = try UITestFixtures.generate(
      into: markedRoot, spec: .init(sourceCount: 3, destCount: 1, prefill: .none))
    let movs = try FileManager.default.contentsOfDirectory(
      at: paths.source, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == "mov" }
    XCTAssertTrue(movs.isEmpty, "videos default to none")
  }
}
