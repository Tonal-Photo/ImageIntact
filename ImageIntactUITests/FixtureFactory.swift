//
//  FixtureFactory.swift
//  ImageIntactUITests
//
//  Runner-side fixture generation for the powerbox open-panel test. The UI
//  test runner is sandboxed for real and cannot reach the app's container, so
//  fixtures the app must read through a genuine NSOpenPanel grant have to live
//  in the RUNNER's own container. This generates them there; the app reaches
//  them through the powerbox selection (security-scoped bookmark), exactly as a
//  user picking a folder would. Because both the source tree and the copied
//  destination then live in the runner's container, the runner can recompute
//  checksums and byte-verify the result - ground truth the app's own stats
//  cannot provide. Ported from Palomino's FixtureFactory.
//
//  This file is a member of the UI test target only (never shipped), so it is
//  not #if DEBUG-gated. The app generates its own in-container fixtures through
//  ImageIntact/Testing/UITestFixtures.swift.
//

import AppKit
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

enum FixtureFactory {
    /// Name marker required on (or immediately above) any directory this factory
    /// deletes or regenerates. The delete-then-regenerate contract is a loaded
    /// gun if it ever points at a real user directory; refuse anything that is
    /// not explicitly ours.
    static let pathMarker = "imageintact-uitest"

    enum FactoryError: Error {
        case unmarkedPath(String)
    }

    /// True if `url` (or its immediate parent) is name-marked as ours. The
    /// parent case covers the nested layout the test builds:
    /// `<...imageintact-uitest-powerbox-UUID>/source`.
    static func isFixturePath(_ url: URL) -> Bool {
        let dir = url.standardizedFileURL
        return dir.lastPathComponent.contains(pathMarker)
            || dir.deletingLastPathComponent().lastPathComponent.contains(pathMarker)
    }

    /// Generates `count` deterministic JPEGs (fix-01.jpg, fix-02.jpg, ...) into
    /// `dir`. `dir` must be name-marked (itself or its parent); it is removed
    /// and recreated. Each file gets a distinct hue so the files have distinct
    /// bytes, which makes the checksum match meaningful. Returns the generated
    /// URLs in order.
    @discardableResult
    static func generateImages(into dir: URL, count: Int) throws -> [URL] {
        let target = dir.standardizedFileURL
        guard isFixturePath(target) else { throw FactoryError.unmarkedPath(target.path) }
        let fm = FileManager.default
        if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        return try (1...count).map { i in
            let url = target.appendingPathComponent(String(format: "fix-%02d.jpg", i))
            try writeJPEG(
                to: url,
                hue: CGFloat(i - 1) / CGFloat(count),
                exifDate: String(format: "2026:01:01 12:%02d:00", min(i, 59)))
            return url
        }
    }

    /// SHA-256 of a file's bytes, lowercase hex. Fixtures are tiny so a single
    /// read is fine.
    static func sha256(of url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
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
}
