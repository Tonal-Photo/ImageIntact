//
//  SmartSearchView.swift
//  ImageIntact
//
//  Intelligent search interface for finding images using Vision and Core Image metadata
//

import SwiftUI
import CoreData

struct SmartSearchView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var searchResults: [ImageSearchResult] = []
    @State private var isSearching = false
    @State private var selectedResult: ImageSearchResult?
    @State private var searchScope: SearchScope = .all
    @State private var showAdvancedFilters = false

    // Advanced filters
    @State private var filterByScenes = true
    @State private var filterByObjects = true
    @State private var filterByText = true
    @State private var filterByColors = true
    @State private var filterByQuality = false
    @State private var minConfidence: Double = 0.5

    // Focus management
    @FocusState private var isSearchFieldFocused: Bool

    // Security-scoped source folder access
    @State private var sourceURL: URL?
    @State private var isAccessingSource = false

    // Foundation Models readiness
    @State private var searchWhenReady = false

    // Browse mode stats
    @State private var totalImagesInCategory = 0
    @State private var isBrowseMode = true

    // Drill-down navigation for browse mode
    @State private var browseCategories: [BrowseCategory] = []
    @State private var selectedCategory: BrowseCategory?
    @State private var isDrilledDown = false

    // macOS version check
    private var isMacOS26OrLater: Bool {
        if #available(macOS 26, *) {
            return true
        }
        return false
    }

    // Check if search is ready
    private var isSearchReady: Bool {
        if #available(macOS 26, *) {
            return SemanticImageSearch.shared.isReady
        }
        return false
    }

    enum SearchScope: String, CaseIterable {
        case all = "All"
        case scenes = "Scenes"
        case objects = "Objects"
        case text = "Text"
        case faces = "Faces"
        case technical = "Technical"

        var icon: String {
            switch self {
            case .all: return "magnifyingglass"
            case .scenes: return "photo"
            case .objects: return "cube"
            case .text: return "text.magnifyingglass"
            case .faces: return "person.crop.rectangle"
            case .technical: return "gear"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search Header
            searchHeader

            Divider()

            // Main Content
            if !isMacOS26OrLater {
                upgradeRequiredState
            } else if searchResults.isEmpty && !searchText.isEmpty && !isSearching {
                emptyState
            } else if isSearching {
                loadingState
            } else if !searchResults.isEmpty {
                resultsList
            } else {
                welcomeState
            }
        }
        .frame(width: 800, height: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            // Set focus to search field when view appears
            isSearchFieldFocused = true

            // Load source folder bookmark for thumbnail access
            loadSourceBookmark()

            // Pre-warm Foundation Models session (triggers initialization)
            if #available(macOS 26, *) {
                _ = SemanticImageSearch.shared
            }

            // Load browse mode results for initial category
            loadBrowseResults()
        }
        .onChange(of: searchScope) { _, _ in
            // Refocus search field when scope changes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isSearchFieldFocused = true
            }

            // Reload browse results for new category
            if searchText.isEmpty {
                isDrilledDown = false
                selectedCategory = nil
                loadBrowseResults()
            }
        }
        .onChange(of: searchText) { _, newText in
            // Switch between browse and search modes
            isBrowseMode = newText.isEmpty
            if isBrowseMode {
                isDrilledDown = false
                selectedCategory = nil
                loadBrowseResults()
            }
        }
        .onDisappear {
            // Stop accessing security-scoped resource when view closes
            stopAccessingSource()
        }
        .onChange(of: isSearchReady) { _, isReady in
            // Auto-trigger search when Foundation Models becomes ready
            if isReady && searchWhenReady {
                searchWhenReady = false
                performSearch()
            }
        }
    }

    private func loadSourceBookmark() {
        guard let bookmarkData = UserDefaults.standard.data(forKey: "sourceBookmark") else {
            print("⚠️ No source bookmark found in UserDefaults")
            return
        }

        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: bookmarkData,
                            options: .withSecurityScope,
                            relativeTo: nil,
                            bookmarkDataIsStale: &isStale)

            if isStale {
                print("⚠️ Source bookmark is stale")
            }

            // Start accessing and KEEP accessing while view is open
            let didStart = url.startAccessingSecurityScopedResource()
            if didStart {
                isAccessingSource = true
                sourceURL = url
                print("✅ Loaded source bookmark and started security access: \(url.lastPathComponent)")
            } else {
                print("❌ Failed to start accessing security-scoped resource")
            }
        } catch {
            print("❌ Failed to load source bookmark: \(error)")
        }
    }

    private func stopAccessingSource() {
        if isAccessingSource, let url = sourceURL {
            url.stopAccessingSecurityScopedResource()
            isAccessingSource = false
            print("✅ Stopped accessing security-scoped resource")
        }
    }

    private var searchHeader: some View {
        VStack(spacing: 12) {
            // Title and close button
            HStack {
                Label("Smart Image Search", systemImage: "sparkle.magnifyingglass")
                    .font(.title2.bold())

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.top)

            // Search field with scope selector
            HStack(spacing: 8) {
                // Scope selector
                Picker("", selection: $searchScope) {
                    ForEach(SearchScope.allCases, id: \.self) { scope in
                        Label(scope.rawValue, systemImage: scope.icon)
                            .tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 300)
                .onChange(of: searchScope) { _, _ in
                    // Refocus search field when scope changes
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isSearchFieldFocused = true
                    }
                }

                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)

                    TextField("Search by scene, object, text, color...", text: $searchText)
                        .textFieldStyle(.plain)
                        .focused($isSearchFieldFocused)
                        .onSubmit {
                            performSearch()
                        }

                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                // Advanced filters toggle
                Button(action: { showAdvancedFilters.toggle() }) {
                    Image(systemName: showAdvancedFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .foregroundColor(showAdvancedFilters ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help("Advanced filters")
            }
            .padding(.horizontal)

            // Advanced filters (collapsible)
            if showAdvancedFilters {
                advancedFilters
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showAdvancedFilters)
    }

    private var advancedFilters: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Search in:")
                .font(.caption.bold())
                .foregroundColor(.secondary)

            HStack(spacing: 16) {
                Toggle("Scenes", isOn: $filterByScenes)
                Toggle("Objects", isOn: $filterByObjects)
                Toggle("Text (OCR)", isOn: $filterByText)
                Toggle("Colors", isOn: $filterByColors)
                Toggle("Quality", isOn: $filterByQuality)
            }
            .toggleStyle(.checkbox)
            .font(.caption)

            HStack {
                Text("Min Confidence:")
                    .font(.caption)
                Slider(value: $minConfidence, in: 0...1)
                    .frame(width: 150)
                Text("\(Int(minConfidence * 100))%")
                    .font(.caption.monospacedDigit())
                    .frame(width: 40, alignment: .trailing)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .padding(.horizontal)
    }

    private var welcomeState: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("Search Your Backed-Up Images")
                .font(.title2)

            VStack(alignment: .leading, spacing: 12) {
                Text("Try searching for:")
                    .font(.headline)

                ForEach(searchSuggestions, id: \.self) { suggestion in
                    Button(action: {
                        searchText = suggestion
                        performSearch()
                    }) {
                        HStack {
                            Image(systemName: "arrow.right.circle")
                                .foregroundColor(.secondary)
                            Text(suggestion)
                                .foregroundColor(.primary)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 400)

            Spacer()
        }
        .padding()
    }

    private var searchSuggestions: [String] {
        [
            "sunset beach",
            "wedding ceremony",
            "text documents",
            "photos with faces",
            "outdoor landscape",
            "pets and animals",
            "blurry images"
        ]
    }

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.5)

            Text("Searching...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var upgradeRequiredState: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundColor(.orange)

            Text("macOS 26 (Tahoe) Required")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 12) {
                Text("Smart Search uses Apple's Foundation Models framework, which requires macOS 26 (Tahoe) or later.")
                    .multilineTextAlignment(.center)

                Text("Foundation Models provides:")
                    .font(.headline)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 8) {
                    Label("On-device semantic search", systemImage: "brain")
                    Label("Natural language queries", systemImage: "text.bubble")
                    Label("Privacy-first AI processing", systemImage: "lock.shield")
                    Label("No internet required", systemImage: "wifi.slash")
                }
                .padding(.leading, 8)

                Button(action: {
                    if let url = URL(string: "https://www.apple.com/macos/macos-tahoe/") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    Label("Learn About macOS 26", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
            }
            .frame(maxWidth: 500)

            Spacer()
        }
        .padding()
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.badge.magnifyingglass")
                .font(.system(size: 50))
                .foregroundColor(.secondary)

            Text("No Results Found")
                .font(.title2)

            Text("Try different keywords or adjust filters")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultsList: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Browse mode: show either category list or drilled-down images
                if isBrowseMode {
                    if isDrilledDown {
                        // Drilled down: show images for selected category
                        imageGridForCategory
                    } else {
                        // Top level: show category list
                        categoryListView
                    }
                } else {
                    // Search mode: show search results
                    searchResultsGrid
                }
            }
        }
        .sheet(item: $selectedResult) { result in
            SearchResultDetailView(result: result)
        }
    }

    private var categoryListView: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !browseCategories.isEmpty {
                // Header
                HStack {
                    Label {
                        Text("Found \(browseCategories.count) \(categoryTypeText)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } icon: {
                        Image(systemName: "list.bullet")
                            .foregroundColor(.accentColor)
                    }
                    Spacer()
                }
                .padding()

                // Category list
                LazyVStack(spacing: 1) {
                    ForEach(browseCategories) { category in
                        CategoryRow(category: category)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectCategory(category)
                            }
                    }
                }
            }
        }
    }

    private var imageGridForCategory: some View {
        VStack(spacing: 16) {
            // Back button and category header
            if let category = selectedCategory {
                HStack {
                    Button(action: {
                        isDrilledDown = false
                        selectedCategory = nil
                    }) {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)

                    Spacer()

                    Text("\(category.displayName) (\(searchResults.count) images)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }

            // Image grid
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16)
            ], spacing: 16) {
                ForEach(searchResults) { result in
                    SearchResultCard(result: result, sourceURL: sourceURL)
                        .onTapGesture {
                            selectedResult = result
                        }
                }
            }
            .padding()
        }
    }

    private var searchResultsGrid: some View {
        VStack(spacing: 16) {
            // Stats header for search mode
            if totalImagesInCategory > 0 {
                HStack {
                    Label {
                        Text(statsText)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } icon: {
                        Image(systemName: "info.circle")
                            .foregroundColor(.accentColor)
                    }

                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }

            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16)
            ], spacing: 16) {
                ForEach(searchResults) { result in
                    SearchResultCard(result: result, sourceURL: sourceURL)
                        .onTapGesture {
                            selectedResult = result
                        }
                }
            }
            .padding()
        }
    }

    private var categoryTypeText: String {
        switch searchScope {
        case .all:
            return "categories"
        case .scenes:
            return "scenes"
        case .objects:
            return "objects"
        case .text:
            return "images with text"
        case .faces:
            return "images with faces"
        case .technical:
            return "images"
        }
    }

    private func selectCategory(_ category: BrowseCategory) {
        selectedCategory = category
        isDrilledDown = true
        loadImagesForCategory(category)
    }

    private var statsText: String {
        let categoryName: String
        switch searchScope {
        case .all:
            categoryName = "images"
        case .scenes:
            categoryName = "images with scenes"
        case .objects:
            categoryName = "images with objects"
        case .text:
            categoryName = "images with text"
        case .faces:
            categoryName = "images with faces"
        case .technical:
            categoryName = "images with technical data"
        }

        if searchResults.count < totalImagesInCategory {
            return "Found \(totalImagesInCategory) \(categoryName) • Showing top \(searchResults.count) by recency"
        } else {
            return "Found \(totalImagesInCategory) \(categoryName)"
        }
    }

    // MARK: - Search Logic

    private func performSearch() {
        guard !searchText.isEmpty else { return }
        guard isMacOS26OrLater else {
            print("❌ Smart Search requires macOS 26 or later")
            return
        }

        // Check if Foundation Models session is ready
        if #available(macOS 26, *) {
            guard isSearchReady else {
                print("⏳ Foundation Models initializing... search will start automatically when ready")
                searchWhenReady = true
                return
            }
        }

        isSearching = true
        searchResults = []

        Task {
            if #available(macOS 26, *) {
                // Use Foundation Models semantic search
                let results = await SemanticImageSearch.shared.search(query: searchText)

                await MainActor.run {
                    self.searchResults = results
                    self.isSearching = false
                }
            }
        }
    }

    private func loadBrowseResults() {
        guard isMacOS26OrLater else { return }

        isSearching = true
        browseCategories = []
        isDrilledDown = false
        selectedCategory = nil

        // Capture the scope before async work
        let scope = searchScope

        Task {
            let context = EventLogger.shared.backgroundContext

            let categories = await context.perform {
                // Fetch categories with counts based on scope
                switch scope {
                case .scenes:
                    return self.fetchSceneCategories(context: context)
                case .objects:
                    return self.fetchObjectCategories(context: context)
                case .text:
                    return self.fetchTextImages(context: context)
                case .faces:
                    return self.fetchFaceImages(context: context)
                case .technical:
                    return self.fetchTechnicalImages(context: context)
                case .all:
                    return self.fetchAllCategories(context: context)
                }
            }

            await MainActor.run {
                self.browseCategories = categories
                self.isSearching = false
                print("✅ Browse mode: Loaded \(categories.count) categories")
            }
        }
    }

    private nonisolated func fetchSceneCategories(context: NSManagedObjectContext) -> [BrowseCategory] {
        let request = NSFetchRequest<NSDictionary>(entityName: "SceneClassification")
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = ["identifier"]
        request.returnsDistinctResults = true

        do {
            let scenes = try context.fetch(request)
            var categoryCounts: [String: Int] = [:]

            // Count images for each scene
            for sceneDict in scenes {
                if let identifier = sceneDict["identifier"] as? String {
                    let countRequest = NSFetchRequest<NSManagedObject>(entityName: "SceneClassification")
                    countRequest.predicate = NSPredicate(format: "identifier == %@", identifier)
                    let count = try context.count(for: countRequest)
                    categoryCounts[identifier] = count
                }
            }

            // Convert to BrowseCategory and sort by count
            return categoryCounts.map { identifier, count in
                BrowseCategory(
                    name: identifier,
                    displayName: identifier.replacingOccurrences(of: "_", with: " ").capitalized,
                    count: count,
                    scope: .scenes
                )
            }.sorted { $0.count > $1.count }

        } catch {
            print("❌ Failed to fetch scene categories: \(error)")
            return []
        }
    }

    private nonisolated func fetchObjectCategories(context: NSManagedObjectContext) -> [BrowseCategory] {
        let request = NSFetchRequest<NSDictionary>(entityName: "DetectedObject")
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = ["label"]
        request.returnsDistinctResults = true

        do {
            let objects = try context.fetch(request)
            var categoryCounts: [String: Int] = [:]

            // Count images for each object
            for objectDict in objects {
                if let label = objectDict["label"] as? String {
                    let countRequest = NSFetchRequest<NSManagedObject>(entityName: "DetectedObject")
                    countRequest.predicate = NSPredicate(format: "label == %@", label)
                    let count = try context.count(for: countRequest)
                    categoryCounts[label] = count
                }
            }

            // Convert to BrowseCategory and sort by count
            return categoryCounts.map { label, count in
                BrowseCategory(
                    name: label,
                    displayName: label,
                    count: count,
                    scope: .objects
                )
            }.sorted { $0.count > $1.count }

        } catch {
            print("❌ Failed to fetch object categories: \(error)")
            return []
        }
    }

    private nonisolated func fetchTextImages(context: NSManagedObjectContext) -> [BrowseCategory] {
        // For text, just return images with text (no subcategories)
        let request = NSFetchRequest<NSManagedObject>(entityName: "ImageMetadata")
        request.predicate = NSPredicate(format: "hasText == YES")

        do {
            let count = try context.count(for: request)
            return [BrowseCategory(name: "text", displayName: "Images with Text", count: count, scope: .text)]
        } catch {
            print("❌ Failed to fetch text images: \(error)")
            return []
        }
    }

    private nonisolated func fetchFaceImages(context: NSManagedObjectContext) -> [BrowseCategory] {
        // For faces, just return images with faces (no subcategories)
        let request = NSFetchRequest<NSManagedObject>(entityName: "ImageMetadata")
        request.predicate = NSPredicate(format: "faceCount > 0")

        do {
            let count = try context.count(for: request)
            return [BrowseCategory(name: "faces", displayName: "Images with Faces", count: count, scope: .faces)]
        } catch {
            print("❌ Failed to fetch face images: \(error)")
            return []
        }
    }

    private nonisolated func fetchTechnicalImages(context: NSManagedObjectContext) -> [BrowseCategory] {
        // For technical, return categories for color/EXIF/quality
        var categories: [BrowseCategory] = []

        do {
            // Color analysis
            let colorRequest = NSFetchRequest<NSManagedObject>(entityName: "ImageMetadata")
            colorRequest.predicate = NSPredicate(format: "colorAnalysis != nil")
            let colorCount = try context.count(for: colorRequest)
            if colorCount > 0 {
                categories.append(BrowseCategory(name: "color", displayName: "Color Analysis", count: colorCount, scope: .technical))
            }

            // EXIF data
            let exifRequest = NSFetchRequest<NSManagedObject>(entityName: "ImageMetadata")
            exifRequest.predicate = NSPredicate(format: "exifData != nil")
            let exifCount = try context.count(for: exifRequest)
            if exifCount > 0 {
                categories.append(BrowseCategory(name: "exif", displayName: "EXIF Data", count: exifCount, scope: .technical))
            }

            return categories
        } catch {
            print("❌ Failed to fetch technical images: \(error)")
            return []
        }
    }

    private nonisolated func fetchAllCategories(context: NSManagedObjectContext) -> [BrowseCategory] {
        var categories: [BrowseCategory] = []

        // Get top scenes
        categories.append(contentsOf: fetchSceneCategories(context: context).prefix(10))
        // Get all objects
        categories.append(contentsOf: fetchObjectCategories(context: context))
        // Get text/face counts
        categories.append(contentsOf: fetchTextImages(context: context))
        categories.append(contentsOf: fetchFaceImages(context: context))

        return categories.sorted { $0.count > $1.count }
    }

    private func loadImagesForCategory(_ category: BrowseCategory) {
        isSearching = true
        searchResults = []

        Task {
            let context = EventLogger.shared.backgroundContext

            let results = await context.perform {
                let request = NSFetchRequest<NSManagedObject>(entityName: "ImageMetadata")

                // Build predicate based on category type
                switch category.scope {
                case .scenes:
                    // Find images with this scene classification
                    request.predicate = NSPredicate(
                        format: "ANY sceneClassifications.identifier == %@",
                        category.name
                    )
                case .objects:
                    // Find images with this detected object
                    request.predicate = NSPredicate(
                        format: "ANY detectedObjects.label == %@",
                        category.name
                    )
                case .text:
                    request.predicate = NSPredicate(format: "hasText == YES")
                case .faces:
                    request.predicate = NSPredicate(format: "faceCount > 0")
                case .technical:
                    if category.name == "color" {
                        request.predicate = NSPredicate(format: "colorAnalysis != nil")
                    } else if category.name == "exif" {
                        request.predicate = NSPredicate(format: "exifData != nil")
                    }
                case .all:
                    request.predicate = nil
                }

                // Prefetch relationships
                request.relationshipKeyPathsForPrefetching = [
                    "sceneClassifications",
                    "detectedObjects",
                    "colorAnalysis",
                    "exifData"
                ]

                // Sort by analysis date (most recent first)
                request.sortDescriptors = [NSSortDescriptor(key: "analysisDate", ascending: false)]

                // Limit to 100 for performance
                request.fetchLimit = 100

                do {
                    let metadata = try context.fetch(request)
                    print("📊 Fetched \(metadata.count) images for category '\(category.displayName)'")

                    // Convert to ImageSearchResult
                    let results: [ImageSearchResult] = metadata.compactMap { item in
                        Self.createSearchResult(from: item, confidence: 1.0)
                    }

                    return results
                } catch {
                    print("❌ Failed to fetch images for category: \(error)")
                    return []
                }
            }

            await MainActor.run {
                self.searchResults = results
                self.isSearching = false
                print("✅ Loaded \(results.count) images for '\(category.displayName)'")
            }
        }
    }

    /// Create search result from Core Data metadata
    private nonisolated static func createSearchResult(from metadata: NSManagedObject, confidence: Double) -> ImageSearchResult? {
        guard let id = metadata.value(forKey: "id") as? UUID,
              let filePath = metadata.value(forKey: "filePath") as? String else {
            return nil
        }

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
        var extractedText: String?
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

// MARK: - Browse Category Model

struct BrowseCategory: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let displayName: String
    let count: Int
    let scope: SmartSearchView.SearchScope

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: BrowseCategory, rhs: BrowseCategory) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Search Result Model

