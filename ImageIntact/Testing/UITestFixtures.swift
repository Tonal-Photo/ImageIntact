//
//  UITestFixtures.swift
//  ImageIntact
//
//  DEBUG-only fixture seam for the XCUITest suite. Generates deterministic
//  image fixtures inside the app container (sandbox-safe, no powerbox) and
//  wires them into the existing --testSource/--testDest UserDefaults seam.
//  See .planning/design/ui-test-suite.md.
//

import Foundation

/// Always-compiled shim consulted by the backup pipeline's security-scope
/// guards. `startAccessingSecurityScopedResource()` returns false for
/// non-bookmark URLs even when the path is fully accessible (the app's own
/// container) — for UI-test fixture paths that false is not a denial.
/// Release builds never bypass the scope check.
enum UITestSeam {
  static func allowsUnscopedAccess(_ url: URL) -> Bool {
    #if DEBUG
      return UITestFixtures.isUITestPath(url)
    #else
      return false
    #endif
  }

  /// True only for DEBUG builds launched by the UI suite (`--uitest`).
  /// Views consult this before attaching machine-readable a11y payloads
  /// (sheet.completion / sheet.migration / sheet.duplicate values) so
  /// VoiceOver users never hear test syntax in production.
  static var isActive: Bool {
    isActive(arguments: ProcessInfo.processInfo.arguments)
  }

  static func isActive(arguments: [String]) -> Bool {
    #if DEBUG
      return arguments.contains("--uitest")
    #else
      return false
    #endif
  }

  /// Per-file copy throttle (nanoseconds) the backup worker honors so the UI
  /// suite can cancel a backup mid-copy. ALWAYS 0 in release — the knob
  /// compiles out (the `#else` returns a constant 0), so the production copy
  /// path is unchanged and the throttle branch is dead. In DEBUG it reflects
  /// `--testCopyDelayMs` (stored under "TestCopyDelayMs" by bootstrap).
  static var perFileCopyDelayNanos: UInt64 {
    #if DEBUG
      let ms = UserDefaults.standard.integer(forKey: "TestCopyDelayMs")
      return ms > 0 ? UInt64(ms) * 1_000_000 : 0
    #else
      return 0
    #endif
  }

  /// DEBUG-only per-file artificial delay (nanoseconds) applied after each
  /// copied file and each verified file, so the live-progress UI stays on
  /// screen long enough for the UI suite to sample it. Driven by
  /// `--testPerFileDelayMs <N>` (clamped 0…5000ms). Always 0 in Release, and 0
  /// whenever the flag is absent or the suite is not active.
  static var perFileDelayNanos: UInt64 {
    perFileDelayNanos(arguments: ProcessInfo.processInfo.arguments)
  }

  static func perFileDelayNanos(arguments: [String]) -> UInt64 {
    #if DEBUG
      guard isActive(arguments: arguments),
        let idx = arguments.firstIndex(of: "--testPerFileDelayMs"),
        idx + 1 < arguments.count,
        let ms = Int(arguments[idx + 1]), ms > 0
      else { return 0 }
      return UInt64(min(ms, 5000)) * 1_000_000
    #else
      return 0
    #endif
  }
}

