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

### 🎨 Thoughtfully Designed
- **Clean, native Mac interface** – No Java, no weird UI, just a proper Mac app
- **Preferences that make sense** – Organized settings, not a maze of options
- **Smart notifications** – Get notified when backups complete
- **Privacy-first** – Anonymize logs when sharing for support

## New in Version 2.0.0

### Major New Features
- **Vision Framework Integration** – AI-powered image analysis during backup (Apple Silicon only)
- **Swift 6 Compliance** – Full strict concurrency checking for enhanced stability
- **M5 Processor Support** – Ready for next-generation Apple Silicon

### Previous Updates

### Critical Fixes
- **Fixed Progress Tracking** – Accurate file counting for multi-destination backups
- **Fixed Cancel Button** – Now works reliably during all operations
- **Fixed File Counter Overflow** – No more counting past 100% with multiple destinations

### Network Performance
- **Network Performance Settings** – Configurable timeouts, speed limiting, and buffer sizes for SMB/NAS
- **Stream-Based Network Copy** – Cancellable, throttleable copying method for unreliable connections
- **Enhanced SMB Stability** – No more indefinite hangs when network drives disconnect
- **Smart Timeout Protection** – Configurable timeout (default 90 seconds) prevents stuck transfers

### Safety & Security
- **Improved File Handling** – Smarter handling of aliases, symbolic links, and special files
- **Extended Metadata** – Preserves Finder tags, comments, and custom file attributes
- **Enhanced Data Integrity** – Better protection when backing up to network volumes
- **Better Help System** – Improved documentation with easier access from the Help menu
- **Security Enhancements** – Multiple under-the-hood improvements for safer backups

## Real-World Use

### Daily Workflow
After a shoot, drop your cards into folders and let ImageIntact mirror them to your backup drives. It'll verify every file and show you exactly what was copied.

### Archive Management
Use ImageIntact to maintain multiple copies of your archive. It understands that your 2015 folder shouldn't change, so it won't waste time re-copying thousands of files.

### Client Delivery
Need to copy final images to a client drive? ImageIntact ensures every file is perfect with cryptographic verification – no more worried emails about corrupt files.

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
- macOS 15.0 (Sequoia) or later
- Compatible with macOS 26 (Tahoe)
- Works great on both Intel and Apple Silicon Macs
- Note: macOS Tahoe (26) is the last version supporting Intel Macs

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
- Written in Swift using SwiftUI for a native Mac experience
- SHA-256 checksums for cryptographic verification
- Queue-based architecture with adaptive worker threads
- Core Data for robust event logging
- Comprehensive test coverage

## Building from Source

The `main` branch contains the latest development version with new features not yet released.

```bash
git clone https://github.com/Tonal-Photo/ImageIntact.git
cd ImageIntact
open ImageIntact.xcodeproj
```

Build and run in Xcode (requires Xcode 15+ for releases, Xcode 26+ for development).

## Roadmap

Coming in future versions:
- v1.3: Resume interrupted backups, professional video format support
- v1.4: Spotlight integration for searching backed-up images
- v1.5: AI-powered similarity detection and face grouping

See the full [roadmap](https://github.com/Tonal-Photo/ImageIntact/issues?q=is%3Aissue+is%3Aopen+label%3Aenhancement) for details.

## License

MIT License – Use it, modify it, share it. Just keep your photos safe.

---

*Built with ❤️ by a photographer who was tired of losing sleep over backups.*

**Download ImageIntact today and never worry about losing photos again.**
