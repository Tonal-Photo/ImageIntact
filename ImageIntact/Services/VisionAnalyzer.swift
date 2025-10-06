//
//  VisionAnalyzer.swift
//  ImageIntact
//
//  AI-powered image analysis using Vision Framework
//  Apple Silicon ONLY - Disabled on Intel Macs
//

import Foundation
@preconcurrency import Vision
import CoreImage
import CoreData
import UniformTypeIdentifiers
import ImageIO
import AppKit

/// Manages Vision Framework analysis for images during backup
@MainActor
class VisionAnalyzer: ObservableObject {
    static let shared = VisionAnalyzer()

    // MARK: - Published Properties
    @Published private(set) var isAnalyzing = false
    @Published private(set) var currentAnalysisCount = 0
    @Published private(set) var totalAnalysisCount = 0
    @Published private(set) var currentImageName = ""
    @Published private(set) var analysisProgress: Double = 0.0

    // MARK: - Configuration
    private let maxConcurrentAnalyses: Int
    private let isEnabled: Bool

    // MARK: - Vision Requests
    private lazy var objectDetectionRequest: VNCoreMLRequest? = {
        guard isEnabled else { return nil }
        // Use built-in object detection
        return nil // Will be replaced with actual model in future
    }()

    private lazy var sceneClassificationRequest: VNClassifyImageRequest? = {
        guard isEnabled else { return nil }
        let request = VNClassifyImageRequest()
        // maximumObservations is not available, will get top results
        return request
    }()

    private lazy var faceDetectionRequest: VNDetectFaceRectanglesRequest? = {
        guard isEnabled else { return nil }
        let request = VNDetectFaceRectanglesRequest()
        // maximumObservations not available for face detection
        return request
    }()

    private lazy var textDetectionRequest: VNRecognizeTextRequest? = {
        guard isEnabled else { return nil }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        return request
    }()

    private lazy var objectRecognitionRequest: VNRecognizeAnimalsRequest? = {
        guard isEnabled else { return nil }
        return VNRecognizeAnimalsRequest()
    }()

    // MARK: - Initialization
    private init() {
        // Check if we're on Apple Silicon
        let capabilities = SystemCapabilities.shared
        self.isEnabled = capabilities.processorType == .appleSilicon

        if !isEnabled {
            ApplicationLogger.shared.warning("Vision Framework disabled - Intel Mac detected", category: .vision)
            self.maxConcurrentAnalyses = 0
        } else {
            // Determine concurrent analysis limit based on processor
            self.maxConcurrentAnalyses = Self.getConcurrentLimit(for: capabilities.processorGeneration)
            ApplicationLogger.shared.info("Vision Framework enabled - \(capabilities.displayName) detected with limit: \(maxConcurrentAnalyses)", category: .vision)
        }
    }

    // MARK: - CPU Adaptive Limits
    private static func getConcurrentLimit(for generation: SystemCapabilities.ProcessorGeneration) -> Int {
        // Based on Apple's guidance for Vision Framework (typically max 5 concurrent)
        // Adjusted for M-series Neural Engine capabilities and memory bandwidth
        // IOSurface warnings are normal and don't indicate failures
        switch generation {
        case .m1:
            return 2  // 8-core Neural Engine, 8 CPU cores (4+4)
        case .m2:
            return 3  // 16-core Neural Engine, 8+ CPU cores, better memory bandwidth
        case .m3:
            return 4  // 16-core Neural Engine, improved efficiency cores
        case .m4:
            return 5  // 16-core Neural Engine, 38 TOPS, highest memory bandwidth
        case .m5:
            return 6  // Expected: Enhanced Neural Engine, 3nm process, higher TOPS
        case .unknown:
            return 2  // Conservative default for unknown processors
        }
    }

    // MARK: - Public Methods

    /// Check if Vision analysis is available
    var isAvailable: Bool {
        return isEnabled
    }

