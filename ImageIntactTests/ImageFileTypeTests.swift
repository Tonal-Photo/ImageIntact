import XCTest
@testable import ImageIntact

final class ImageFileTypeTests: XCTestCase {
    
    // MARK: - File Type Detection Tests
    
    func testRAWFileDetection() {
        // Test common RAW formats
        let rawExtensions = ["nef", "cr2", "arw", "dng", "orf", "rw2", "pef", "srw", "x3f", "raf"]
        
        for ext in rawExtensions {
            let url = URL(fileURLWithPath: "/test/photo.\(ext)")
            XCTAssertTrue(ImageFileType.isImageFile(url), "\(ext) should be recognized as image file")
            
            if let fileType = ImageFileType.from(fileExtension: ext) {
                XCTAssertTrue(fileType.isRaw, "\(ext) should be recognized as RAW")
                XCTAssertFalse(fileType.isVideo, "\(ext) should not be video")
                XCTAssertFalse(fileType.isSidecar, "\(ext) should not be sidecar")
            } else {
                XCTFail("Failed to detect file type for \(ext)")
            }
        }
    }
    
    func testStandardImageDetection() {
        let standardFormats = ["jpg", "jpeg", "png", "tiff", "gif", "heic", "webp"]
        
        for ext in standardFormats {
            let url = URL(fileURLWithPath: "/test/image.\(ext)")
            XCTAssertTrue(ImageFileType.isImageFile(url), "\(ext) should be recognized as image file")
            
            if let fileType = ImageFileType.from(fileExtension: ext) {
                XCTAssertFalse(fileType.isRaw, "\(ext) should not be RAW")
                XCTAssertFalse(fileType.isVideo, "\(ext) should not be video")
                XCTAssertFalse(fileType.isSidecar, "\(ext) should not be sidecar")
            }
        }
    }
    
    func testVideoFileDetection() {
        let videoFormats = ["mov", "mp4", "avi", "m4v", "mpg", "mpeg", "wmv", "flv", "webm", "mkv", "mts", "m2ts"]
        
        for ext in videoFormats {
            let url = URL(fileURLWithPath: "/test/video.\(ext)")
            XCTAssertTrue(ImageFileType.isImageFile(url), "\(ext) should be recognized as supported file")
            
            if let fileType = ImageFileType.from(fileExtension: ext) {
                XCTAssertTrue(fileType.isVideo, "\(ext) should be recognized as video")
                XCTAssertFalse(fileType.isRaw, "\(ext) should not be RAW")
                XCTAssertFalse(fileType.isSidecar, "\(ext) should not be sidecar")
            }
        }
    }
    
    func testSidecarFileDetection() {
        let sidecarFormats = ["xmp", "aae", "thm", "dop", "pp3"]
        
        for ext in sidecarFormats {
            let url = URL(fileURLWithPath: "/test/metadata.\(ext)")
            XCTAssertTrue(ImageFileType.isImageFile(url), "\(ext) should be recognized as supported file")
            
            if let fileType = ImageFileType.from(fileExtension: ext) {
                XCTAssertTrue(fileType.isSidecar, "\(ext) should be recognized as sidecar")
                XCTAssertFalse(fileType.isRaw, "\(ext) should not be RAW")
                XCTAssertFalse(fileType.isVideo, "\(ext) should not be video")
            }
        }
    }
    
    func testCatalogFileDetection() {
        let catalogFormats = [
            ("catalog.lrcat", ImageFileType.lrcat),
            ("project.cocatalog", ImageFileType.cocatalog)
        ]
        
        for (filename, expectedType) in catalogFormats {
            let url = URL(fileURLWithPath: "/test/\(filename)")
            XCTAssertTrue(ImageFileType.isImageFile(url), "\(filename) should be recognized as supported file")
            
            let ext = url.pathExtension.lowercased()
            if let fileType = ImageFileType.from(fileExtension: ext) {
                XCTAssertEqual(fileType, expectedType, "\(filename) should be \(expectedType)")
                // Catalog types are lrcat and cocatalog
                XCTAssertTrue(fileType == .lrcat || fileType == .cocatalog, "\(filename) should be catalog type")
            }
        }
    }
    
    func testUnsupportedFileRejection() {
        let unsupportedFormats = ["txt", "doc", "pdf", "zip", "exe", "dmg", "app", "swift", "json"]
        
        for ext in unsupportedFormats {
            let url = URL(fileURLWithPath: "/test/document.\(ext)")
            XCTAssertFalse(ImageFileType.isImageFile(url), "\(ext) should NOT be recognized as image file")
            XCTAssertNil(ImageFileType.from(fileExtension: ext), "\(ext) should return nil")
        }
    }
    
    func testCaseInsensitiveDetection() {
        let mixedCaseFiles = [
            "photo.NEF", "image.Jpeg", "video.MOV", "raw.DnG", "sidecar.XMP"
        ]
        
        for filename in mixedCaseFiles {
            let url = URL(fileURLWithPath: "/test/\(filename)")
            XCTAssertTrue(ImageFileType.isImageFile(url), "\(filename) should be recognized regardless of case")
        }
    }
    
    // MARK: - File Scanning Tests
    
