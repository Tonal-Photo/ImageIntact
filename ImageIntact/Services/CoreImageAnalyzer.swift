//
//  CoreImageAnalyzer.swift
//  ImageIntact
//
//  Core Image analysis for extracting colors, quality metrics, and histograms
//

import Foundation
import CoreImage
import CoreData
import AppKit
import Metal

/// Analyzes images using Core Image for technical properties and visual metrics
@MainActor
class CoreImageAnalyzer: ObservableObject {
    static let shared = CoreImageAnalyzer()

    // MARK: - Published Properties
    @Published var isProcessing = false
    @Published var currentAnalysisCount = 0
    @Published var totalAnalysisCount = 0
    @Published var lastError: Error?

    // MARK: - Private Properties
    private let context: CIContext
    private var analysisQueue = DispatchQueue(label: "com.imageintact.coreimage", qos: .userInitiated)
    private var container: NSPersistentContainer {
        EventLogger.shared.container
    }

    // MARK: - Configuration
    private let maxConcurrentAnalyses: Int

    // MARK: - Initialization
    private init() {
        // Create CIContext with GPU acceleration if available
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            context = CIContext(mtlDevice: metalDevice)
            logInfo("Core Image using Metal GPU acceleration")
        } else {
            context = CIContext(options: [.useSoftwareRenderer: false])
            logInfo("Core Image using CPU rendering")
        }

        // Set concurrent limit based on system capabilities
        let capabilities = SystemCapabilities.shared
        if capabilities.hasNeuralEngine {
            // Use same limits as Vision Framework for consistency
            switch capabilities.processorGeneration {
            case .m1: maxConcurrentAnalyses = 2
            case .m2: maxConcurrentAnalyses = 3
            case .m3: maxConcurrentAnalyses = 4
            case .m4: maxConcurrentAnalyses = 5
            case .m5: maxConcurrentAnalyses = 6
            case .unknown: maxConcurrentAnalyses = 2
            }
        } else {
            // Intel Macs: be conservative
            maxConcurrentAnalyses = 2
        }

