//
//  ImageFileType.swift
//  ImageIntact
//
//  Image file type definitions and recognition
//

import Foundation

enum ImageFileType: String, CaseIterable {
    // Standard image formats
    case jpeg = "JPEG"
    case tiff = "TIFF"
    case png = "PNG"
    case heic = "HEIC"
    case heif = "HEIF"
    case webp = "WebP"
    case bmp = "BMP"
    case gif = "GIF"
    
    // Video formats
    case mov = "MOV"
    case mp4 = "MP4"
    case avi = "AVI"
    case m4v = "M4V"
    case mpg = "MPG"
    case mts = "MTS"  // AVCHD
    case m2ts = "M2TS"  // AVCHD
    case wmv = "WMV"
    case flv = "FLV"
    case webm = "WebM"
    case mkv = "MKV"
    case mpeg = "MPEG"

    // Professional cinema formats
    case braw = "BRAW"        // Blackmagic RAW
    case r3d = "R3D"          // RED camera RAW
    case ari = "ARRIRAW"      // ARRI camera RAW
    case mxf = "MXF"          // Professional container (XAVC, XF-AVC, etc.)
    case crm = "CRM"          // Canon Cinema RAW Light

    // Sidecar and metadata files
    case xmp = "XMP"  // Adobe sidecar
    case aae = "AAE"  // Apple sidecar
    case thm = "THM"  // Thumbnail file
    case dop = "DOP"  // DxO PhotoLab
    case cos = "COS"  // Capture One settings
    case pp3 = "PP3"  // RawTherapee
    case arp = "ARP"  // Adobe Camera Raw
    case lrcat = "LR Catalog"  // Lightroom catalog
    case lrdata = "LR Data"  // Lightroom data
    case cocatalog = "C1 Catalog"  // Capture One catalog
    case cocatalogdb = "C1 Database"  // Capture One catalog database
    
    // Adobe/Generic RAW
    case dng = "DNG"
    
    // Canon
    case cr2 = "CR2"
    case cr3 = "CR3"
    case crw = "CRW"
    
    // Nikon
    case nef = "NEF"
    case nrw = "NRW"
    
    // Sony
    case arw = "ARW"
    case srf = "SRF"
    case sr2 = "SR2"
    
    // Samsung
    case srw = "SRW"
    
    // Fujifilm
    case raf = "RAF"
    
    // Olympus
    case orf = "ORF"
    
    // Panasonic
    case rw2 = "RW2"
    case raw = "RAW"  // Panasonic/Leica
    
    // Pentax
    case pef = "PEF"
    case ptx = "PTX"  // Pentax
    
    // Leica
    case rwl = "RWL"
    
    // Hasselblad
    case fff = "FFF"
    case x3f = "X3F"  // Also Sigma
    
    // Phase One
    case iiq = "IIQ"
    
    // Other professional formats
    case mef = "MEF"  // Mamiya
    case mos = "MOS"  // Leaf
    case dcr = "DCR"  // Kodak
    case kdc = "KDC"  // Kodak
    case erf = "ERF"  // Epson
    case mrw = "MRW"  // Minolta
    