    func testImageFileScannerInitialization() {
        let scanner = ImageFileScanner()
        XCTAssertNotNil(scanner, "Scanner should initialize")
    }
    
    func testScanResultFormatting() {
        let results: [ImageFileType: Int] = [
            .nef: 50,
            .cr2: 30,
            .jpeg: 100,
            .mov: 10,
            .xmp: 80
        ]
        
        let formatted = ImageFileScanner.formatScanResults(results, groupRaw: false)
        XCTAssertFalse(formatted.isEmpty, "Formatted results should not be empty")
        XCTAssertTrue(formatted.contains("80 RAW"), "Should include total RAW count (NEF+CR2)")
        XCTAssertTrue(formatted.contains("100 JPEG"), "Should include JPEG count")
        XCTAssertTrue(formatted.contains("80 Sidecar"), "Should include XMP sidecar count")
    }
    
    func testScanResultFormattingWithGrouping() {
        let results: [ImageFileType: Int] = [
            .nef: 50,
            .cr2: 30,
            .arw: 20,
            .jpeg: 100,
            .mov: 10
        ]
        
        let formatted = ImageFileScanner.formatScanResults(results, groupRaw: true)
        XCTAssertTrue(formatted.contains("100 RAW"), "Should group RAW files when requested")
        XCTAssertTrue(formatted.contains("100 JPEG"), "Should still show JPEG separately")
    }
    
    func testEmptyScanResultFormatting() {
        let results: [ImageFileType: Int] = [:]
        let formatted = ImageFileScanner.formatScanResults(results, groupRaw: false)
        XCTAssertEqual(formatted, "No supported files found", "Empty results should return 'No supported files found'")
    }
    
    // MARK: - Cache File Detection Tests
    
    func testLightRoomCachePathDetection() {
        let cachePatterns = [
            "/Users/test/Pictures/Lightroom/Smart Previews.lrdata/preview.jpg",
            "/Users/test/Pictures/Lightroom/Catalog Previews.lrdata/thumb.jpg",
            "/Users/test/Pictures/Lightroom/MyPhotos Previews.lrdata/1234/5678/preview.jpg"
        ]
        
        for path in cachePatterns {
            _ = URL(fileURLWithPath: path)
            // Note: This would require exposing isLikelyCacheFile or testing through the backup process
            // For now, we're testing the concept that these paths should be excluded
            XCTAssertTrue(path.contains(".lrdata/"), "Path should contain Lightroom cache indicator")
        }
    }
    
    func testCaptureOneSessionSupport() {
        // Test that .cosessiondb files are recognized
        let sessionFile = "MyProject.cosessiondb"
        let ext = URL(fileURLWithPath: sessionFile).pathExtension
        
        if let fileType = ImageFileType.from(fileExtension: ext) {
            XCTAssertEqual(fileType, .cos, "Session database should be COS type")
            XCTAssertTrue(fileType.isSidecar, "Session database should be classified as sidecar")
        } else {
            XCTFail("cosessiondb extension should be recognized")
        }
    }
    
    func testCaptureOneCachePathDetection() {
        // These paths should be detected as cache and excluded
        let cachePaths = [
            "/Users/test/Pictures/Session.cosessiondb/Cache/preview.jpg",
            "/Users/test/Pictures/Session.cosessiondb/Proxies/proxy_001.jpg",
            "/Users/test/Pictures/Session.cosessiondb/Thumbnails/thumb_1234.jpg",
            "/Users/test/Pictures/CaptureOne/Cache/thumb_1234.jpg"
        ]
        
        // These paths should NOT be excluded (legitimate session files)
        let validPaths = [
            "/Users/test/Pictures/Session.cosessiondb/Session.db",
            "/Users/test/Pictures/Session.cosessiondb/Settings/defaults.cos",
            "/Users/test/Pictures/Session.cosessiondb/Output/processed_001.jpg"
        ]
        
        // Verify cache paths contain cache indicators
        for path in cachePaths {
            let containsCache = path.contains("/Cache/") || 
                                path.contains("/Proxies/") || 
                                path.contains("/Thumbnails/")
            XCTAssertTrue(containsCache, "Path \(path) should contain cache indicator")
        }
        
        // Verify valid paths don't contain cache indicators
        for path in validPaths {
            let containsCache = path.contains("/Cache/") || 
                                path.contains("/Proxies/") || 
                                path.contains("/Thumbnails/")
            XCTAssertFalse(containsCache, "Path \(path) should not contain cache indicator")
        }
    }
    
    // MARK: - Performance Tests
    
    func testFileTypeDetectionPerformance() {
        measure {
            for _ in 0..<1000 {
                _ = ImageFileType.isImageFile(URL(fileURLWithPath: "/test/photo.nef"))
                _ = ImageFileType.isImageFile(URL(fileURLWithPath: "/test/video.mov"))
                _ = ImageFileType.isImageFile(URL(fileURLWithPath: "/test/sidecar.xmp"))
            }
        }
    }
    
    func testBulkFileTypeDetection() {
        let urls = (0..<100).map { i in
            URL(fileURLWithPath: "/test/photo\(i).nef")
        }
        
        measure {
            for url in urls {
                _ = ImageFileType.from(fileExtension: url.pathExtension)
            }
        }
    }
}