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
}