    var extensions: Set<String> {
        switch self {
        case .jpeg:
            return ["jpg", "jpeg", "jpe", "jfif"]
        case .tiff:
            return ["tif", "tiff"]
        case .png:
            return ["png"]
        case .heic:
            return ["heic"]
        case .heif:
            return ["heif"]
        case .webp:
            return ["webp"]
        case .bmp:
            return ["bmp"]
        case .gif:
            return ["gif"]
        // Video formats
        case .mov:
            return ["mov", "qt"]
        case .mp4:
            return ["mp4", "m4v", "mp4v"]
        case .avi:
            return ["avi"]
        case .m4v:
            return ["m4v"]
        case .mpg:
            return ["mpg", "mpeg", "mpe", "m2v"]
        case .mts:
            return ["mts", "m2t"]
        case .m2ts:
            return ["m2ts"]

        // Professional cinema formats
        case .braw:
            return ["braw"]
        case .r3d:
            return ["r3d"]
        case .ari:
            return ["ari", "arriraw"]
        case .mxf:
            return ["mxf"]
        case .crm:
            return ["crm"]

        // Sidecar files
        case .xmp:
            return ["xmp"]
        case .dop:
            return ["dop"]
        case .cos:
            return ["cos", "cosessiondb"]
        case .pp3:
            return ["pp3"]
        case .arp:
            return ["arp"]
        case .lrcat:
            return ["lrcat", "lrcat-data"]
        case .lrdata:
            return ["lrdata"]
        case .cocatalog:
            return ["cocatalog"]
        case .cocatalogdb:
            return ["cocatalogdb"]
        // RAW formats
        case .dng:
            return ["dng"]
        case .ptx:
            return ["ptx"]
        case .cr2:
            return ["cr2"]
        case .cr3:
            return ["cr3"]
        case .crw:
            return ["crw"]
        case .nef:
            return ["nef"]
        case .nrw:
            return ["nrw"]
        case .arw:
            return ["arw"]
        case .srf:
            return ["srf"]
        case .sr2:
            return ["sr2"]
        case .raf:
            return ["raf"]
        case .orf:
            return ["orf"]
        case .rw2:
            return ["rw2"]
        case .raw:
            return ["raw"]
        case .pef:
            return ["pef"]
        case .rwl:
            return ["rwl"]
        case .fff:
            return ["fff"]
        case .x3f:
            return ["x3f"]
        case .iiq:
            return ["iiq"]
        case .mef:
            return ["mef"]
        case .mos:
            return ["mos"]
        case .dcr:
            return ["dcr"]
        case .kdc:
            return ["kdc"]
        case .erf:
            return ["erf"]
        case .mrw:
            return ["mrw"]
        case .srw:
            return ["srw"]
        case .wmv:
            return ["wmv"]
        case .flv:
            return ["flv", "f4v", "f4p"]
        case .webm:
            return ["webm"]
        case .mkv:
            return ["mkv"]
        case .mpeg:
            return ["mpeg", "mpg", "mpe"]
        case .aae:
            return ["aae"]
        case .thm:
            return ["thm"]
        }
    }
    
    var isRaw: Bool {
        switch self {
        case .jpeg, .tiff, .png, .heic, .heif, .webp, .bmp, .gif,
             .mov, .mp4, .avi, .m4v, .mpg, .mts, .m2ts, .wmv, .flv, .webm, .mkv, .mpeg,
             .braw, .r3d, .ari, .mxf, .crm,
             .xmp, .dop, .cos, .pp3, .arp, .aae, .thm, .lrcat, .lrdata, .cocatalog, .cocatalogdb:
            return false
        default:
            return true
        }
    }
    
    var isVideo: Bool {
        switch self {
        case .mov, .mp4, .avi, .m4v, .mpg, .mts, .m2ts, .wmv, .flv, .webm, .mkv, .mpeg,
             .braw, .r3d, .ari, .mxf, .crm:
            return true
        default:
            return false
        }
    }
    
    var isSidecar: Bool {
        switch self {
        case .xmp, .dop, .cos, .pp3, .arp, .aae, .thm, .lrcat, .lrdata, .cocatalog, .cocatalogdb:
            return true
        default:
            return false
        }
    }
    
    var displayName: String {
        if isRaw {
            return "RAW (\(rawValue))"
        } else if isVideo {
            return "Video (\(rawValue))"
        } else if isSidecar {
            return rawValue  // Keep simple for sidecars
        }
        return rawValue
    }
    
    var folderName: String {
        // For organizing into subfolders
        return rawValue
    }
    