    /// Analyze an image file
    func analyzeImage(at url: URL, checksum: String) async throws {
        guard isEnabled else {
            throw VisionAnalyzerError.notAvailable
        }

        // Already-analyzed check is now done in the caller to avoid duplicate work

        // Get original image dimensions first (without loading full image)
        let originalDimensions = getImageDimensions(from: url)

        // Run Core Image analysis in parallel with Vision
        let coreImageTask = Task {
            try await CoreImageAnalyzer.shared.analyzeImage(at: url, checksum: checksum)
        }

        // Update UI
        await MainActor.run {
            self.currentImageName = url.lastPathComponent
            self.currentAnalysisCount += 1
        }

        // Retry logic for permission errors
        var imageSource: CGImageSource?
        var retryCount = 0
        let maxRetries = 3

        while retryCount < maxRetries {
            imageSource = CGImageSourceCreateWithURL(url as CFURL, [
                kCGImageSourceShouldCache: false as NSNumber
            ] as CFDictionary)

            if imageSource != nil {
                break
            }

            // Wait and retry if failed
            retryCount += 1
            if retryCount < maxRetries {
                let waitTime = retryCount * 1000 // 1s, 2s, etc.
                print("⚠️ Failed to load image \(url.lastPathComponent), retrying in \(waitTime)ms... (attempt \(retryCount + 1)/\(maxRetries))")
                try await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000)) // Exponential backoff
            }
        }

        guard let finalImageSource = imageSource else {
            throw VisionAnalyzerError.imageLoadFailed
        }

        // Create a smaller thumbnail to reduce memory usage and IOSurface warnings
        // Wrap in autorelease pool for better memory management
        let handler = try autoreleasepool {

            // Create a smaller thumbnail (1024px instead of 2048px) to reduce memory pressure
            let options: [CFString: Any] = [
                kCGImageSourceShouldCache: false,
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 2048, // Back to 2048 as requested by user
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceSubsampleFactor: 2 // Subsample for faster processing
            ]

            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(finalImageSource, 0, options as CFDictionary) else {
                throw VisionAnalyzerError.imageLoadFailed
            }

            // Create handler without additional caching
            return VNImageRequestHandler(cgImage: cgImage, options: [
                .ciContext: CIContext(options: [
                    .useSoftwareRenderer: false,
                    .cacheIntermediates: false
                ])
            ])
        }

        // Prepare requests
        var requests: [VNRequest] = []

        if let sceneRequest = sceneClassificationRequest {
            requests.append(sceneRequest)
        }
        if let faceRequest = faceDetectionRequest {
            requests.append(faceRequest)
        }
        if let textRequest = textDetectionRequest {
            requests.append(textRequest)
        }
        if let animalRequest = objectRecognitionRequest {
            requests.append(animalRequest)
        }

        // Perform analysis in autorelease pool for better memory management
        do {
            try autoreleasepool {
                try handler.perform(requests)
            }
        } catch {
            ApplicationLogger.shared.error("Vision analysis failed for \(url.lastPathComponent): \(error)", category: .vision)
            throw VisionAnalyzerError.analysisFailed(error)
        }

        // Extract results
        let sceneResults = sceneClassificationRequest?.results as? [VNClassificationObservation]
        let faceResults = faceDetectionRequest?.results as? [VNFaceObservation]
        let textResults = textDetectionRequest?.results as? [VNRecognizedTextObservation]
        let animalResults = objectRecognitionRequest?.results as? [VNRecognizedObjectObservation]

        // Log what we found
        print("🤖 Vision Analysis for \(url.lastPathComponent):")

        if let scenes = sceneResults?.prefix(3) {
            let sceneDescriptions = scenes.map { "\($0.identifier.humanReadable) (\(Int($0.confidence * 100))%)" }
            if !sceneDescriptions.isEmpty {
                print("  📸 Scenes: \(sceneDescriptions.joined(separator: ", "))")
            }
        }

        if let faces = faceResults, !faces.isEmpty {
            print("  👤 Faces detected: \(faces.count)")
        }

        if let animals = animalResults, !animals.isEmpty {
            let animalTypes = animals.compactMap { $0.labels.first?.identifier.humanReadable }
            print("  🐾 Animals: \(animalTypes.joined(separator: ", "))")
        }

        if let texts = textResults, !texts.isEmpty {
            let textSnippets = texts.prefix(2).compactMap { $0.topCandidates(1).first?.string }
            if !textSnippets.isEmpty {
                print("  📝 Text found: \"\(textSnippets.joined(separator: ", "))...\"")
            }
        }

        // Also log to ApplicationLogger for persistence
        ApplicationLogger.shared.info(
            "Vision analysis completed for \(url.lastPathComponent): " +
            "Scenes: \(sceneResults?.count ?? 0), " +
            "Faces: \(faceResults?.count ?? 0), " +
            "Animals: \(animalResults?.count ?? 0), " +
            "Text blocks: \(textResults?.count ?? 0)",
            category: .vision
        )

        // Wait for Core Image analysis to complete
        let coreImageResult = try? await coreImageTask.value

        // Process and store results
        await storeAnalysisResults(
            url: url,
            checksum: checksum,
            originalDimensions: originalDimensions,
            sceneResults: sceneResults,
            faceResults: faceResults,
            textResults: textResults,
            animalResults: animalResults,
            coreImageResult: coreImageResult
        )

        // Force cleanup of image resources to prevent IOSurface accumulation
        autoreleasepool { }  // Explicit drain to release any lingering resources
    }

    /// Queue images with checksums for analysis (new method for source file processing)
    func queueImagesForAnalysisWithChecksums(_ images: [(url: URL, checksum: String)], sourceFolderURL: URL? = nil) {
        guard isEnabled else { return }

        Task { @MainActor in
            self.totalAnalysisCount = images.count
            self.currentAnalysisCount = 0
            self.isAnalyzing = true
            self.analysisProgress = 0.0
            // Report to ProgressPublisher
            ProgressPublisher.shared.updateAnalysisProgress(current: 0, total: images.count)
        }

        // Process images SEQUENTIALLY to avoid IOSurface exhaustion
        Task.detached(priority: .background) { [weak self] in
            guard let self = self else { return }

            // Start accessing the source folder's security-scoped resource
            var sourceAccessing = false
            if let sourceFolderURL = sourceFolderURL {
                sourceAccessing = sourceFolderURL.startAccessingSecurityScopedResource()
                print("🔐 Started security-scoped access for source folder: \(sourceFolderURL.path), success: \(sourceAccessing)")
            }
            defer {
                if sourceAccessing, let sourceFolderURL = sourceFolderURL {
                    sourceFolderURL.stopAccessingSecurityScopedResource()
                    print("🔐 Stopped security-scoped access for source folder")
                }
            }

            // Create a single VNSequenceRequestHandler for all images
            // This reuses resources better than creating new handlers
            let sequenceHandler = VNSequenceRequestHandler()

            for (index, image) in images.enumerated() {
                do {
                    // Check if already analyzed using provided checksum
                    let isAnalyzed = await self.isAlreadyAnalyzed(checksum: image.checksum)
                    if isAnalyzed {
                        print("⏭️ Skipping already analyzed: \(image.url.lastPathComponent)")
                    } else {
                        print("🔍 Analyzing image \(index + 1)/\(images.count): \(image.url.lastPathComponent)")

                        // Process with the sequence handler (using provided checksum)
                        try await self.analyzeImageWithSequenceHandler(
                            at: image.url,
                            checksum: image.checksum,
                            handler: sequenceHandler
                        )

                        // Small delay between images to ensure cleanup
                        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
                    }

                    // Update progress
                    await MainActor.run {
                        self.currentAnalysisCount = index + 1
                        self.analysisProgress = Double(self.currentAnalysisCount) / Double(self.totalAnalysisCount)
                        // Report to ProgressPublisher
                        ProgressPublisher.shared.updateAnalysisProgress(current: self.currentAnalysisCount, total: self.totalAnalysisCount)
                        print("📊 Vision progress: \(self.currentAnalysisCount)/\(self.totalAnalysisCount)")
                    }
                } catch {
                    await ApplicationLogger.shared.error("Failed to analyze \(image.url.lastPathComponent): \(error)", category: .vision)
                }
            }

            // Mark completion
            await MainActor.run {
                self.isAnalyzing = false
                self.analysisProgress = 1.0
                ApplicationLogger.shared.info("Vision analysis complete for \(self.totalAnalysisCount) images", category: .vision)
                self.currentAnalysisCount = 0
                self.totalAnalysisCount = 0
            }
        }
    }

    /// Queue multiple images for analysis (legacy method, redirects to new method)
    func queueImagesForAnalysis(_ urls: [URL]) {
        guard isEnabled else { return }

        Task { @MainActor in
            // Add to existing count instead of resetting for incremental additions
            self.totalAnalysisCount = urls.count
            self.currentAnalysisCount = 0
            self.isAnalyzing = true
            self.analysisProgress = 0.0
        }

        // Process images with proper concurrency control using TaskGroup
        Task.detached(priority: .background) { [weak self] in
            guard let self = self else { return }

            // Use withTaskGroup to limit concurrency properly
            await withTaskGroup(of: Void.self) { group in
                var activeCount = 0
                var urlIndex = 0

                // Process URLs with controlled concurrency
                while urlIndex < urls.count {
                    // Add tasks up to the concurrency limit
                    while activeCount < self.maxConcurrentAnalyses && urlIndex < urls.count {
                        let url = urls[urlIndex]
                        urlIndex += 1
                        activeCount += 1

                        group.addTask { [weak self, capturedIndex = urlIndex] in
                            guard let self = self else { return }

                            do {
                                // Add a small initial delay to prevent rush, based on the captured index
                                try await Task.sleep(nanoseconds: UInt64(capturedIndex * 200_000_000)) // Stagger start by 200ms each

                                // Calculate checksum first to avoid duplicate work
                                let checksum = try self.calculateChecksum(for: url)

                                // Check if already analyzed before printing
                                if await self.isAlreadyAnalyzed(checksum: checksum) {
                                    print("⏭️ Skipping already analyzed: \(url.lastPathComponent)")
                                    return
                                }

                                print("🔍 Starting Vision analysis for: \(url.lastPathComponent)")

                                // Analyze
                                try await self.analyzeImage(at: url, checksum: checksum)

                                // Longer delay after analysis to prevent IOSurface exhaustion
                                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay after each analysis

                                // Update progress
                                await MainActor.run {
                                    self.currentAnalysisCount += 1
                                    self.analysisProgress = Double(self.currentAnalysisCount) / Double(self.totalAnalysisCount)
                                    print("📊 Vision progress: \(self.currentAnalysisCount)/\(self.totalAnalysisCount)")
                                }
                            } catch {
                                await ApplicationLogger.shared.error("Failed to analyze \(url.lastPathComponent): \(error)", category: .vision)
                            }
                        }
                    }

                    // Wait for at least one task to complete before adding more
                    await group.next()
                    activeCount -= 1
                }

                // Wait for all remaining tasks
                for await _ in group {
                    // All tasks complete
                }
            }

            // Mark completion
            await MainActor.run {
                self.isAnalyzing = false
                self.analysisProgress = 1.0
                ApplicationLogger.shared.info("Vision analysis complete for \(self.totalAnalysisCount) images", category: .vision)
                self.currentAnalysisCount = 0
                self.totalAnalysisCount = 0
            }
        }
    }

    /// Pause analysis
    func pauseAnalysis() {
        // Not needed with TaskGroup approach
    }

    /// Resume analysis
    func resumeAnalysis() {
        // Not needed with TaskGroup approach
    }

    /// Cancel all pending analyses
    func cancelAnalysis() {
        // Cancel is handled by task cancellation
        Task { @MainActor in
            self.isAnalyzing = false
            self.currentAnalysisCount = 0
            self.totalAnalysisCount = 0
            self.analysisProgress = 0.0
        }
    }

    // MARK: - Private Methods

    /// Analyze image using VNSequenceRequestHandler for better resource management
    private func analyzeImageWithSequenceHandler(at url: URL, checksum: String, handler: VNSequenceRequestHandler) async throws {
        guard isEnabled else {
            throw VisionAnalyzerError.notAvailable
        }

        // Get original dimensions
        let originalDimensions = getImageDimensions(from: url)

        // Run Core Image analysis in parallel
        let coreImageTask = Task {
            try await CoreImageAnalyzer.shared.analyzeImage(at: url, checksum: checksum)
        }

        // Update UI
        await MainActor.run {
            self.currentImageName = url.lastPathComponent
        }

        // Security-scoped access is handled at the folder level in queueImagesForAnalysisWithChecksums

        // Wrap image processing in autoreleasepool for better memory management
        let (sceneResults, faceResults, textResults, animalResults) = try autoreleasepool {
            // Load image with minimal memory footprint
            // IOSurface warnings are a known iOS/macOS issue that doesn't affect functionality
            guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, [
                kCGImageSourceShouldCache: false as NSNumber,
                kCGImageSourceShouldCacheImmediately: false as NSNumber
            ] as CFDictionary) else {
                throw VisionAnalyzerError.imageLoadFailed
            }

            // Create image WITHOUT thumbnail - let Vision handle sizing
            guard let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, [
                kCGImageSourceShouldCache: false as NSNumber,
                kCGImageSourceShouldCacheImmediately: false as NSNumber
            ] as CFDictionary) else {
                throw VisionAnalyzerError.imageLoadFailed
            }

            // Prepare Vision requests
            var requests: [VNRequest] = []

            if let sceneRequest = sceneClassificationRequest {
                requests.append(sceneRequest)
            }
            if let faceRequest = faceDetectionRequest {
                requests.append(faceRequest)
            }
            if let animalRequest = objectRecognitionRequest {
                requests.append(animalRequest)
            }
            if let textRequest = textDetectionRequest {
                requests.append(textRequest)
            }

            // Perform Vision analysis using sequence handler
            try handler.perform(requests, on: cgImage)

            // Extract and return results
            return (
                sceneClassificationRequest?.results as? [VNClassificationObservation],
                faceDetectionRequest?.results as? [VNFaceObservation],
                textDetectionRequest?.results as? [VNRecognizedTextObservation],
                objectRecognitionRequest?.results as? [VNRecognizedObjectObservation]
            )
        }

        // Log results
        print("🤖 Vision Analysis for \(url.lastPathComponent):")

        if let scenes = sceneResults?.prefix(3) {
            let sceneDescriptions = scenes.map { "\($0.identifier.humanReadable) (\(Int($0.confidence * 100))%)" }
            if !sceneDescriptions.isEmpty {
                print("  📸 Scenes: \(sceneDescriptions.joined(separator: ", "))")
            }
        }

        if let faces = faceResults, !faces.isEmpty {
            print("  👤 Faces detected: \(faces.count)")
        }

        if let animals = animalResults, !animals.isEmpty {
            let animalTypes = animals.compactMap { $0.labels.first?.identifier.humanReadable }
            print("  🐾 Animals: \(animalTypes.joined(separator: ", "))")
        }

        // Wait for Core Image analysis to complete
        let coreImageResult = try? await coreImageTask.value

        // Store results
        await storeAnalysisResults(
            url: url,
            checksum: checksum,
            originalDimensions: originalDimensions,
            sceneResults: sceneResults,
            faceResults: faceResults,
            textResults: textResults,
            animalResults: animalResults,
            coreImageResult: coreImageResult
        )

        // Log completion
        ApplicationLogger.shared.info(
            "Vision analysis completed for \(url.lastPathComponent): " +
            "Scenes: \(sceneResults?.count ?? 0), " +
            "Faces: \(faceResults?.count ?? 0), " +
            "Animals: \(animalResults?.count ?? 0), " +
            "Text blocks: \(textResults?.count ?? 0)",
            category: .vision
        )
    }

    private nonisolated func calculateChecksum(for url: URL) throws -> String {
        // Security-scoped access is handled at the folder level in queueImagesForAnalysisWithChecksums

        // Simple MD5 checksum for now
        let data = try Data(contentsOf: url)
        return data.base64EncodedString().prefix(32).description
    }

    private func getImageDimensions(from url: URL) -> (width: Int, height: Int)? {
        // Security-scoped access is handled at the folder level in queueImagesForAnalysisWithChecksums

        // Get original dimensions without loading full image
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] else {
            return nil
        }

        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0

        return (width: width, height: height)
    }

    // Removed loadImage function - no longer needed since Vision handles URL directly

    private func isAlreadyAnalyzed(checksum: String) async -> Bool {
        let context = EventLogger.shared.backgroundContext

        return await context.perform {
            let request = NSFetchRequest<ImageMetadata>(entityName: "ImageMetadata")
            request.predicate = NSPredicate(format: "checksum == %@", checksum)
            request.fetchLimit = 1

            do {
                let count = try context.count(for: request)
                return count > 0
            } catch {
                Task { @MainActor in
                    ApplicationLogger.shared.error("Failed to check analysis status: \(error)", category: .vision)
                }
                return false
            }
        }
    }

    private func storeAnalysisResults(
        url: URL,
        checksum: String,
        originalDimensions: (width: Int, height: Int)?,
        sceneResults: [VNClassificationObservation]?,
        faceResults: [VNFaceObservation]?,
        textResults: [VNRecognizedTextObservation]?,
        animalResults: [VNRecognizedObjectObservation]?,
        coreImageResult: CoreImageAnalysisResult? = nil
    ) async {
        let context = EventLogger.shared.backgroundContext

        await context.perform {
            // Create metadata entity
            let metadata = NSEntityDescription.insertNewObject(forEntityName: "ImageMetadata", into: context)

            metadata.setValue(UUID(), forKey: "id")
            metadata.setValue(checksum, forKey: "checksum")
            metadata.setValue(url.path, forKey: "filePath")
            metadata.setValue(Date(), forKey: "analysisDate")
            metadata.setValue("1.0", forKey: "analysisVersion")

            // Store dimensions
            if let original = originalDimensions {
                // Analysis dimensions (Vision internally handles any downsampling)
                metadata.setValue(Int32(original.width), forKey: "imageWidth")
                metadata.setValue(Int32(original.height), forKey: "imageHeight")

                // Original dimensions
                metadata.setValue(Int32(original.width), forKey: "originalWidth")
                metadata.setValue(Int32(original.height), forKey: "originalHeight")
            } else {
                // Fallback - set all to 0 if we couldn't get dimensions
                metadata.setValue(Int32(0), forKey: "imageWidth")
                metadata.setValue(Int32(0), forKey: "imageHeight")
                metadata.setValue(Int32(0), forKey: "originalWidth")
                metadata.setValue(Int32(0), forKey: "originalHeight")
            }

            // Face count
            metadata.setValue(Int16(faceResults?.count ?? 0), forKey: "faceCount")

            // Has text
            metadata.setValue(!textResults.isNilOrEmpty, forKey: "hasText")

            // Store scene classifications
            if let scenes = sceneResults?.prefix(5) {
                for scene in scenes {
                    let sceneEntity = NSEntityDescription.insertNewObject(forEntityName: "SceneClassification", into: context)
                    sceneEntity.setValue(UUID(), forKey: "id")
                    sceneEntity.setValue(scene.identifier, forKey: "identifier")
                    sceneEntity.setValue(scene.identifier.humanReadable, forKey: "label")
                    sceneEntity.setValue(scene.confidence, forKey: "confidence")
                    sceneEntity.setValue(metadata, forKey: "imageMetadata")
                }
            }

            // Store face rectangles (privacy-aware)
            if let faces = faceResults?.prefix(100) {
                for face in faces {
                    let faceEntity = NSEntityDescription.insertNewObject(forEntityName: "FaceRectangle", into: context)
                    faceEntity.setValue(UUID(), forKey: "id")
                    faceEntity.setValue(NSStringFromRect(NSRect(x: face.boundingBox.origin.x, y: face.boundingBox.origin.y, width: face.boundingBox.size.width, height: face.boundingBox.size.height)), forKey: "boundingBox")
                    faceEntity.setValue(face.confidence, forKey: "confidence")
                    // Note: faceCaptureQuality doesn't exist, using confidence
                    faceEntity.setValue(metadata, forKey: "imageMetadata")
                }
            }

            // Store animal detections as objects
            if let animals = animalResults {
                for animal in animals {
                    let objectEntity = NSEntityDescription.insertNewObject(forEntityName: "DetectedObject", into: context)
                    objectEntity.setValue(UUID(), forKey: "id")
                    objectEntity.setValue(animal.labels.first?.identifier ?? "animal", forKey: "identifier")
                    objectEntity.setValue(animal.labels.first?.identifier.humanReadable ?? "Animal", forKey: "label")
                    objectEntity.setValue(animal.confidence, forKey: "confidence")
                    objectEntity.setValue(NSStringFromRect(NSRect(x: animal.boundingBox.origin.x, y: animal.boundingBox.origin.y, width: animal.boundingBox.size.width, height: animal.boundingBox.size.height)), forKey: "boundingBox")
                    objectEntity.setValue(metadata, forKey: "imageMetadata")
                }
            }

            // Extract and store EXIF data
            if let exifData = self.extractExifData(from: url) {
                let exifEntity = NSEntityDescription.insertNewObject(forEntityName: "ExifData", into: context)
                exifEntity.setValue(UUID(), forKey: "id")
                exifEntity.setValue(exifData.cameraModel, forKey: "cameraModel")
                exifEntity.setValue(exifData.lens, forKey: "lens")
                exifEntity.setValue(exifData.dateTaken, forKey: "dateTaken")
                exifEntity.setValue(exifData.iso, forKey: "iso")
                exifEntity.setValue(exifData.aperture, forKey: "aperture")
                exifEntity.setValue(exifData.focalLength, forKey: "focalLength")
                exifEntity.setValue(exifData.exposureTime, forKey: "exposureTime")
                exifEntity.setValue(metadata, forKey: "imageMetadata")
            }

            // Store Core Image analysis results
            if let coreImage = coreImageResult {
                // Store color analysis
                if let colorAnalysis = coreImage.colorAnalysis {
                    let colorEntity = NSEntityDescription.insertNewObject(forEntityName: "ImageColorAnalysis", into: context)
                    colorEntity.setValue(UUID(), forKey: "id")
                    colorEntity.setValue(colorAnalysis.dominantColorHex, forKey: "dominantColorHex")
                    colorEntity.setValue(colorAnalysis.colorPalette, forKey: "colorPalette")
                    colorEntity.setValue(Float(colorAnalysis.averageHue), forKey: "averageHue")
                    colorEntity.setValue(Float(colorAnalysis.averageSaturation), forKey: "averageSaturation")
                    colorEntity.setValue(Float(colorAnalysis.averageBrightness), forKey: "averageBrightness")
                    colorEntity.setValue(colorAnalysis.isMonochrome, forKey: "isMonochrome")
                    colorEntity.setValue(Int32(colorAnalysis.colorTemperature), forKey: "colorTemperature")
                    colorEntity.setValue(metadata, forKey: "imageMetadata")
                }

                // Store quality metrics
                if let qualityMetrics = coreImage.qualityMetrics {
                    let qualityEntity = NSEntityDescription.insertNewObject(forEntityName: "ImageQualityMetrics", into: context)
                    qualityEntity.setValue(UUID(), forKey: "id")
                    qualityEntity.setValue(qualityMetrics.blurScore, forKey: "blurScore")
                    qualityEntity.setValue(qualityMetrics.sharpnessScore, forKey: "sharpnessScore")
                    qualityEntity.setValue(qualityMetrics.noiseLevel, forKey: "noiseLevel")
                    qualityEntity.setValue(qualityMetrics.contrastRatio, forKey: "contrastRatio")
                    qualityEntity.setValue(qualityMetrics.exposureValue, forKey: "exposureValue")
                    qualityEntity.setValue(qualityMetrics.highlightsClipped, forKey: "highlightsClipped")
                    qualityEntity.setValue(qualityMetrics.shadowsClipped, forKey: "shadowsClipped")
                    qualityEntity.setValue(qualityMetrics.overallQuality, forKey: "overallQuality")
                    qualityEntity.setValue(metadata, forKey: "imageMetadata")
                }

                // Store histogram data
                if let histogram = coreImage.histogram {
                    let histogramEntity = NSEntityDescription.insertNewObject(forEntityName: "ImageHistogram", into: context)
                    histogramEntity.setValue(UUID(), forKey: "id")
                    histogramEntity.setValue(histogram.redChannel, forKey: "redChannel")
                    histogramEntity.setValue(histogram.greenChannel, forKey: "greenChannel")
                    histogramEntity.setValue(histogram.blueChannel, forKey: "blueChannel")
                    histogramEntity.setValue(histogram.luminanceChannel, forKey: "luminanceChannel")
                    histogramEntity.setValue(Int16(histogram.peakRed), forKey: "peakRed")
                    histogramEntity.setValue(Int16(histogram.peakGreen), forKey: "peakGreen")
                    histogramEntity.setValue(Int16(histogram.peakBlue), forKey: "peakBlue")
                    histogramEntity.setValue(metadata, forKey: "imageMetadata")
                }

                // Store enhanced EXIF from Core Image (if Vision didn't get it)
                if self.extractExifData(from: url) == nil, let exifData = coreImage.exifData {
                    let exifEntity = NSEntityDescription.insertNewObject(forEntityName: "ExifData", into: context)
                    exifEntity.setValue(UUID(), forKey: "id")
                    exifEntity.setValue(exifData.cameraModel, forKey: "cameraModel")
                    exifEntity.setValue(exifData.lens, forKey: "lens")
                    exifEntity.setValue(exifData.dateTaken, forKey: "dateTaken")
                    exifEntity.setValue(Int32(exifData.iso ?? 0), forKey: "iso")
                    exifEntity.setValue(exifData.aperture, forKey: "aperture")
                    exifEntity.setValue(exifData.focalLength, forKey: "focalLength")
                    exifEntity.setValue(exifData.exposureTime, forKey: "exposureTime")
                    exifEntity.setValue(exifData.latitude, forKey: "latitude")
                    exifEntity.setValue(exifData.longitude, forKey: "longitude")
                    exifEntity.setValue(metadata, forKey: "imageMetadata")
                }
            }

            // Save context
            do {
                try context.save()
                Task { @MainActor in
                    ApplicationLogger.shared.debug("Stored analysis results for \(url.lastPathComponent)", category: .vision)
                }
            } catch {
                Task { @MainActor in
                    ApplicationLogger.shared.error("Failed to save analysis results: \(error)", category: .vision)
                }
            }
        }
    }

    private nonisolated func extractExifData(from url: URL) -> (
        cameraModel: String?,
        lens: String?,
        dateTaken: Date?,
        iso: Int32,
        aperture: Float,
        focalLength: Float,
        exposureTime: String?
    )? {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any] else {
            return nil
        }

        let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any]

        return (
            cameraModel: tiff?[kCGImagePropertyTIFFModel as String] as? String,
            lens: exif?[kCGImagePropertyExifLensModel as String] as? String,
            dateTaken: exif?[kCGImagePropertyExifDateTimeOriginal as String] as? Date,
            iso: exif?[kCGImagePropertyExifISOSpeedRatings as String] as? Int32 ?? 0,
            aperture: exif?[kCGImagePropertyExifFNumber as String] as? Float ?? 0,
            focalLength: exif?[kCGImagePropertyExifFocalLength as String] as? Float ?? 0,
            exposureTime: exif?[kCGImagePropertyExifExposureTime as String] as? String
        )
    }
}

// MARK: - Errors
enum VisionAnalyzerError: LocalizedError {
    case notAvailable
    case imageLoadFailed
    case analysisFailed(Error)

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Vision Framework requires Apple Silicon Mac"
        case .imageLoadFailed:
            return "Failed to load image for analysis"
        case .analysisFailed(let error):
            return "Vision analysis failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - String Extension
private extension String {
    /// Convert Vision identifier to human-readable label
    var humanReadable: String {
        return self
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: ".")
            .last?
            .capitalized ?? self
    }
}

// MARK: - Collection Extension
private extension Optional where Wrapped: Collection {
    var isNilOrEmpty: Bool {
        return self?.isEmpty ?? true
    }
}