#if DEBUG
  import AppKit
  import CoreData
  import ImageIO
  import UniformTypeIdentifiers

  enum UITestFixtures {

    /// Name marker required in (or immediately above) any directory this seam
    /// deletes or regenerates. The delete-then-regenerate contract is a loaded
    /// gun if it ever points at a real user directory; refuse anything not
    /// explicitly ours. (Pattern ported from Palomino's FixtureFactory.)
    static let pathMarker = "imageintact-uitest"

    struct Spec: Equatable {
      var sourceCount: Int
      var destCount: Int
      var prefill: Prefill
      /// Number of source files to make unreadable (chmod 000) so the backup
      /// hits real per-file read failures. Defaulted so existing positional
      /// call sites and the synthesized memberwise init keep compiling.
      var failureCount: Int = 0
      /// Number of `.mov` video fixtures to write into the source IN ADDITION
      /// to the `sourceCount` photos, so a photo/video file-type filter has a
      /// measurable effect (a JPEG-only source can't be split). Source-only:
      /// videos are never prefilled or failure-poisoned. Defaulted so existing
      /// call sites and the synthesized memberwise init keep compiling.
      var videoCount: Int = 0
    }

    enum Prefill: String {
      case none
      /// Byte-identical copies of the source files inside the organization
      /// folder — triggers the duplicate-warning path.
      case exact
      /// Copies of the source files at the destination ROOT with no
      /// organization folder — triggers the migration-dialog path.
      case loose
      /// Same content as the source but recorded at the destination under a
      /// DIFFERENT name — triggers the renamed-duplicate path. Detection is
      /// Core-Data-backed (DuplicateDetector reads EventLogger's "copy" events,
      /// not the destination filesystem), so this mode seeds a copy event per
      /// file with a matching checksum but a differing fileName. The source
      /// files use distinct content (a different EXIF year) so their checksums
      /// never collide with the standard fixtures' accumulated records.
      case renamed
    }

    struct GeneratedPaths {
      let source: URL
      let dests: [URL]
    }

    enum SeamError: Error {
      case malformedSpec(String)
      case unmarkedPath(String)
    }

    /// Default fixture root: inside the app container's tmp, so the sandboxed
    /// app has full access without any security-scoped grant.
    static var defaultRoot: URL {
      URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(pathMarker)
    }

    static func isUITestPath(_ url: URL) -> Bool {
      let dir = url.standardizedFileURL
      var probe = dir
      // The marker must be on the path itself or a close ancestor (fixtures
      // nest two levels: <root>/source/fix-01.jpg), but NOT arbitrarily far
      // up — a repo cloned under a marked directory must not arm this.
      for _ in 0..<3 {
        if probe.lastPathComponent.contains(pathMarker) { return true }
        let parent = probe.deletingLastPathComponent()
        if parent.path == probe.path { break }
        probe = parent
      }
      return false
    }

    // MARK: - Spec parsing

    /// Grammar: `src=<1...999>[,dests=<1...8>][,prefill=none|exact|loose|renamed][,failures=<0...src>][,videos=<0...999>]`
    static func parseSpec(_ raw: String) -> Spec? {
      var sourceCount: Int?
      var destCount = 1
      var prefill = Prefill.none
      var failureCount = 0
      var videoCount = 0

      for field in raw.split(separator: ",") {
        let pair = field.split(separator: "=", maxSplits: 1)
        guard pair.count == 2 else { return nil }
        let (key, value) = (String(pair[0]), String(pair[1]))
        switch key {
        case "src":
          guard let n = Int(value), (1...999).contains(n) else { return nil }
          sourceCount = n
        case "dests":
          guard let n = Int(value), (1...8).contains(n) else { return nil }
          destCount = n
        case "prefill":
          guard let p = Prefill(rawValue: value) else { return nil }
          prefill = p
        case "failures":
          guard let n = Int(value), (0...999).contains(n) else { return nil }
          failureCount = n
        case "videos":
          guard let n = Int(value), (0...999).contains(n) else { return nil }
          videoCount = n
        default:
          return nil
        }
      }
      guard let sourceCount else { return nil }
      // Can't fail more files than exist (validated here, where src is known
      // regardless of field order).
      guard (0...sourceCount).contains(failureCount) else { return nil }
      return Spec(
        sourceCount: sourceCount, destCount: destCount, prefill: prefill,
        failureCount: failureCount, videoCount: videoCount)
    }

    /// Parses `--testCopyDelayMs <0...60000>` — a DEBUG-only per-file copy
    /// throttle that holds a backup in the copy phase long enough for the
    /// cancel-mid-copy UI test. Returns nil if the flag is absent, non-numeric,
    /// or out of range. Pure, for unit testing; the value is stored under
    /// "TestCopyDelayMs" and read by UITestSeam.perFileCopyDelayNanos.
    static func parseCopyDelayMs(arguments: [String]) -> Int? {
      guard let raw = value(after: "--testCopyDelayMs", in: arguments),
        let ms = Int(raw), (0...60000).contains(ms)
      else { return nil }
      return ms
    }

    // MARK: - Generation

    @discardableResult
    static func generate(
      into root: URL, spec: Spec, organizationName: String = "UITestOrg"
    ) throws -> GeneratedPaths {
      let dir = root.standardizedFileURL
      guard isUITestPath(dir) else { throw SeamError.unmarkedPath(dir.path) }

      let fm = FileManager.default
      if fm.fileExists(atPath: dir.path) {
        restorePermissions(at: dir)
        try fm.removeItem(at: dir)
      }

      let source = dir.appendingPathComponent("source")
      try fm.createDirectory(at: source, withIntermediateDirectories: true)
      var sourceFiles: [URL] = []
      // Renamed-duplicate fixtures use distinct content (a different EXIF year)
      // so their checksums never collide with the standard (2026) fixtures whose
      // "copy" records accumulate in the shared EventLogger store — otherwise a
      // colliding same-name record could classify them exact instead of renamed.
      let exifYear = spec.prefill == .renamed ? "2024" : "2026"
      for i in 1...spec.sourceCount {
        let url = source.appendingPathComponent(String(format: "fix-%02d.jpg", i))
        try writeJPEG(
          to: url,
          hue: CGFloat(i - 1) / CGFloat(spec.sourceCount),
          exifDate: String(format: "\(exifYear):01:01 12:%02d:00", min(i, 59)))
        sourceFiles.append(url)
      }

      // Video fixtures (source-only): a JPEG-only source can't exercise a
      // photo/video filter, so write `videoCount` `.mov` files alongside the
      // photos. They are not added to `sourceFiles`, so prefill and failure
      // injection (below) touch only the photos.
      if spec.videoCount > 0 {
        for i in 1...spec.videoCount {
          let url = source.appendingPathComponent(String(format: "vid-%02d.mov", i))
          try writeVideoBlob(to: url, index: i)
        }
      }

      var dests: [URL] = []
      for d in 1...spec.destCount {
        let dest = dir.appendingPathComponent("dest\(d)")
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        switch spec.prefill {
        case .none:
          break
        case .exact:
          let orgDir = dest.appendingPathComponent(organizationName)
          try fm.createDirectory(at: orgDir, withIntermediateDirectories: true)
          for file in sourceFiles {
            try fm.copyItem(at: file, to: orgDir.appendingPathComponent(file.lastPathComponent))
          }
        case .loose:
          for file in sourceFiles {
            try fm.copyItem(at: file, to: dest.appendingPathComponent(file.lastPathComponent))
          }
        case .renamed:
          // Disk: place same-content copies under DIFFERENT names in the org
          // folder (faithful to a renamed-on-disk duplicate).
          let orgDir = dest.appendingPathComponent(organizationName)
          try fm.createDirectory(at: orgDir, withIntermediateDirectories: true)
          for (idx, file) in sourceFiles.enumerated() {
            let renamedName = String(format: "renamed-%02d.jpg", idx + 1)
            try fm.copyItem(at: file, to: orgDir.appendingPathComponent(renamedName))
          }
          // Detection reads Core Data, not the disk, so seed a "copy" event per
          // file: matching checksum, DIFFERENT fileName -> classified renamed.
          try seedRenamedDuplicateRecords(
            sourceFiles: sourceFiles, destination: dest, organizationName: organizationName)
        }
        dests.append(dest)
      }

      // Make the first `failureCount` source files unreadable. Done AFTER the
      // prefill copies above so those copies are made from readable originals;
      // only the source the backup reads is poisoned. The owner (non-root test
      // runner) gets EACCES on open() for read, a genuine per-file failure.
      if spec.failureCount > 0 {
        for file in sourceFiles.prefix(spec.failureCount) {
          try fm.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)
        }
      }
      return GeneratedPaths(source: source, dests: dests)
    }

    /// Reset traversable permissions across a fixture tree before deletion.
    /// `failures=N` leaves mode-000 files behind; POSIX still lets the owner
    /// unlink a 000 *file* (deletion is a parent-dir operation), but be
    /// defensive so a leftover can never wedge the next regenerate or reset.
    private static func restorePermissions(at root: URL) {
      let fm = FileManager.default
      guard
        let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey])
      else { return }
      for case let url as URL in enumerator {
        // Skip symlinks: setAttributes(ofItemAtPath:) resolves them, so a
        // symlink planted in the fixture tree could chmod a file outside it.
        if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
          continue
        }
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
      }
    }

    /// Seeds the duplicate detector's Core Data store with one "copy" event per
    /// source file: a MATCHING checksum (so it is a duplicate) but a DIFFERENT
    /// fileName (so `DuplicateDetector` classifies it renamed, not exact).
    ///
    /// `DuplicateDetector.queryExistingFiles` reads EventLogger's store (NOT the
    /// destination filesystem) and matches on the destination's volume UUID, then
    /// compares the stored `fileName` to the source filename. So we mirror exactly
    /// what a real backup records (`BatchEventLogger`): eventType=copy,
    /// severity=info, checksum, fileName, driveUUID. `session` is optional in the
    /// model, so it is omitted. The checksum is computed with the same
    /// `ChecksumService` the manifest uses, guaranteeing the match.
    private static func seedRenamedDuplicateRecords(
      sourceFiles: [URL], destination: URL, organizationName: String
    ) throws {
      let driveUUID = (try? destination.resourceValues(forKeys: [.volumeUUIDStringKey]))?
        .volumeUUIDString
      let orgDir = destination.appendingPathComponent(organizationName)

      // Compute checksums up front (file I/O), so the Core Data work below stays
      // small and runs entirely on the context's own queue.
      var seeds: [(checksum: String, fileName: String, destinationPath: String)] = []
      for (idx, file) in sourceFiles.enumerated() {
        let renamedName = String(format: "renamed-%02d.jpg", idx + 1)
        let checksum = try ChecksumService.sha256(for: file, shouldCancel: { false })
        seeds.append((checksum, renamedName, orgDir.appendingPathComponent(renamedName).path))
      }

      // Always touch the main-queue viewContext through performAndWait so this is
      // correct even if fixture generation is ever moved off the main thread.
      let context = EventLogger.shared.container.viewContext
      var saveError: Error?
      context.performAndWait {
        for seed in seeds {
          let event = BackupEvent(context: context)
          event.id = UUID()
          event.timestamp = Date()
          event.eventType = EventType.copy.rawValue
          event.severity = EventSeverity.info.rawValue
          event.checksum = seed.checksum
          event.fileName = seed.fileName
          event.driveUUID = driveUUID
          event.destinationPath = seed.destinationPath
        }
        do { try context.save() } catch { saveError = error }
      }
      if let saveError { throw saveError }
    }

    private static func writeJPEG(to url: URL, hue: CGFloat, exifDate: String) throws {
      let w = 640
      let h = 480
      guard
        let ctx = CGContext(
          data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
          space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { throw CocoaError(.fileWriteUnknown) }
      ctx.setFillColor(NSColor(hue: hue, saturation: 0.8, brightness: 0.9, alpha: 1).cgColor)
      ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
      guard let image = ctx.makeImage(),
        let dest = CGImageDestinationCreateWithURL(
          url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
      else { throw CocoaError(.fileWriteUnknown) }
      let props: [CFString: Any] = [
        kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: exifDate]
      ]
      CGImageDestinationAddImage(dest, image, props as CFDictionary)
      guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
    }

    /// Write a `.mov` fixture: 512 deterministic, index-varied bytes. Not a real
    /// QuickTime container — the scanner classifies by extension and the backup
    /// only hashes/copies bytes, so arbitrary content suffices. Index-varied so
    /// distinct files have distinct checksums.
    /// TODO: if the scanner ever moves to UTType/AVFoundation header sniffing,
    /// replace these bytes with a minimal valid `.mov` atom structure.
    private static func writeVideoBlob(to url: URL, index: Int) throws {
      var bytes = [UInt8](repeating: 0, count: 512)
      for j in 0..<bytes.count { bytes[j] = UInt8((j &+ index) & 0xFF) }
      try Data(bytes).write(to: url)
    }

    // MARK: - Launch seam

    /// Bootstraps the seam from launch arguments. Called from ImageIntactApp
    /// init when `--uitest` is present. Order matters: reset first, then
    /// fixtures, then path passthrough, so every test launch starts hermetic.
    static func bootstrap(arguments: [String] = ProcessInfo.processInfo.arguments) {
      if arguments.contains("--uitest-reset") {
        reset(
          defaults: .standard,
          domainName: Bundle.main.bundleIdentifier ?? "com.tonalphoto.tech.ImageIntact",
          fixturesRoot: defaultRoot)
      }
      // Stored AFTER reset so the hermetic wipe doesn't clear it. Read per-file
      // by UITestSeam.perFileCopyDelayNanos to throttle the copy phase. The
      // explicit clear is belt-and-suspenders: a launch that doesn't ask for a
      // throttle never inherits a stale one, independent of the reset above.
      if let delayMs = parseCopyDelayMs(arguments: arguments) {
        UserDefaults.standard.set(delayMs, forKey: "TestCopyDelayMs")
      } else {
        UserDefaults.standard.removeObject(forKey: "TestCopyDelayMs")
      }
      do {
        let applied = try applyLaunchSeam(
          arguments: arguments, defaults: .standard, fixturesRoot: defaultRoot)
        if !applied {
          applyPassthroughPathArguments(arguments)
        }
      } catch {
        // Surface loudly: a half-configured seam makes every downstream UI
        // assertion misleading. fatalError keeps the failure at the true cause.
        fatalError("UITestFixtures bootstrap failed: \(error)")
      }
    }

    /// Generates fixtures per `--testAutoFixtures <spec>` and writes the
    /// resulting paths into the SAME UserDefaults keys the pre-existing
    /// `--testSource/--testDest1/--testDest2` seam consumes
    /// (BackupManager.loadUITestPaths / DestinationManager.loadUITestDestinations).
    /// Returns false if the argument is absent.
    @discardableResult
    static func applyLaunchSeam(
      arguments: [String], defaults: UserDefaults, fixturesRoot: URL
    ) throws -> Bool {
      guard let idx = arguments.firstIndex(of: "--testAutoFixtures"),
        idx + 1 < arguments.count
      else { return false }

      guard let spec = parseSpec(arguments[idx + 1]) else {
        throw SeamError.malformedSpec(arguments[idx + 1])
      }
      let organizationName = value(after: "--testOrganization", in: arguments) ?? "UITestOrg"
      let paths = try generate(into: fixturesRoot, spec: spec, organizationName: organizationName)

      defaults.set(paths.source.path, forKey: "TestSourcePath")
      if paths.dests.count >= 1 { defaults.set(paths.dests[0].path, forKey: "TestDest1Path") }
      if paths.dests.count >= 2 { defaults.set(paths.dests[1].path, forKey: "TestDest2Path") }
      if let org = value(after: "--testOrganization", in: arguments) {
        defaults.set(org, forKey: "TestOrganizationName")
      }
      return true
    }

    /// The original Aug-2025 seam: explicit paths via launch arguments.
    /// Kept for tests that stage their own trees.
    static func applyPassthroughPathArguments(_ arguments: [String]) {
      let mapping: [(flag: String, key: String)] = [
        ("--testSource", "TestSourcePath"),
        ("--testDest1", "TestDest1Path"),
        ("--testDest2", "TestDest2Path"),
        ("--testOrganization", "TestOrganizationName"),
      ]
      for (flag, key) in mapping {
        if let v = value(after: flag, in: arguments) {
          UserDefaults.standard.set(v, forKey: key)
        }
      }
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
      guard let idx = arguments.firstIndex(of: flag), idx + 1 < arguments.count else { return nil }
      return arguments[idx + 1]
    }

    // MARK: - Reset

    /// Wipes the app's persisted defaults domain and the fixture tree.
    /// Refuses to delete a fixture root that lacks the path marker.
    static func reset(defaults: UserDefaults, domainName: String, fixturesRoot: URL) {
      defaults.removePersistentDomain(forName: domainName)
      if isUITestPath(fixturesRoot) {
        restorePermissions(at: fixturesRoot)
        try? FileManager.default.removeItem(at: fixturesRoot)
      }
    }
  }
#endif
