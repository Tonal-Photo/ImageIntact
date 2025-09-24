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
    private let analysisQueue: OperationQueue
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

        // Configure analysis queue
        self.analysisQueue = OperationQueue()
        self.analysisQueue.name = "com.imageintact.vision.analysis"
        self.analysisQueue.qualityOfService = .utility
        self.analysisQueue.maxConcurrentOperationCount = maxConcurrentAnalyses
    }

    // MARK: - CPU Adaptive Limits
    private static func getConcurrentLimit(for generation: SystemCapabilities.ProcessorGeneration) -> Int {
        switch generation {
        case .m1:
            return 2
        case .m2:
            return 3
        case .m3:
            return 4
        case .m4:
            return 6
        case .unknown:
            return 2 // Conservative default
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

        // Check if already analyzed
        if await isAlreadyAnalyzed(checksum: checksum) {
            ApplicationLogger.shared.debug("Skipping already analyzed image: \(url.lastPathComponent)", category: .vision)
            return
        }

        // Update UI
        await MainActor.run {
            self.currentImageName = url.lastPathComponent
            self.currentAnalysisCount += 1
        }

        // Load image
        guard let image = loadImage(from: url) else {
            throw VisionAnalyzerError.imageLoadFailed
        }

        // Create Vision handler
        let handler = VNImageRequestHandler(ciImage: image, options: [:])

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

        // Perform analysis
        do {
            try handler.perform(requests)
        } catch {
            ApplicationLogger.shared.error("Vision analysis failed for \(url.lastPathComponent): \(error)", category: .vision)
            throw VisionAnalyzerError.analysisFailed(error)
        }

        // Process and store results
        await storeAnalysisResults(
            url: url,
            checksum: checksum,
            image: image,
            sceneResults: sceneClassificationRequest?.results as? [VNClassificationObservation],
            faceResults: faceDetectionRequest?.results as? [VNFaceObservation],
            textResults: textDetectionRequest?.results as? [VNRecognizedTextObservation],
            animalResults: objectRecognitionRequest?.results as? [VNRecognizedObjectObservation]
        )
    }

    /// Queue multiple images for analysis
    func queueImagesForAnalysis(_ urls: [URL]) {
        guard isEnabled else { return }

        Task { @MainActor in
            self.totalAnalysisCount = urls.count
            self.currentAnalysisCount = 0
            self.isAnalyzing = true
            self.analysisProgress = 0.0
        }

        for url in urls {
            analysisQueue.addOperation {
                Task {
                    do {
                        // Calculate checksum
                        let checksum = try self.calculateChecksum(for: url)

                        // Analyze
                        try await self.analyzeImage(at: url, checksum: checksum)

                        // Update progress
                        await MainActor.run {
                            self.analysisProgress = Double(self.currentAnalysisCount) / Double(self.totalAnalysisCount)
                        }
                    } catch {
                        ApplicationLogger.shared.error("Failed to analyze \(url.lastPathComponent): \(error)", category: .vision)
                    }
                }
            }
        }

        // Mark completion when all done
        analysisQueue.addBarrierBlock {
            Task { @MainActor in
                self.isAnalyzing = false
                self.analysisProgress = 1.0
                ApplicationLogger.shared.info("Vision analysis complete for \(self.totalAnalysisCount) images", category: .vision)
            }
        }
    }

    /// Pause analysis
    func pauseAnalysis() {
        analysisQueue.isSuspended = true
    }

    /// Resume analysis
    func resumeAnalysis() {
        analysisQueue.isSuspended = false
    }

    /// Cancel all pending analyses
    func cancelAnalysis() {
        analysisQueue.cancelAllOperations()
        Task { @MainActor in
            self.isAnalyzing = false
            self.currentAnalysisCount = 0
            self.totalAnalysisCount = 0
            self.analysisProgress = 0.0
        }
    }

    // MARK: - Private Methods

    private func calculateChecksum(for url: URL) throws -> String {
        // Simple MD5 checksum for now
        let data = try Data(contentsOf: url)
        return data.base64EncodedString().prefix(32).description
    }

    private func loadImage(from url: URL) -> CIImage? {
        // Load and downsample image for analysis
        let maxDimension: CGFloat = 2048

        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            return nil
        }

        return CIImage(cgImage: cgImage)
    }

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
                ApplicationLogger.shared.error("Failed to check analysis status: \(error)", category: .vision)
                return false
            }
        }
    }

    private func storeAnalysisResults(
        url: URL,
        checksum: String,
        image: CIImage,
        sceneResults: [VNClassificationObservation]?,
        faceResults: [VNFaceObservation]?,
        textResults: [VNRecognizedTextObservation]?,
        animalResults: [VNRecognizedObjectObservation]?
    ) async {
        let context = EventLogger.shared.backgroundContext

        await context.perform {
            // Create metadata entity
            let metadata = NSEntityDescription.insertNewObject(forEntityName: "ImageMetadata", into: context) as! NSManagedObject

            metadata.setValue(UUID(), forKey: "id")
            metadata.setValue(checksum, forKey: "checksum")
            metadata.setValue(url.path, forKey: "filePath")
            metadata.setValue(Date(), forKey: "analysisDate")
            metadata.setValue("1.0", forKey: "analysisVersion")

            // Image dimensions
            metadata.setValue(Int32(image.extent.width), forKey: "imageWidth")
            metadata.setValue(Int32(image.extent.height), forKey: "imageHeight")

            // Face count
            metadata.setValue(Int16(faceResults?.count ?? 0), forKey: "faceCount")

            // Has text
            metadata.setValue(!textResults.isNilOrEmpty, forKey: "hasText")

            // Store scene classifications
            if let scenes = sceneResults?.prefix(5) {
                for scene in scenes {
                    let sceneEntity = NSEntityDescription.insertNewObject(forEntityName: "SceneClassification", into: context) as! NSManagedObject
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
                    let faceEntity = NSEntityDescription.insertNewObject(forEntityName: "FaceRectangle", into: context) as! NSManagedObject
                    faceEntity.setValue(UUID(), forKey: "id")
                    faceEntity.setValue(NSStringFromRect(NSRect(x: face.boundingBox.origin.x, y: face.boundingBox.origin.y, width: face.boundingBox.size.width, height: face.boundingBox.size.height)), forKey: "boundingBox")
                    faceEntity.setValue(face.confidence ?? 0, forKey: "confidence")
                    // Note: faceCaptureQuality doesn't exist, using confidence
                    faceEntity.setValue(metadata, forKey: "imageMetadata")
                }
            }

            // Store animal detections as objects
            if let animals = animalResults {
                for animal in animals {
                    let objectEntity = NSEntityDescription.insertNewObject(forEntityName: "DetectedObject", into: context) as! NSManagedObject
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
                let exifEntity = NSEntityDescription.insertNewObject(forEntityName: "ExifData", into: context) as! NSManagedObject
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

            // Save context
            do {
                try context.save()
                ApplicationLogger.shared.debug("Stored analysis results for \(url.lastPathComponent)", category: .vision)
            } catch {
                ApplicationLogger.shared.error("Failed to save analysis results: \(error)", category: .vision)
            }
        }
    }

    private func extractExifData(from url: URL) -> (
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