    // Average file size in bytes (rough estimates for pre-backup calculation)
    var averageFileSize: Int {
        switch self {
        // RAW files are typically large
        case .dng, .cr2, .cr3, .nef, .arw, .orf, .rw2, .raf, .pef, .srw, .erf, .crw, .raw:
            return 25_000_000  // ~25 MB average for modern RAW files
        case .nrw, .rwl, .iiq, .mos, .dcr, .mef, .mrw, .kdc, .srf, .sr2, .ptx, .fff, .x3f:
            return 20_000_000  // ~20 MB for these RAW formats
            
        // Standard images
        case .jpeg:
            return 2_000_000   // ~2 MB for typical JPEG
        case .heic, .heif:
            return 1_500_000   // ~1.5 MB (more efficient than JPEG)
        case .tiff:
            return 10_000_000  // ~10 MB (varies widely)
        case .png:
            return 3_000_000   // ~3 MB
        case .webp:
            return 1_000_000   // ~1 MB
        case .bmp:
            return 5_000_000   // ~5 MB (uncompressed)
        case .gif:
            return 500_000     // ~500 KB
            
        // Video files (much more realistic sizes)
        case .mov, .mp4:
            return 50_000_000  // ~50 MB for typical video clips
        case .avi, .mpg, .mpeg:
            return 30_000_000  // ~30 MB
        case .mts, .m2ts:
            return 40_000_000  // ~40 MB (AVCHD)
        case .m4v, .wmv, .flv, .webm, .mkv:
            return 20_000_000  // ~20 MB

        // Professional cinema formats are very large
        case .braw:
            return 200_000_000  // ~200 MB (Blackmagic RAW varies widely)
        case .r3d:
            return 300_000_000  // ~300 MB (RED RAW is huge)
        case .ari:
            return 500_000_000  // ~500 MB (ARRIRAW is massive)
        case .mxf:
            return 100_000_000  // ~100 MB (depends on codec)
        case .crm:
            return 150_000_000  // ~150 MB (Canon Cinema RAW Light)

        // Sidecar files are small
        case .xmp, .aae, .dop, .cos, .pp3, .arp:
            return 50_000     // ~50 KB
        case .thm:
            return 100_000    // ~100 KB (thumbnail)
            
        // Catalog files can be large
        case .lrcat, .cocatalog:
            return 100_000_000 // ~100 MB
        case .lrdata, .cocatalogdb:
            return 500_000_000 // ~500 MB (can be huge)
        }
    }
    
    static func from(fileExtension ext: String) -> ImageFileType? {
        let lowercased = ext.lowercased()
        for type in ImageFileType.allCases {
            if type.extensions.contains(lowercased) {
                return type
            }
        }
        return nil
    }
    
    static func isSupportedFile(_ url: URL) -> Bool {
        // Use UTI detection as primary method (more reliable)
        let utiDetector = UTIFileTypeDetector.shared
        if utiDetector.isSupportedFile(url) {
            return true
        }
        
        // Fallback to extension checking for edge cases
        let ext = url.pathExtension.lowercased()
        return from(fileExtension: ext) != nil
    }
    
    // Enhanced version with detailed info
    static func getFileInfo(_ url: URL) -> FileTypeInfo {
        return UTIFileTypeDetector.shared.getFileTypeInfo(url)
    }
    
    // Keep for compatibility
    static func isImageFile(_ url: URL) -> Bool {
        return isSupportedFile(url)
    }
}

// File scanner for analyzing source folders
class ImageFileScanner {
    struct ScanInfo {
        let count: Int
        let totalBytes: Int64
    }
    
    typealias ScanResult = [ImageFileType: Int]
    typealias DetailedScanResult = (fileTypes: [ImageFileType: Int], totalBytes: Int64)
    typealias ScanProgress = (scanned: Int, total: Int?, currentPath: String)
    
    private var currentTask: Task<ScanResult, Error>?
    private var currentDetailedTask: Task<DetailedScanResult, Error>?
    
    func scan(directory: URL, 
              progress: @escaping (ScanProgress) -> Void) async throws -> ScanResult {
        // Cancel any existing scan
        currentTask?.cancel()
        
        let task = Task<ScanResult, Error> {
            var results = ScanResult()
            var scannedCount = 0
            
            let resourceKeys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .fileSizeKey,
                                                 .isSymbolicLinkKey, .isPackageKey]
            
            guard let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: resourceKeys,
                options: [.skipsHiddenFiles]
            ) else {
                throw NSError(domain: "ImageFileScanner", code: 1, 
                            userInfo: [NSLocalizedDescriptionKey: "Failed to create enumerator"])
            }
            
            // Safety tracking
            var visitedPaths = Set<String>()
            let maxDepth = 50
            let photoPackageExtensions = Set(["cosessiondb", "lrdata", "photoslibrary", "aplibrary", "photolibrary"])
            