struct ImageSearchResult: Identifiable {
    let id: UUID
    let filename: String
    let filePath: String
    let checksum: String
    let analysisDate: Date
    let matchedScenes: [String]
    let matchedObjects: [String]
    let extractedText: String?
    let dominantColors: [String]
    let confidence: Double

    // Direct initializer for when we're building results manually
    init(
        id: UUID,
        filename: String,
        filePath: String,
        checksum: String,
        analysisDate: Date,
        matchedScenes: [String],
        matchedObjects: [String],
        extractedText: String?,
        dominantColors: [String],
        confidence: Double
    ) {
        self.id = id
        self.filename = filename
        self.filePath = filePath
        self.checksum = checksum
        self.analysisDate = analysisDate
        self.matchedScenes = matchedScenes
        self.matchedObjects = matchedObjects
        self.extractedText = extractedText
        self.dominantColors = dominantColors
        self.confidence = confidence
    }

}

// MARK: - Category Row

struct CategoryRow: View {
    let category: BrowseCategory

    var body: some View {
        HStack(spacing: 12) {
            // Icon based on category type
            Image(systemName: iconForCategory)
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 32)

            // Category name
            Text(category.displayName)
                .font(.body)

            Spacer()

            // Count badge
            Text("\(category.count)")
                .font(.subheadline.monospacedDigit())
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)

