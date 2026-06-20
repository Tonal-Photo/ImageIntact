//
//  ProgressUITests.swift
//  ImageIntactUITests
//
//  Asserts the LIVE backup-progress phase (overall bar advances, phase label
//  moves through copy then verify, per-destination counts climb to the total)
//  before the completion sheet appears. Made observable by the slow-fixture
//  seam: `--testPerFileDelayMs` keeps copy and verify on screen long enough to
//  sample, and the `progress.live` accessibility marker exposes the state as a
//  single machine-readable value. See .planning/design/ui-test-live-progress.md.
//

import XCTest

final class ProgressUITests: ImageIntactUITestCase {

  // 16 files over 2 destinations with a 250ms per-file delay: copy ≈ 2s
  // (2 workers/dest, before the 5s worker ramp), verify ≈ 4s (serial) — a live
  // window of several seconds, sampled below.
  private let fixtures = "src=16,dests=2"
  private let perFileDelayMs = "250"
  private let expectedTotal = 16

  // BackupPhase raw values (ImageIntact/Models/BackupManager.swift).
  private let phaseCopy = 3
  private let phaseVerify = 5

  /// One observation of the `progress.live` marker.
  private struct Sample {
    let phaseRaw: Int
    let overall: Int            // 0...100
    let dests: [String: (done: Int, total: Int)]
    let sawProgressIndicator: Bool
  }

  /// Parse `phase=3;name=copyingFiles;overall=42;processed=8;verified=0;total=16;dests=dest1:8/16,dest2:7/16`.
  private func parse(_ value: String, sawIndicator: Bool) -> Sample? {
    guard !value.isEmpty else { return nil }
    var fields: [String: String] = [:]
    for pair in value.split(separator: ";") {
      let kv = pair.split(separator: "=", maxSplits: 1)
      if kv.count == 2 { fields[String(kv[0])] = String(kv[1]) }
    }
    guard let phaseRaw = fields["phase"].flatMap({ Int($0) }),
      let overall = fields["overall"].flatMap({ Int($0) })
    else { return nil }

    var dests: [String: (Int, Int)] = [:]
    if let destsField = fields["dests"], !destsField.isEmpty {
      for entry in destsField.split(separator: ",") {
        let parts = entry.split(separator: ":")
        guard parts.count == 2 else { continue }
        let counts = parts[1].split(separator: "/")
        guard counts.count == 2, let done = Int(counts[0]), let total = Int(counts[1])
        else { continue }
        dests[String(parts[0])] = (done, total)
      }
    }
    return Sample(phaseRaw: phaseRaw, overall: overall, dests: dests, sawProgressIndicator: sawIndicator)
  }

  /// Drive a backup and sample `progress.live` until the completion sheet
  /// appears (or `timeout`). Returns every successfully-parsed observation, in
  /// order. Fails the test set-up (not the assertions) if the run never starts.
  private func runAndSampleProgress(timeout: TimeInterval = 90) -> [Sample] {
    let a = launchApp(fixtures: fixtures, extraArgs: ["--testPerFileDelayMs", perFileDelayMs])
    let main = MainScreen(app: a)

    guard main.folderRow("source").waitForExistence(timeout: 15) else {
      dumpElementTree(a, label: "progress-no-source-row")
      XCTFail("seam-selected source folder is not shown in the UI; element tree dumped")
      return []
    }
    guard waitUntilHittable(main.runBackupButton) else {
      XCTFail("Run Backup never became clickable")
      return []
    }
    main.runBackupButton.click()

    let liveMarker = a.staticTexts["progress.live"].firstMatch
    let completion = a.staticTexts["sheet.completion"].firstMatch

    var samples: [Sample] = []
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if completion.exists { break }
      if liveMarker.exists {
        let raw = (liveMarker.value as? String) ?? ""
        let sawIndicator = a.progressIndicators.firstMatch.exists
        if let s = parse(raw, sawIndicator: sawIndicator) { samples.append(s) }
      }
      Thread.sleep(forTimeInterval: 0.08)
    }
    return samples
  }

  func testLiveProgress_AdvancesThroughCopyThenVerify() throws {
    let samples = runAndSampleProgress()

    XCTAssertFalse(
      samples.isEmpty,
      "live-progress marker `progress.live` was never observed during the backup — "
        + "either the marker is missing or the run finished before any sample (slow seam not applied)")
    guard !samples.isEmpty else { return }

    // The real progress control is on screen during the live phase.
    XCTAssertTrue(
      samples.contains { $0.sawProgressIndicator },
      "no ProgressView/progressIndicator was present during the live phase")

    // Overall advances and never goes backwards (high-water mark).
    var highWater = -1
    for s in samples {
      XCTAssertGreaterThanOrEqual(
        s.overall, highWater - 1,
        "overall progress regressed (saw \(s.overall) after \(highWater)); samples=\(samples.map { $0.overall })")
      highWater = max(highWater, s.overall)
    }
    let firstOverall = samples.first!.overall
    XCTAssertGreaterThan(
      highWater, firstOverall,
      "overall progress never advanced (stuck at \(firstOverall)); samples=\(samples.map { $0.overall })")

    // Phase label progresses through copy then verify, never backwards.
    var phaseHighWater = 0
    for s in samples {
      XCTAssertGreaterThanOrEqual(
        s.phaseRaw, phaseHighWater,
        "phase regressed (saw \(s.phaseRaw) after \(phaseHighWater)); phases=\(samples.map { $0.phaseRaw })")
      phaseHighWater = max(phaseHighWater, s.phaseRaw)
    }
    let phasesSeen = Set(samples.map { $0.phaseRaw })
    XCTAssertTrue(
      phasesSeen.contains(phaseCopy),
      "never observed the copy phase (\(phaseCopy)); phases=\(samples.map { $0.phaseRaw })")
    XCTAssertTrue(
      phasesSeen.contains(phaseVerify),
      "never observed the verify phase (\(phaseVerify)); phases=\(samples.map { $0.phaseRaw })")
  }

  func testLiveProgress_PerDestinationCountsReachTotalBeforeCompletion() throws {
    let samples = runAndSampleProgress()

    XCTAssertFalse(samples.isEmpty, "live-progress marker `progress.live` was never observed")
    guard !samples.isEmpty else { return }

    // Both seam destinations must appear and each must climb to the full total
    // at some point BEFORE the completion sheet (we stop sampling at completion).
    for dest in ["dest1", "dest2"] {
      let reachedTotal = samples.contains { sample in
        guard let counts = sample.dests[dest] else { return false }
        return counts.total == expectedTotal && counts.done == expectedTotal
      }
      let observed = samples.compactMap { $0.dests[dest].map { "\($0.done)/\($0.total)" } }
      XCTAssertTrue(
        reachedTotal,
        "\(dest) never reached \(expectedTotal)/\(expectedTotal) before completion; observed=\(observed)")
    }

    // Per-destination counts are monotonic non-decreasing per destination.
    for dest in ["dest1", "dest2"] {
      var destHighWater = -1
      for s in samples {
        guard let counts = s.dests[dest] else { continue }
        XCTAssertGreaterThanOrEqual(
          counts.done, destHighWater,
          "\(dest) count regressed (saw \(counts.done) after \(destHighWater))")
        destHighWater = max(destHighWater, counts.done)
      }
    }
  }
}