        logInfo("Core Image analyzer initialized with max \(maxConcurrentAnalyses) concurrent analyses")
    }

    // MARK: - Public Methods

    /// Analyze an image and store Core Image metadata
    func analyzeImage(at url: URL, checksum: String) async throws -> CoreImageAnalysisResult {
        guard let ciImage = CIImage(contentsOf: url) else {
            throw CoreImageError.failedToLoadImage(url)
        }

        // Run analysis on background queue
        return try await withCheckedThrowingContinuation { continuation in
            analysisQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: CoreImageError.analyzerDeallocated)
                    return
                }

                do {
                    var result = CoreImageAnalysisResult(checksum: checksum)

                    // Extract all analyses synchronously on background queue
                    result.colorAnalysis = try self.extractColorAnalysis(from: ciImage)
                    result.qualityMetrics = try self.extractQualityMetrics(from: ciImage, at: url)
                    result.histogram = try self.extractHistogram(from: ciImage)
                    result.exifData = self.extractExifData(from: ciImage)

                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Color Analysis

    nonisolated private func extractColorAnalysis(from image: CIImage) throws -> ColorAnalysis {
        var analysis = ColorAnalysis()

        // Calculate average color
        let averageFilter = CIFilter(name: "CIAreaAverage")!
        averageFilter.setValue(image, forKey: kCIInputImageKey)
        averageFilter.setValue(CIVector(cgRect: image.extent), forKey: "inputExtent")

        if let outputImage = averageFilter.outputImage {
            var bitmap = [UInt8](repeating: 0, count: 4)
            context.render(outputImage, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())

            let color = NSColor(red: CGFloat(bitmap[0])/255.0, green: CGFloat(bitmap[1])/255.0, blue: CGFloat(bitmap[2])/255.0, alpha: 1.0)
            analysis.dominantColorHex = color.hexString
            analysis.averageHue = color.hueComponent
            analysis.averageSaturation = color.saturationComponent
            analysis.averageBrightness = color.brightnessComponent
        }

        // Extract color palette using histogram
        analysis.colorPalette = try extractColorPalette(from: image)

        // Determine if monochrome
        analysis.isMonochrome = isImageMonochrome(image)

        // Estimate color temperature
        analysis.colorTemperature = estimateColorTemperature(from: image)

        return analysis
    }

    // MARK: - Quality Metrics

    nonisolated private func extractQualityMetrics(from image: CIImage, at url: URL) throws -> QualityMetrics {
        var metrics = QualityMetrics()

        // Blur detection using Laplacian
        metrics.blurScore = calculateBlurScore(from: image)

        // Sharpness using edge detection
        metrics.sharpnessScore = calculateSharpness(from: image)

        // Noise estimation
        metrics.noiseLevel = estimateNoise(from: image)

        // Contrast calculation
        metrics.contrastRatio = calculateContrast(from: image)

        // Exposure analysis
        let exposure = analyzeExposure(from: image)
        metrics.exposureValue = exposure.value
        metrics.highlightsClipped = exposure.highlightsClipped
        metrics.shadowsClipped = exposure.shadowsClipped

        // Overall quality assessment
        metrics.overallQuality = assessOverallQuality(metrics)

        return metrics
    }

    // MARK: - Histogram Extraction

    nonisolated private func extractHistogram(from image: CIImage) throws -> HistogramData {
        var histogram = HistogramData()

        // Create histogram filter
        let histogramFilter = CIFilter(name: "CIAreaHistogram")!
        histogramFilter.setValue(image, forKey: kCIInputImageKey)
        histogramFilter.setValue(CIVector(cgRect: image.extent), forKey: "inputExtent")
        histogramFilter.setValue(256, forKey: "inputCount")
        histogramFilter.setValue(1.0, forKey: "inputScale")

        guard let histogramImage = histogramFilter.outputImage else {
            throw CoreImageError.histogramGenerationFailed
        }

        // Extract histogram data for each channel
        let histogramData = extractHistogramData(from: histogramImage)
        histogram.redChannel = histogramData.red
        histogram.greenChannel = histogramData.green
        histogram.blueChannel = histogramData.blue
        histogram.luminanceChannel = histogramData.luminance

        // Find peaks
        histogram.peakRed = findPeak(in: histogramData.red)
        histogram.peakGreen = findPeak(in: histogramData.green)
        histogram.peakBlue = findPeak(in: histogramData.blue)

        return histogram
    }

    // MARK: - EXIF Data

    nonisolated private func extractExifData(from image: CIImage) -> EnhancedExifData? {
        let properties = image.properties
        guard !properties.isEmpty else { return nil }

        var exifData = EnhancedExifData()

        // Extract EXIF dictionary
        if let exif = properties["{Exif}"] as? [String: Any] {
            exifData.aperture = exif["FNumber"] as? Float
            exifData.exposureTime = exif["ExposureTime"] as? String
            exifData.iso = exif["ISOSpeedRatings"] as? Int
            exifData.focalLength = exif["FocalLength"] as? Float

            // Date taken
            if let dateString = exif["DateTimeOriginal"] as? String {
                exifData.dateTaken = parseExifDate(dateString)
            }
        }

        // Extract TIFF dictionary
        if let tiff = properties["{TIFF}"] as? [String: Any] {
            exifData.cameraModel = tiff["Model"] as? String
            exifData.lens = tiff["LensModel"] as? String
        }

        // Extract GPS data
        if let gps = properties["{GPS}"] as? [String: Any] {
            exifData.latitude = gps["Latitude"] as? Double
            exifData.longitude = gps["Longitude"] as? Double
        }

        return exifData
    }

    // MARK: - Helper Methods

    nonisolated private func extractColorPalette(from image: CIImage, count: Int = 5) throws -> [String] {
        // Simplified color palette extraction
        // In production, would use k-means clustering or similar
        var colors: [String] = []

        // Sample points across the image
        let sampleSize = 10
        let width = Int(image.extent.width)
        let height = Int(image.extent.height)

        for x in stride(from: 0, to: width, by: width / sampleSize) {
            for y in stride(from: 0, to: height, by: height / sampleSize) {
                if let color = getPixelColor(at: CGPoint(x: x, y: y), in: image) {
                    let hex = color.hexString
                    if !colors.contains(hex) {
                        colors.append(hex)
                    }
                    if colors.count >= count { break }
                }
            }
            if colors.count >= count { break }
        }

        return colors
    }

    nonisolated private func getPixelColor(at point: CGPoint, in image: CIImage) -> NSColor? {
        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(image, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: point.x, y: point.y, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        return NSColor(red: CGFloat(bitmap[0])/255.0, green: CGFloat(bitmap[1])/255.0, blue: CGFloat(bitmap[2])/255.0, alpha: 1.0)
    }

    nonisolated private func isImageMonochrome(_ image: CIImage) -> Bool {
        // Check if image has very low saturation
        let avgSaturation = calculateAverageSaturation(from: image)
        return avgSaturation < 0.1
    }

    nonisolated private func calculateAverageSaturation(from image: CIImage) -> Float {
        // Simplified calculation
        return 0.5 // Placeholder
    }

    nonisolated private func estimateColorTemperature(from image: CIImage) -> Int {
        // Estimate based on blue/red ratio
        // Placeholder: would need proper color temperature calculation
        return 5500 // Daylight
    }

    nonisolated private func calculateBlurScore(from image: CIImage) -> Float {
        // Use Laplacian filter to detect edges
        // Less edges = more blur
        guard let laplacian = CIFilter(name: "CIConvolution3X3") else { return 0.0 }
        laplacian.setValue(image, forKey: kCIInputImageKey)
        laplacian.setValue(CIVector(values: [0, -1, 0, -1, 4, -1, 0, -1, 0], count: 9), forKey: "inputWeights")

        // Calculate variance of the filtered image
        // Higher variance = sharper image
        return 0.5 // Placeholder
    }

    nonisolated private func calculateSharpness(from image: CIImage) -> Float {
        // Edge detection strength
        return 0.5 // Placeholder
    }

    nonisolated private func estimateNoise(from image: CIImage) -> Float {
        // Noise estimation using high-pass filter
        return 0.1 // Placeholder
    }

    nonisolated private func calculateContrast(from image: CIImage) -> Float {
        // Calculate standard deviation of luminance
        return 1.0 // Placeholder
    }

    nonisolated private func analyzeExposure(from image: CIImage) -> (value: Float, highlightsClipped: Bool, shadowsClipped: Bool) {
        // Analyze histogram for clipping
        return (value: 0.0, highlightsClipped: false, shadowsClipped: false) // Placeholder
    }

    nonisolated private func assessOverallQuality(_ metrics: QualityMetrics) -> String {
        let score = (metrics.sharpnessScore * 0.4) + ((1.0 - metrics.blurScore) * 0.3) + ((1.0 - metrics.noiseLevel) * 0.3)

        if score > 0.8 { return "Excellent" }
        if score > 0.6 { return "Good" }
        if score > 0.4 { return "Fair" }
        return "Poor"
    }

    nonisolated private func extractHistogramData(from histogramImage: CIImage) -> (red: Data, green: Data, blue: Data, luminance: Data) {
        // Extract raw histogram data
        // Placeholder implementation
        let emptyData = Data()
        return (emptyData, emptyData, emptyData, emptyData)
    }

    nonisolated private func findPeak(in data: Data) -> Int {
        // Find the bin with maximum count
        return 128 // Placeholder
    }

    nonisolated private func parseExifDate(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: dateString)
    }
}

