# ImageIntact

**Your photos are irreplaceable. Back them up right.**

ImageIntact is the backup app photographers have been waiting for – built by a photographer who understands that losing images isn't an option. Unlike generic backup tools, ImageIntact speaks your language and protects your workflow.

![macOS](https://img.shields.io/badge/macOS-15.0%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.0%2B-orange)
![License](https://img.shields.io/badge/License-MIT-green)
![Version](https://img.shields.io/badge/Version-2.0.0-brightgreen)

## Why ImageIntact?

After 25+ years in tech and countless hours behind the camera, I built ImageIntact because existing backup solutions just don't get it. They're either too complex, too slow, or – worst of all – they don't verify your files actually copied correctly. 

ImageIntact is different. It's fast, it's safe, and it just works.

## What Makes It Special

### 🎯 Built for Photographers
- **Understands your files** – RAW, JPEG, TIFF, DNG, and every format you shoot
- **Respects your workflow** – Works with Lightroom, Capture One, and your folder structure
- **Multiple destinations** – Back up to 4 drives simultaneously (because one backup isn't enough)
- **Smart filtering** – Back up only RAWs, only JPEGs, or all images

### ⚡ Actually Fast
- **Parallel processing** – Each destination runs independently at full speed
- **Smart copying** – Skips files that are already backed up and are exact copies of the originals
- **Optimized for SSDs** – Takes advantage of modern drive speeds
- **Real-time progress** – See exactly what's happening and when it'll finish

### 🛡️ Genuinely Safe
- **Verification built-in** – Every file is checksummed to ensure perfect copies
- **Never deletes** – Suspicious files are quarantined, never removed
- **Complete audit trail** – Know exactly what happened to every file
- **Sleep prevention** – Your Mac won't sleep mid-backup
- **Network drive safety** – Enhanced data integrity for NAS and network volumes
- **SMB timeout protection** – No more indefinite hangs on network issues

### 🤖 Intelligent (Apple Silicon)
- **AI-Powered Analysis** – Automatic object, scene, and face detection during backup (FREE)
- **Removable Drive Tracking** – Know which images are on disconnected drives (FREE)
- **Smart Image Search** – Find photos using natural language queries (macOS 26+) **[Pro]**
- **Browse by Category** – Explore your backed-up images by detected content **[Pro]**
- **Privacy-First AI** – All analysis happens on your Mac, nothing leaves your device

### 🎨 Thoughtfully Designed
- **Clean, native Mac interface** – No Java, no weird UI, just a proper Mac app
- **Preferences that make sense** – Organized settings, not a maze of options
- **Smart notifications** – Get notified when backups complete
- **Timestamp organization** – ISO 8601 timestamps for chronological folder names
- **Privacy-first** – Anonymize logs when sharing for support

## New in Version 2.0.0

### 🔍 Smart Image Search (Apple Silicon Only) **[Pro Feature]**

**Find your photos using natural language.** Powered by Apple Foundation Models (macOS 26+), Smart Search lets you search your backed-up images using phrases like "sunset beach", "birthday party", or "wedding photos". The AI understands concepts, not just keywords.

- **Semantic Search**: Natural language queries with AI-powered ranking **[Pro]**
- **Browse Mode**: Explore by Scenes, Objects, Text, Faces, Colors, or Technical metrics **[Pro]**
- **Drill-Down Navigation**: Click a category to see matching images **[Pro]**
- **Disconnected Drive Detection**: See which images are on unplugged drives (FREE)

### 🤖 Vision Framework & Core Image Integration (Apple Silicon Only) **[FREE]**

**Your backups get smarter automatically.** ImageIntact analyzes images during backup using Apple's Vision and Core Image frameworks, extracting rich metadata that powers Smart Search. **Image analysis is completely free** – Pro features unlock the ability to search and browse the analyzed data.

**Vision Framework Analysis (FREE):**
- Object detection (100+ categories: person, dog, car, plant, food, etc.)
- Scene classification (beach, forest, wedding, indoor, outdoor, etc.)
- Face detection (privacy-aware: counts only, no identification)
- Text recognition (OCR for signs, documents, receipts)
- Barcode/QR code detection
- Saliency maps, horizon detection, and more

**Core Image Analysis (FREE):**
- Dominant colors and color palettes
- Quality metrics (sharpness, blur, noise)
- Histogram generation
- Enhanced EXIF extraction (camera, lens, settings)

**Performance:**
- CPU-adaptive: 2-6 concurrent analyses based on your M-series chip
- Non-blocking: Never slows down your backup
- Thermal-aware: Automatically throttles under system pressure
- All processing happens on your Mac - no cloud required

### 💾 Removable Drive Intelligence

**Never lose track of your backup drives.** ImageIntact now tracks which images are on which drives using IOKit drive UUIDs.

- Drive UUID and volume name stored with each image
- Smart Search shows when images are on disconnected drives
- Visual placeholders with drive name: "Image is on disconnected drive 'PhotoBackup'"
- Works with external drives, network volumes, and memory cards

### ⏰ Timestamp-Based Folder Organization

**Organize backups chronologically.** New checkbox in Backup Organization creates folders with ISO 8601 timestamps.

- Format: `YYYY-MM-DD_HH-MM` (e.g., `2025-10-23_14-05`)
- Sorts chronologically, file-system safe, internationally understood
- Field remains editable for customization
- Per-preset setting (saved with your custom presets)
- Perfect for camera card imports and dated sessions

### 🏗️ Technical Improvements

- **Swift 6 Strict Concurrency**: Full compliance across codebase for enhanced stability
- **Core Data Schema v4**: Enhanced metadata storage with drive UUID tracking
- **Foundation Models Integration**: On-device AI powered by Apple's 3B parameter LLM
- **M5 Processor Support**: Ready for next-generation Apple Silicon
- **Dual-Pipeline Processing**: Vision and Core Image analysis in parallel
- **Apple HIG Compliant UI**: Smart Search window follows macOS 26 Tahoe design patterns

See the full [CHANGELOG.md](CHANGELOG.md) for complete details.

## Real-World Use

### Daily Workflow
After a shoot, drop your cards into folders and let ImageIntact mirror them to your backup drives. It'll verify every file and show you exactly what was copied. On Apple Silicon, images are automatically analyzed for free, cataloging objects, scenes, and faces. Upgrade to Pro to unlock Smart Search and browse your entire photo collection using natural language.

### Archive Management
Use ImageIntact to maintain multiple copies of your archive. It understands that your 2015 folder shouldn't change, so it won't waste time re-copying thousands of files. With Pro, Smart Search lets you find specific images across all your backup drives, even if some are disconnected.

### Client Delivery
Need to copy final images to a client drive? ImageIntact ensures every file is perfect with cryptographic verification – no more worried emails about corrupt files. Use timestamp-based organization to create clearly dated delivery folders.

### Finding That Perfect Shot
(Apple Silicon + Pro) Lost track of a specific image? Use Smart Search to find it: "sunset beach with dogs", "birthday cake indoors", or just browse by category. Works even when backup drives are disconnected - you'll know exactly which drive to plug in. All your backed-up images are automatically analyzed for free; Pro unlocks the search interface.

## Getting Started

### Quick Install
1. Download the latest release from the [Releases](https://github.com/Tonal-Photo/ImageIntact/releases/latest) page
2. Open the DMG and drag ImageIntact to your Applications folder
3. Launch and approve folder access when asked
4. Select your source folder, pick your backup destinations, and click "Run Backup"

#### macOS Permissions
ImageIntact uses the standard macOS file picker for folder access. When you select folders:
- You'll be asked to grant access to those specific folders
- No Full Disk Access required - just approve the folders you want to backup
- Works seamlessly with macOS Tahoe's enhanced permission system
- Your selections are remembered between launches

That's it. No complex configuration, no command lines, no stress.

### System Requirements
- **macOS**: 15.0 (Sequoia) minimum, 26.0 (Tahoe) for Foundation Models semantic search
- **Architecture**: Universal (Intel + Apple Silicon)
- **AI Features**: Require Apple Silicon (M1 or later)
  - Smart Image Search
  - Vision Framework analysis
  - Core Image analysis
  - Semantic search with Foundation Models (macOS 26+)
- **Note**: macOS 26 Tahoe is the last version supporting Intel Macs
- **Note**: Intel Macs can use all core backup features; AI features are Apple Silicon-only

## Why Open Source?

This is my give-back to the photography community. The code is open so you can verify it does exactly what it says – nothing more, nothing less. No telemetry, no cloud requirements, no subscriptions. Just a solid tool that does one thing really well.

## Support the Project

ImageIntact is free and always will be. If it saves your photos (and your sanity), consider:
- ⭐ Starring the project on GitHub
- 🐛 Reporting bugs or suggesting features
- 📸 Telling other photographers about it
- ☕ [Buying me a coffee](https://github.com/sponsors/Tonal-Photo) (coming soon)

## Need Help?

- **Quick Start**: Check the in-app help (Help menu)
- **Issues**: Report problems on the [Issues](https://github.com/Tonal-Photo/ImageIntact/issues) page
- **Discussions**: Join the conversation in [Discussions](https://github.com/Tonal-Photo/ImageIntact/discussions)

## Technical Details

For the curious or technically inclined:
- **Language**: Swift 5.0+ with SwiftUI for native Mac UI
- **Concurrency**: Swift 6 strict concurrency compliance with actors and @MainActor
- **AI Frameworks**: Apple Vision Framework and Core Image (Apple Silicon only)
- **On-Device LLM**: Apple Foundation Models (3B parameter model, macOS 26+)
- **Verification**: SHA-1 checksums for fast, reliable file verification
- **Architecture**: Queue-based with adaptive worker threads (1-8 per destination)
- **Storage**: Core Data v4 for event logging and metadata
- **Drive Detection**: IOKit for persistent drive UUID tracking
- **UI Patterns**: Apple Human Interface Guidelines (macOS 26 Tahoe)
- **Test Coverage**: Comprehensive unit and integration tests

## Building from Source

The `main` branch contains the latest development version with new features not yet released.

```bash
git clone https://github.com/Tonal-Photo/ImageIntact.git
cd ImageIntact
open ImageIntact.xcodeproj
```

Build and run in Xcode (requires Xcode 15+ for releases, Xcode 26+ for development).

## Roadmap

**v2.0 (Current)**: Smart Image Search, Vision/Core Image analysis, removable drive tracking, timestamp organization ✅

Coming in future versions:
- **v2.1**: Spotlight integration for system-wide image search, template variable system for folder naming
- **v2.2**: AI-powered similarity detection, face grouping, automatic collections
- **v2.3**: Enhanced network drive support, cloud destination connectors

See the full [roadmap](https://github.com/Tonal-Photo/ImageIntact/issues?q=is%3Aissue+is%3Aopen+label%3Aenhancement) for details.

## License

MIT License – Use it, modify it, share it. Just keep your photos safe.

---

*Built with ❤️ by a photographer who was tired of losing sleep over backups.*

**Download ImageIntact today and never worry about losing photos again.**