            // Chevron
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
        .padding(.horizontal)
        .padding(.vertical, 2)
    }

    private var iconForCategory: String {
        switch category.scope {
        case .scenes:
            return "photo.fill"
        case .objects:
            return "cube.fill"
        case .text:
            return "doc.text.fill"
        case .faces:
            return "person.fill"
        default:
            return "square.grid.2x2.fill"
        }
    }
}

// MARK: - Search Result Card

struct SearchResultCard: View {
    let result: ImageSearchResult
    let sourceURL: URL?
    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail
            Group {
                if let thumbnail = thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay(
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundColor(.gray)
                        )
                }
            }
            .frame(width: 150, height: 150)
            .clipped()
            .cornerRadius(8)
            .onAppear {
                loadThumbnail()
            }

            // Filename
            Text(result.filename)
                .font(.caption)
                .lineLimit(1)

            // Match info
            HStack(spacing: 4) {
                if !result.matchedScenes.isEmpty {
                    Label("\(result.matchedScenes.count)", systemImage: "photo")
                        .font(.caption2)
                }
                if !result.matchedObjects.isEmpty {
                    Label("\(result.matchedObjects.count)", systemImage: "cube")
                        .font(.caption2)
                }
                if result.extractedText != nil {
                    Image(systemName: "text.magnifyingglass")
                        .font(.caption2)
                }
            }
            .foregroundColor(.secondary)
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        .shadow(radius: 2)
    }

    private func loadThumbnail() {
        Task {
            // Load thumbnail on background thread
            let path = result.filePath
            let fileURL = URL(fileURLWithPath: path)

            guard FileManager.default.fileExists(atPath: path) else {
                print("⚠️ File not found: \(path)")
                return
            }

            // Source folder security access is already active at view level
            // No need to start/stop here - just load the image

            // Try to load image using URL (better for sandboxed apps)
            guard let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                print("⚠️ Failed to load image: \(path)")
                return
            }

            // Create thumbnail (150x150)
            let thumbnailSize = NSSize(width: 150, height: 150)
            let nsImage = NSImage(cgImage: cgImage, size: thumbnailSize)

            await MainActor.run {
                self.thumbnail = nsImage
            }
        }
    }
}

