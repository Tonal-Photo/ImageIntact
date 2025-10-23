# Changelog

All notable changes to ImageIntact will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2025-10-23

### Major New Features

#### 🔍 Smart Image Search (Apple Silicon Only)
- **Semantic Search**: Find images using natural language queries powered by Apple Foundation Models (macOS 26+)
  - Search by content: "sunset beach", "birthday party", "wedding photos"
  - Understands concepts, not just keywords
  - AI-powered ranking with confidence scores
- **Browse Mode**: Explore analyzed images by category
  - Drill-down navigation: Category lists → Image grids
  - Scenes: "outdoor", "plant", "sky", "architecture"
  - Objects: Detected items like "dog", "car", "person"
  - Text: Images containing recognized text
  - Faces: Images with detected faces (privacy-aware, no identification)
  - Technical: Filter by colors, quality metrics, camera data
- **Apple HIG Compliant UI**: Professional utility window design
  - Unified custom header with integrated search
  - Resizable window (700×500 minimum)
  - Native macOS 26 Tahoe design patterns

#### 🤖 Vision Framework Integration (Apple Silicon Only)
- **Automatic Image Analysis**: AI-powered analysis during backup
  - Object detection (100+ categories: person, dog, car, plant, food, etc.)
  - Scene classification (beach, forest, wedding, celebration, indoor, outdoor, etc.)
  - Face detection with privacy protection (count only, no identification)
  - Text recognition (OCR for signs, documents, receipts)
  - Barcode/QR code detection and decoding
  - Saliency maps for main subject identification
  - Horizon detection for landscape photos
  - Rectangle detection for documents
  - Feature prints for future similarity detection
- **CPU-Adaptive Processing**: Intelligent throttling based on Apple Silicon generation
  - M1: 2 concurrent analyses
  - M2: 3 concurrent analyses
  - M3: 4 concurrent analyses
  - M4: 6 concurrent analyses
  - M5: 6 concurrent analyses (ready for future hardware)
- **Non-Blocking Analysis**: Runs in background, never blocks backup operations
- **Thermal & Memory Awareness**: Automatically throttles under system pressure

#### 🎨 Core Image Analysis (Apple Silicon Only)
- **Color Analysis**: Dominant colors and color palettes
- **Quality Metrics**: Sharpness, blur detection, noise analysis
- **Histogram Generation**: RGB channel histograms for technical analysis
- **Enhanced EXIF Extraction**: Camera model, lens, settings, GPS data

#### 💾 Removable Drive Intelligence
- **Drive UUID Tracking**: Identify and track removable drives across reconnections
  - Uses IOKit for persistent drive identification
  - Stores volumeUUID and volumeName with each analyzed image
- **Disconnected Drive Detection**: Smart Search shows when images are on unavailable drives
  - Visual placeholder with drive name
  - "Drive 'PhotoBackup' not connected" messaging
  - Graceful handling of internal vs. external vs. network drives

#### ⏰ Timestamp-Based Folder Organization
- **ISO 8601 Timestamps**: Create folders with international-standard timestamps
  - Format: `YYYY-MM-DD_HH-MM` (e.g., `2025-10-23_14-05`)
  - Sorts chronologically, file-system safe
  - Per-minute resolution for session grouping
- **Simple Checkbox UI**: "Use timestamp for folder name" in Backup Organization
  - Immediately updates preview path
  - Field remains editable for customization
  - Per-preset setting (saved with custom presets)
- **Consistent Timestamps**: Generated once at backup start, used across all destinations
- **Designed for Extensibility**: Backend ready for v2.1 template variable system

### Technical Improvements

#### 🏗️ Core Data Enhancements
- **Schema v4 Migration**: Added driveUUID and volumeName to ImageMetadata
  - Efficient fetch indexes for drive queries
  - Lightweight automatic migration from v3
- **Schema v3**: Vision Framework and Core Image metadata storage
  - ImageMetadata entity for AI analysis results
  - DetectedObject, SceneClassification, FaceRectangle entities
  - ExifData and ImageColorAnalysis entities
  - ImageQualityMetrics and ImageHistogram entities
  - Proper relationships and indexes for performance

#### 🚀 Performance & Architecture
- **Swift 6 Strict Concurrency**: Full compliance across codebase
  - Proper @MainActor isolation
  - @Sendable conformance for all transferred types
  - Actor-based concurrent processing
  - Zero data races
- **Foundation Models Integration**: On-device AI powered by Apple's 3B parameter LLM
  - @Generable structs for structured output
  - Two-stage search (pre-filter + semantic ranking)
  - Context window management (4096 token limit)
- **Dual-Pipeline Processing**: Vision and Core Image analysis in parallel
  - Async/await throughout
  - Efficient batch processing
  - Memory-efficient image loading

#### 🎯 Developer Experience
- **Enhanced Documentation**: VISION_FRAMEWORK_DECISIONS.md with all architectural decisions
- **Comprehensive Logging**: Detailed console output for debugging analysis
- **Test Infrastructure**: Mock objects and helpers for Vision Framework testing

### Changed
- Renamed "destinationOrganizationName" to "organizationName" for clarity
- Updated backup preset system to store timestamp preferences
- Improved error messages for Vision Framework availability
- Enhanced DriveMonitor to track connected drive UUIDs

### Fixed
- Smart Search enter key now works on first press (Foundation Models initialization race condition)
- Thumbnail loading fixed with proper security-scoped bookmark access
- Browse categories properly display in all tabs
- Smart Search window properly resizable
- Category picker placement stable (footer instead of toolbar)
- Vision Framework IOSurface warnings properly handled (harmless, expected behavior)

### Apple Silicon Requirements
Vision Framework, Core Image analysis, and Smart Search features require Apple Silicon (M1 or later).
Intel Mac users can still use all core backup features, but AI-powered analysis is unavailable.

### Compatibility
- **macOS**: 15.0 (Sequoia) minimum, 26.0 (Tahoe) for Foundation Models
- **Architecture**: Universal (Intel + Apple Silicon), AI features require Apple Silicon
- **Note**: macOS 26 Tahoe is the last version supporting Intel Macs

---

## [1.3.0] - 2025-10-20

### Added
- Progress indicator fixes for multi-destination backups
- Window activation and visibility improvements
- Actor isolation fixes for batch event logging
- Release documentation and App Store notes

### Fixed
- Progress stuck at 0% issue
- Large backup confirmation flow
- Double checksum calculation eliminated
- Cancel button reliability
- File counter overflow with multiple destinations

---

## [1.2.9] - 2025-09-21

### Network Performance
- Network performance settings with configurable timeouts
- Stream-based network copy for SMB/NAS reliability
- Enhanced SMB stability with timeout protection
- Speed limiting and buffer size configuration

### Safety & Security
- Improved file handling for aliases and symbolic links
- Extended metadata preservation (Finder tags, comments)
- Enhanced data integrity for network volumes
- Better help system with improved documentation

### Changed
- SHA-256 to SHA-1 checksum switch for 3-5x speed improvement
- Network timeout default: 90 seconds

---

## Earlier Versions

See [GitHub Releases](https://github.com/Tonal-Photo/ImageIntact/releases) for full history.

