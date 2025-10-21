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

    // macOS version check
    private var isMacOS26OrLater: Bool {
        if #available(macOS 26, *) {
            return true
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
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16)
            ], spacing: 16) {
                ForEach(searchResults) { result in
                    SearchResultCard(result: result)
                        .onTapGesture {
                            selectedResult = result
                        }
                }
            }
            .padding()
        }
        .sheet(item: $selectedResult) { result in
            SearchResultDetailView(result: result)
        }
    }

    // MARK: - Search Logic

    private func performSearch() {
        guard !searchText.isEmpty else { return }
        guard isMacOS26OrLater else {
            print("❌ Smart Search requires macOS 26 or later")
            return
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

// MARK: - Search Result Card

struct SearchResultCard: View {
    let result: ImageSearchResult
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
            guard FileManager.default.fileExists(atPath: path) else {
                print("⚠️ File not found: \(path)")
                return
            }

            guard let image = NSImage(contentsOfFile: path) else {
                print("⚠️ Failed to load image: \(path)")
                return
            }

            // Create thumbnail (150x150)
            let thumbnailSize = NSSize(width: 150, height: 150)
            let thumbnailImage = NSImage(size: thumbnailSize)

            thumbnailImage.lockFocus()
            image.draw(in: NSRect(origin: .zero, size: thumbnailSize),
                      from: NSRect(origin: .zero, size: image.size),
                      operation: .copy,
                      fraction: 1.0)
            thumbnailImage.unlockFocus()

            await MainActor.run {
                self.thumbnail = thumbnailImage
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