            while let element = enumerator.nextObject() {
                guard let url = element as? URL else { continue }
                
                try Task.checkCancellation()
                
                // Check depth
                let depth = url.pathComponents.count - directory.pathComponents.count
                if depth > maxDepth {
                    enumerator.skipDescendants()
                    continue
                }
                
                let resourceValues = try url.resourceValues(forKeys: Set(resourceKeys))
                
                // Handle symbolic links
                if resourceValues.isSymbolicLink == true {
                    enumerator.skipDescendants()
                    continue
                }
                
                // Handle packages
                if resourceValues.isPackage == true {
                    let ext = url.pathExtension.lowercased()
                    if !photoPackageExtensions.contains(ext) {
                        enumerator.skipDescendants()
                        continue
                    }
                }
                
                guard resourceValues.isRegularFile == true else {
                    visitedPaths.insert(url.path)
                    continue
                }
                
                if let fileType = ImageFileType.from(fileExtension: url.pathExtension) {
                    results[fileType, default: 0] += 1
                }
                
                scannedCount += 1
                if scannedCount % 100 == 0 {
                    progress((scanned: scannedCount, total: nil, currentPath: url.lastPathComponent))
                }
            }
            
            return results
        }
        
        currentTask = task
        return try await task.value
    }
    
    func scanWithSize(directory: URL, 
                      progress: @escaping (ScanProgress) -> Void) async throws -> DetailedScanResult {
        // Cancel any existing scan
        currentTask?.cancel()
        
        print("📂 Starting scan of: \(directory.path)")
        
        var fileTypes = ScanResult()
        var totalBytes: Int64 = 0
        var scannedCount = 0
        var skippedCount = 0
        var rawFileCount = 0
        var skippedPackages = 0
        var resolvedSymlinks = 0
        
        let resourceKeys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .fileSizeKey, 
                                             .isSymbolicLinkKey, .isPackageKey, .isAliasFileKey]
        
        // Create custom enumerator with controlled behavior
        // We'll selectively scan packages that are known photo management structures
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles]  // Keep hidden files skipped
        ) else {
            throw NSError(domain: "ImageFileScanner", code: 1, 
                        userInfo: [NSLocalizedDescriptionKey: "Failed to create enumerator"])
        }
        
        // Track visited paths to prevent circular references
        var visitedPaths = Set<String>()
        
        // Define maximum recursion depth to prevent infinite loops
        let maxDepth = 50  // Reasonable depth for photo libraries
        
        // Photo management packages we should scan inside
        let photoPackageExtensions = Set([
            "cosessiondb",  // Capture One Session
            "lrdata",       // Lightroom data
            "photoslibrary", // Photos.app library
            "aplibrary",    // Aperture library
            "photolibrary"  // Old Photos library
        ])
        
        while let element = enumerator.nextObject() {
            guard let url = element as? URL else { continue }
            
            try Task.checkCancellation()
            
            // Check recursion depth
            let depth = url.pathComponents.count - directory.pathComponents.count
            if depth > maxDepth {
                print("  ⚠️ Skipping deep path (depth \(depth)): \(url.path)")
                enumerator.skipDescendants()
                continue
            }
            
            let resourceValues = try url.resourceValues(forKeys: Set(resourceKeys))
            
            // Handle symbolic links
            if resourceValues.isSymbolicLink == true {
                resolvedSymlinks += 1
                // Resolve the symlink
                do {
                    let resolvedURL = try URL(fileURLWithPath: FileManager.default.destinationOfSymbolicLink(atPath: url.path))
                    let realPath = resolvedURL.path
                    
                    // Check for circular references
                    if visitedPaths.contains(realPath) {
                        print("  ⚠️ Skipping circular symlink: \(url.lastPathComponent) -> \(realPath)")
                        enumerator.skipDescendants()
                        continue
                    }
                    
                    // Don't follow symlinks that point outside the scan directory
                    if !realPath.hasPrefix(directory.path) {
                        print("  ⚠️ Skipping external symlink: \(url.lastPathComponent) -> \(realPath)")
                        enumerator.skipDescendants()
                        continue
                    }
                } catch {
                    print("  ⚠️ Cannot resolve symlink: \(url.lastPathComponent)")
                    enumerator.skipDescendants()
                    continue
                }
            }
            
            // Handle packages (app bundles, etc.)
            if resourceValues.isPackage == true {
                let ext = url.pathExtension.lowercased()
                
                // Only scan inside known photo management packages
                if !photoPackageExtensions.contains(ext) {
                    skippedPackages += 1
                    if skippedPackages <= 5 {
                        print("  ⚠️ Skipping package: \(url.lastPathComponent)")
                    }
                    enumerator.skipDescendants()
                    continue
                }
                // If it's a photo package, we'll scan inside it
                print("  📦 Scanning photo package: \(url.lastPathComponent)")
            }
            
            // Skip if it's a directory (unless it's a photo package we're scanning)
            guard resourceValues.isRegularFile == true else {
                // Mark this directory as visited
                visitedPaths.insert(url.path)
                continue
            }
            
            let ext = url.pathExtension
            if let fileType = ImageFileType.from(fileExtension: ext) {
                fileTypes[fileType, default: 0] += 1
                
                // Debug: track RAW files specifically
                if fileType.isRaw {
                    rawFileCount += 1
                    if rawFileCount <= 5 || rawFileCount % 100 == 0 {
                        print("  🎯 RAW #\(rawFileCount): \(url.lastPathComponent) (\(fileType.rawValue))")
                    }
                }
                
                // Add file size to total
                if let fileSize = resourceValues.fileSize {
                    totalBytes += Int64(fileSize)
                }
            } else if !ext.isEmpty {
                skippedCount += 1
                if skippedCount <= 10 {
                    print("  ⚠️ Skipped unsupported: .\(ext) - \(url.lastPathComponent)")
                }
            }
            
            scannedCount += 1
            if scannedCount % 100 == 0 {
                progress((scanned: scannedCount, total: nil, currentPath: url.lastPathComponent))
            }
        }
        
        print("📊 Scan complete:")
        print("  - Total files scanned: \(scannedCount)")
        print("  - RAW files found: \(rawFileCount)")
        print("  - Files skipped (unsupported): \(skippedCount)")
        print("  - Packages skipped: \(skippedPackages)")
        print("  - Symlinks resolved: \(resolvedSymlinks)")
        print("  - Total size: \(totalBytes / (1024*1024*1024)) GB")
        
        // Print breakdown by type
        for (type, count) in fileTypes.sorted(by: { $0.value > $1.value }) {
            print("    \(type.rawValue): \(count)")
        }
        
        return (fileTypes, totalBytes)
    }
    
    func cancel() {
        currentTask?.cancel()
        currentDetailedTask?.cancel()
    }
    
    // Helper to get a nice summary string
    static func formatScanResults(_ results: ScanResult, groupRaw: Bool = false) -> String {
        if results.isEmpty {
            return "No supported files found"
        }
        
        // Group counts by category
        var rawCount = 0
        var videoCount = 0
        var sidecarCount = 0
        var imageCount = 0
        var imageCounts: [(ImageFileType, Int)] = []
        
        for (type, count) in results {
            if type.isRaw {
                rawCount += count
            } else if type.isVideo {
                videoCount += count
            } else if type.isSidecar {
                sidecarCount += count
            } else {
                imageCount += count
                imageCounts.append((type, count))
            }
        }
        
        var parts: [String] = []
        
        // Add counts in priority order
        if rawCount > 0 {
            parts.append("\(rawCount.formatted()) RAW")
        }
        
        // Show top image formats
        for (type, count) in imageCounts.sorted(by: { $0.1 > $1.1 }).prefix(2) {
            parts.append("\(count.formatted()) \(type.rawValue)")
        }
        
        if videoCount > 0 {
            parts.append("\(videoCount.formatted()) Video")
        }
        
        if sidecarCount > 0 {
            parts.append("\(sidecarCount.formatted()) Sidecar")
        }
        
        // Limit to 5 parts total
        if parts.count > 5 {
            parts = Array(parts.prefix(4))
            parts.append("...")
        }
        
        return parts.joined(separator: " • ")
    }
}