// MARK: - Search Result Detail View

struct SearchResultDetailView: View {
    let result: ImageSearchResult
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text(result.filename)
                    .font(.title2.bold())

                Spacer()

                Button("Done") {
                    dismiss()
                }
            }

            // Image preview
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .aspectRatio(16/9, contentMode: .fit)
                .overlay(
                    Image(systemName: "photo")
                        .font(.system(size: 50))
                        .foregroundColor(.gray)
                )
                .cornerRadius(8)

            // Metadata
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !result.matchedScenes.isEmpty {
                        detailRow(title: "Scenes", items: result.matchedScenes)
                    }

                    if !result.matchedObjects.isEmpty {
                        detailRow(title: "Objects", items: result.matchedObjects)
                    }

                    if let text = result.extractedText, !text.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Extracted Text")
                                .font(.headline)
                            Text(text)
                                .font(.caption)
                                .padding(8)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(4)
                        }
                    }

                    if !result.dominantColors.isEmpty {
                        detailRow(title: "Colors", items: result.dominantColors)
                    }

                    // File info
                    VStack(alignment: .leading, spacing: 4) {
                        Text("File Information")
                            .font(.headline)
                        Text("Path: \(result.filePath)")
                            .font(.caption)
                        Text("Checksum: \(result.checksum)")
                            .font(.caption.monospaced())
                        Text("Analyzed: \(result.analysisDate.formatted())")
                            .font(.caption)
                    }
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(4)
                }
            }

            // Actions
            HStack {
                Button("Show in Finder") {
                    if let url = URL(string: "file://\(result.filePath)") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }

                Button("Copy Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result.filePath, forType: .string)
                }
            }
        }
        .padding()
        .frame(width: 600, height: 500)
    }

    private func detailRow(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)

            FlowLayout(spacing: 4) {
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(4)
                }
            }
        }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(for: subviews, in: proposal.width ?? 0, spacing: spacing)
        return CGSize(width: proposal.width ?? 0, height: result.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(for: subviews, in: bounds.width, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: result.positions[index].x + bounds.minX,
                                      y: result.positions[index].y + bounds.minY),
                         proposal: ProposedViewSize(result.sizes[index]))
        }
    }

    struct FlowResult {
        var height: CGFloat
        var positions: [CGPoint]
        var sizes: [CGSize]

        init(for subviews: Subviews, in width: CGFloat, spacing: CGFloat) {
            var positions: [CGPoint] = []
            var sizes: [CGSize] = []
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                sizes.append(size)

                if currentX + size.width > width && currentX > 0 {
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }

                positions.append(CGPoint(x: currentX, y: currentY))
                currentX += size.width + spacing
                lineHeight = max(lineHeight, size.height)
            }

            self.height = currentY + lineHeight
            self.positions = positions
            self.sizes = sizes
        }
    }
}