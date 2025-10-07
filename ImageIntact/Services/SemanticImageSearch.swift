//
//  SemanticImageSearch.swift
//  ImageIntact
//
//  Semantic search for images using Foundation Models framework (macOS 26)
//

import Foundation
import CoreData
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Provides intelligent semantic search over image metadata using Apple's Foundation Models
@MainActor
class SemanticImageSearch: ObservableObject {
    static let shared = SemanticImageSearch()

    #if canImport(FoundationModels)
    private var languageSession: LanguageModelSession?
    #endif

    private init() {
        setupLanguageModel()
    }

    private func setupLanguageModel() {
        #if canImport(FoundationModels)
        Task {
            do {
                // Initialize the language model session
                // The model runs on-device for privacy
                let config = LanguageModelConfiguration(
                    modelType: .general,  // Use general-purpose model for semantic understanding
                    temperature: 0.3      // Lower temperature for more focused results
                )

                // Create session with instructions for image search
                self.languageSession = try await LanguageModelSession(
                    configuration: config,
                    systemPrompt: """
                    You are a semantic search engine for images. Given a natural language query and \
                    a list of image descriptions (including scenes, objects, text, colors, and metadata), \
                    rank the images by relevance to the query.

                    Consider semantic similarity, not just exact matches. For example:
                    - "sunset" relates to orange/pink colors, evening, horizon
                    - "party" relates to celebration, people, cake, indoor events
                    - "nature" relates to outdoor, landscape, trees, mountains, water

                    Return results as a ranked list with confidence scores.
                    """
                )

                print("✅ Foundation Models initialized for semantic search")
            } catch {
                print("❌ Failed to initialize Foundation Models: \(error)")
            }
        }
        #else
        print("⚠️ Foundation Models not available - using fallback search")
        #endif
    }

    /// Perform semantic search over image metadata
    func search(query: String) async -> [ImageSearchResult] {
        #if canImport(FoundationModels)
        guard let session = languageSession else {
            print("Language model not initialized")
            return await fallbackSearch(query: query)
        }

        // Fetch all image metadata from Core Data
        let allMetadata = await fetchAllImageMetadata()

        guard !allMetadata.isEmpty else {
            print("No images to search")
            return []
        }

        // Convert metadata to searchable documents
        let documents = allMetadata.map { metadata in
            createSearchableDocument(from: metadata)
        }

        do {
            // Use Foundation Models to rank documents by relevance
            let prompt = """
            Query: "\(query)"

            Images to search:
            \(documents.enumerated().map { "[\($0.offset)] \($0.element)" }.joined(separator: "\n"))

            Rank the images by relevance to the query. Return the indices of the top 10 most relevant images \
            in order, with confidence scores (0-1). Format: [index]:[score]
            Example: 3:0.95,1:0.82,5:0.75
            """

            let response = try await session.generateResponse(prompt: prompt)

            // Parse the response to get ranked results
            let rankings = parseRankings(response, count: allMetadata.count)

            // Convert to ImageSearchResult objects
            return rankings.compactMap { ranking in
                guard ranking.index < allMetadata.count else { return nil }
                let metadata = allMetadata[ranking.index]
                return createSearchResult(from: metadata, confidence: ranking.score)
            }

        } catch {
            print("Semantic search failed: \(error)")
            return await fallbackSearch(query: query)
        }
        #else
        return await fallbackSearch(query: query)
        #endif
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

        // Add filename
        if let filename = metadata.value(forKey: "filename") as? String {
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

        // Add extracted text
        if let text = metadata.value(forKey: "extractedText") as? String, !text.isEmpty {
            parts.append("Text: \(text)")
        }

        // Add dominant colors
        if let colorData = metadata.value(forKey: "dominantColors") as? Data,
           let colors = try? JSONDecoder().decode([String].self, from: colorData) {
            parts.append("Colors: \(colors.joined(separator: ", "))")
        }

        // Add EXIF data (camera, location if available)
        if let exifData = metadata.value(forKey: "exifData") as? NSManagedObject {
            var exifParts: [String] = []

            if let camera = exifData.value(forKey: "cameraModel") as? String {
                exifParts.append("Camera: \(camera)")
            }

            if let date = exifData.value(forKey: "captureDate") as? Date {
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

    /// Parse ranking response from language model
    private func parseRankings(_ response: String, count: Int) -> [(index: Int, score: Double)] {
        var rankings: [(index: Int, score: Double)] = []

        // Expected format: "3:0.95,1:0.82,5:0.75"
        let pairs = response.split(separator: ",")

        for pair in pairs {
            let components = pair.split(separator: ":")
            if components.count == 2,
               let index = Int(components[0].trimmingCharacters(in: .whitespaces)),
               let score = Double(components[1].trimmingCharacters(in: .whitespaces)),
               index >= 0 && index < count {
                rankings.append((index: index, score: score))
            }
        }

        return rankings
    }

    /// Create search result from metadata
    private func createSearchResult(from metadata: NSManagedObject, confidence: Double) -> ImageSearchResult {
        let id = (metadata.value(forKey: "id") as? UUID) ?? UUID()
        let filename = (metadata.value(forKey: "filename") as? String) ?? "Unknown"
        let filePath = (metadata.value(forKey: "filePath") as? String) ?? ""
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

        // Extract text
        let extractedText = metadata.value(forKey: "extractedText") as? String

        // Extract colors
        var dominantColors: [String] = []
        if let colorData = metadata.value(forKey: "dominantColors") as? Data,
           let colors = try? JSONDecoder().decode([String].self, from: colorData) {
            dominantColors = colors
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

    /// Fallback search using simple text matching
    private func fallbackSearch(query: String) async -> [ImageSearchResult] {
        print("Using fallback text search")

        let allMetadata = await fetchAllImageMetadata()
        let queryTerms = query.lowercased().components(separatedBy: " ")

        // Simple scoring based on term matches
        var scoredResults: [(metadata: NSManagedObject, score: Int)] = []

        for metadata in allMetadata {
            let document = createSearchableDocument(from: metadata).lowercased()
            var score = 0

            for term in queryTerms {
                if document.contains(term) {
                    score += 1
                }
            }

            if score > 0 {
                scoredResults.append((metadata: metadata, score: score))
            }
        }

        // Sort by score and take top results
        scoredResults.sort { $0.score > $1.score }

        return scoredResults.prefix(20).map { result in
            createSearchResult(
                from: result.metadata,
                confidence: Double(result.score) / Double(queryTerms.count)
            )
        }
    }
}

// MARK: - Foundation Models Extension (when available)

#if canImport(FoundationModels)
extension LanguageModelSession {
    /// Generate a response from the model
    func generateResponse(prompt: String) async throws -> String {
        // This would use the actual Foundation Models API
        // The exact API will depend on the final framework design

        // Placeholder for actual implementation:
        // let response = try await self.generate(prompt: prompt)
        // return response.text

        // For now, return empty string as we don't have the actual API
        return ""
    }
}

// Placeholder types until we have the actual Foundation Models framework
struct LanguageModelConfiguration {
    enum ModelType {
        case general
        case specialized
    }

    let modelType: ModelType
    let temperature: Double
}

class LanguageModelSession {
    init(configuration: LanguageModelConfiguration, systemPrompt: String) async throws {
        // Initialize session
    }
}
#endif