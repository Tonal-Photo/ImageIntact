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
}

#if DEBUG
  import AppKit
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
    }

    enum Prefill: String {
      case none
      /// Byte-identical copies of the source files inside the organization
      /// folder — triggers the duplicate-warning path.
      case exact
      /// Copies of the source files at the destination ROOT with no
      /// organization folder — triggers the migration-dialog path.
      case loose
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

    /// Grammar: `src=<1...999>[,dests=<1...8>][,prefill=none|exact|loose]`
    static func parseSpec(_ raw: String) -> Spec? {
      var sourceCount: Int?
      var destCount = 1
      var prefill = Prefill.none

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
        default:
          return nil
        }
      }
      guard let sourceCount else { return nil }
      return Spec(sourceCount: sourceCount, destCount: destCount, prefill: prefill)
    }

    // MARK: - Generation

    @discardableResult
    static func generate(
      into root: URL, spec: Spec, organizationName: String = "UITestOrg"
    ) throws -> GeneratedPaths {
      let dir = root.standardizedFileURL
      guard isUITestPath(dir) else { throw SeamError.unmarkedPath(dir.path) }

      let fm = FileManager.default
      if fm.fileExists(atPath: dir.path) { try fm.removeItem(at: dir) }

      let source = dir.appendingPathComponent("source")
      try fm.createDirectory(at: source, withIntermediateDirectories: true)
      var sourceFiles: [URL] = []
      for i in 1...spec.sourceCount {
        let url = source.appendingPathComponent(String(format: "fix-%02d.jpg", i))
        try writeJPEG(
          to: url,
          hue: CGFloat(i - 1) / CGFloat(spec.sourceCount),
          exifDate: String(format: "2026:01:01 12:%02d:00", min(i, 59)))
        sourceFiles.append(url)
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
        }
        dests.append(dest)
      }
      return GeneratedPaths(source: source, dests: dests)
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
        try? FileManager.default.removeItem(at: fixturesRoot)
      }
    }
  }
#endif