// MARK: - Data Structures

struct CoreImageAnalysisResult {
    let checksum: String
    var colorAnalysis: ColorAnalysis?
    var qualityMetrics: QualityMetrics?
    var histogram: HistogramData?
    var exifData: EnhancedExifData?
}

struct ColorAnalysis {
    var dominantColorHex: String?
    var colorPalette: [String] = []
    var averageHue: CGFloat = 0
    var averageSaturation: CGFloat = 0
    var averageBrightness: CGFloat = 0
    var isMonochrome: Bool = false
    var colorTemperature: Int = 5500
}

struct QualityMetrics {
    var blurScore: Float = 0
    var sharpnessScore: Float = 0
    var noiseLevel: Float = 0
    var contrastRatio: Float = 1.0
    var exposureValue: Float = 0
    var highlightsClipped: Bool = false
    var shadowsClipped: Bool = false
    var overallQuality: String = "Unknown"
}

struct HistogramData {
    var redChannel: Data = Data()
    var greenChannel: Data = Data()
    var blueChannel: Data = Data()
    var luminanceChannel: Data = Data()
    var peakRed: Int = 0
    var peakGreen: Int = 0
    var peakBlue: Int = 0
}

struct EnhancedExifData {
    var cameraModel: String?
    var lens: String?
    var aperture: Float?
    var exposureTime: String?
    var iso: Int?
    var focalLength: Float?
    var dateTaken: Date?
    var latitude: Double?
    var longitude: Double?
}

// MARK: - Errors

enum CoreImageError: LocalizedError {
    case failedToLoadImage(URL)
    case analyzerDeallocated
    case histogramGenerationFailed

    var errorDescription: String? {
        switch self {
        case .failedToLoadImage(let url):
            return "Failed to load image at \(url.path)"
        case .analyzerDeallocated:
            return "Core Image analyzer was deallocated during analysis"
        case .histogramGenerationFailed:
            return "Failed to generate histogram data"
        }
    }
}

// MARK: - Color Extensions

extension NSColor {
    var hexString: String {
        let red = Int(redComponent * 255)
        let green = Int(greenComponent * 255)
        let blue = Int(blueComponent * 255)
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    var hueComponent: CGFloat {
        var hue: CGFloat = 0
        getHue(&hue, saturation: nil, brightness: nil, alpha: nil)
        return hue
    }

    var saturationComponent: CGFloat {
        var saturation: CGFloat = 0
        getHue(nil, saturation: &saturation, brightness: nil, alpha: nil)
        return saturation
    }

    var brightnessComponent: CGFloat {
        var brightness: CGFloat = 0
        getHue(nil, saturation: nil, brightness: &brightness, alpha: nil)
        return brightness
    }
}