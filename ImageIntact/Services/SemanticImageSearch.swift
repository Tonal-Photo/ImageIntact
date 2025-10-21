//
//  SemanticImageSearch.swift
//  ImageIntact
//
//  Semantic search for images using Foundation Models framework (macOS 26+)
//

import Foundation
import CoreData
import FoundationModels

// MARK: - Generable Structs for Structured Output

/// Ranked search results from Foundation Models
@available(macOS 26, *)
@Generable
struct ImageRankings {
    @Guide(description: "List of images ranked by relevance to the search query, with most relevant first")
    let rankedImages: [RankedImage]
}

/// A single ranked image result
@available(macOS 26, *)
@Generable
struct RankedImage {
    @Guide(description: "The index of the image in the provided list (0-based)")
    let index: Int

    @Guide(description: "Confidence score from 0.0 to 1.0 indicating how well this image matches the query")
    let confidence: Double
}

// MARK: - Semantic Image Search

/// Provides intelligent semantic search over image metadata using Apple's Foundation Models
/// Requires macOS 26 (Tahoe) or later
@available(macOS 26, *)
@MainActor
class SemanticImageSearch: ObservableObject {
    static let shared = SemanticImageSearch()

    private var languageSession: LanguageModelSession?
    @Published var isReady = false

    /// Check if Foundation Models is available on this system
    static var isAvailable: Bool {
        if #available(macOS 26, *) {
            return true
        }
        return false
    }

    private init() {
        setupLanguageModel()
    }

    private func setupLanguageModel() {
        Task { @MainActor in
            // Create session with instructions for image search
            let instructions = """
            You are a semantic search engine for photographs and images.

            You will be given:
            1. A natural language search query from the user
            2. A numbered list of images with their metadata (scenes, objects, colors, text, EXIF data)

            Your task is to rank the images by relevance to the query, considering semantic similarity.

            Examples of semantic understanding:
            - "sunset" → orange/pink/red colors, evening scenes, horizon, sky
            - "wedding" → celebration, people, cake, indoor/outdoor events, formal attire
            - "nature" → outdoor, landscape, trees, mountains, water, wildlife
            - "beach" → sand, ocean, water, coastal, vacation
            - "portraits" → people, faces, close-up shots
            - "food" → meals, restaurants, cooking, dining

            Return the top 20 most relevant images with confidence scores.
            If an image has no relevance to the query, don't include it in results.
            """

            self.languageSession = LanguageModelSession(instructions: instructions)
            self.isReady = true
            print("✅ Foundation Models initialized for semantic image search")
        }
    }

    /// Perform semantic search over image metadata
    func search(query: String) async -> [ImageSearchResult] {
        guard let session = languageSession else {
            print("❌ Foundation Models session not initialized")
            return []
        }

        // Fetch all image metadata from Core Data
        let allMetadata = await fetchAllImageMetadata()

        guard !allMetadata.isEmpty else {
            print("⚠️ No images in database to search")
            return []
        }

        print("🔍 Searching \(allMetadata.count) images for: '\(query)'")

        // Pre-filter with keyword matching to reduce candidates
        // This avoids exceeding the 4096 token context window
        let candidates = preFilterCandidates(query: query, metadata: allMetadata, maxCandidates: 50)

        if candidates.isEmpty {
            print("⚠️ No candidates matched keyword pre-filter")
            return []
        }

        print("📋 Pre-filtered to \(candidates.count) candidate images")

        // Convert metadata to searchable documents
        let documents = candidates.enumerated().map { index, metadata in
            "[\(index)] \(createSearchableDocument(from: metadata))"
        }.joined(separator: "\n\n")

        do {
            // Build the search prompt
            let searchPrompt = """
            Search Query: "\(query)"

            Images to search:
            \(documents)

            Rank these images by relevance to the query.
            """

            // Use Foundation Models to get structured rankings
            let response = try await session.respond(
                to: searchPrompt,
                generating: ImageRankings.self
            )

            // Extract the generated value from the response
            let rankings = response.content

            print("✅ Foundation Models returned \(rankings.rankedImages.count) ranked results")

            // Convert to ImageSearchResult objects (using candidates array)
            let results = rankings.rankedImages.compactMap { rankedImage -> ImageSearchResult? in
                guard rankedImage.index >= 0 && rankedImage.index < candidates.count else {
                    print("⚠️ Invalid index \(rankedImage.index) returned by model")
                    return nil
                }

                let metadata = candidates[rankedImage.index]
                return createSearchResult(from: metadata, confidence: rankedImage.confidence)
            }

            return results

        } catch {
            print("❌ Semantic search failed: \(error)")
            return []
        }
    }

    /// Pre-filter candidates using keyword matching to avoid context window overflow
    private func preFilterCandidates(query: String, metadata: [NSManagedObject], maxCandidates: Int) -> [NSManagedObject] {
        let queryTerms = query.lowercased().components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }

        // Score each image by keyword matches
        var scoredMetadata: [(metadata: NSManagedObject, score: Int)] = []

        for item in metadata {
            let document = createSearchableDocument(from: item).lowercased()
            var score = 0

            for term in queryTerms {
                if document.contains(term) {
                    score += 1
                }
            }

            if score > 0 {
                scoredMetadata.append((metadata: item, score: score))
            }
        }

        // Sort by score (best matches first) and take top candidates
        scoredMetadata.sort { $0.score > $1.score }

        return scoredMetadata.prefix(maxCandidates).map { $0.metadata }
    }

    /// Fetch all image metadata from Core Data
    private func fetchAllImageMetadata() async -> [NSManagedObject] {
        let context = EventLogger.shared.backgroundContext

        return await context.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: "ImageMetadata")
            request.fetchLimit = 500  // Limit for performance

            do {
                return try context.fetch(request)
            } catch {
                print("Failed to fetch metadata: \(error)")
                return []
            }
        }
    }

    /// Create a searchable text document from image metadata
    private func createSearchableDocument(from metadata: NSManagedObject) -> String {
        var parts: [String] = []

        // Add filename (extract from filePath)
        if let filePath = metadata.value(forKey: "filePath") as? String {
            let filename = (filePath as NSString).lastPathComponent
            parts.append("File: \(filename)")
        }

        // Add scene classifications
        if let scenes = metadata.value(forKey: "sceneClassifications") as? Set<NSManagedObject> {
            let sceneList = scenes.compactMap { scene in
                (scene.value(forKey: "identifier") as? String)?.replacingOccurrences(of: "_", with: " ")
            }
            if !sceneList.isEmpty {
                parts.append("Scenes: \(sceneList.joined(separator: ", "))")
            }
        }

        // Add detected objects
        if let objects = metadata.value(forKey: "detectedObjects") as? Set<NSManagedObject> {
            let objectList = objects.compactMap { obj in
                obj.value(forKey: "label") as? String
            }
            if !objectList.isEmpty {
                parts.append("Objects: \(objectList.joined(separator: ", "))")
            }
        }

        // Add extracted text from textRegions
        if let hasText = metadata.value(forKey: "hasText") as? Bool, hasText {
            if let textRegions = metadata.value(forKey: "textRegions") as? [[String: Any]] {
                let textStrings = textRegions.compactMap { $0["text"] as? String }
                if !textStrings.isEmpty {
                    let combinedText = textStrings.joined(separator: " ")
                    parts.append("Text: \(combinedText)")
                }
            }
        }

        // Add dominant colors from colorAnalysis
        if let colorAnalysis = metadata.value(forKey: "colorAnalysis") as? NSManagedObject {
            if let colorPalette = colorAnalysis.value(forKey: "colorPalette") as? [String], !colorPalette.isEmpty {
                parts.append("Colors: \(colorPalette.joined(separator: ", "))")
            }
        }

        // Add EXIF data (camera, location if available)
        if let exifData = metadata.value(forKey: "exifData") as? NSManagedObject {
            var exifParts: [String] = []

            if let camera = exifData.value(forKey: "cameraModel") as? String {
                exifParts.append("Camera: \(camera)")
            }

            if let date = exifData.value(forKey: "dateTaken") as? Date {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                exifParts.append("Date: \(formatter.string(from: date))")
            }

            if !exifParts.isEmpty {
                parts.append(exifParts.joined(separator: ", "))
            }
        }

        return parts.joined(separator: ". ")
    }


    /// Create search result from metadata
    private func createSearchResult(from metadata: NSManagedObject, confidence: Double) -> ImageSearchResult {
        let id = (metadata.value(forKey: "id") as? UUID) ?? UUID()
        let filePath = (metadata.value(forKey: "filePath") as? String) ?? ""
        let filename = (filePath as NSString).lastPathComponent
        let checksum = (metadata.value(forKey: "checksum") as? String) ?? ""
        let analysisDate = (metadata.value(forKey: "analysisDate") as? Date) ?? Date()

        // Extract scenes
        var matchedScenes: [String] = []
        if let scenes = metadata.value(forKey: "sceneClassifications") as? Set<NSManagedObject> {
            matchedScenes = scenes.compactMap { scene in
                (scene.value(forKey: "identifier") as? String)?.replacingOccurrences(of: "_", with: " ")
            }
        }

        // Extract objects
        var matchedObjects: [String] = []
        if let objects = metadata.value(forKey: "detectedObjects") as? Set<NSManagedObject> {
            matchedObjects = objects.compactMap { obj in
                obj.value(forKey: "label") as? String
            }
        }

        // Extract text from textRegions
        var extractedText: String? = nil
        if let hasText = metadata.value(forKey: "hasText") as? Bool, hasText {
            if let textRegions = metadata.value(forKey: "textRegions") as? [[String: Any]] {
                let textStrings = textRegions.compactMap { $0["text"] as? String }
                if !textStrings.isEmpty {
                    extractedText = textStrings.joined(separator: " ")
                }
            }
        }

        // Extract colors from colorAnalysis relationship
        var dominantColors: [String] = []
        if let colorAnalysis = metadata.value(forKey: "colorAnalysis") as? NSManagedObject {
            if let colorPalette = colorAnalysis.value(forKey: "colorPalette") as? [String] {
                dominantColors = colorPalette
            }
        }

        return ImageSearchResult(
            id: id,
            filename: filename,
            filePath: filePath,
            checksum: checksum,
            analysisDate: analysisDate,
            matchedScenes: matchedScenes,
            matchedObjects: matchedObjects,
            extractedText: extractedText,
            dominantColors: dominantColors,
            confidence: confidence
        )
    }

}
