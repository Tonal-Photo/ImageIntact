import SwiftUI
import CoreData

struct VisionResultsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = "overview"
    @State private var searchText = ""
    @State private var selectedScene: String?
    @State private var showOnlyFaces = false
    @State private var showOnlyText = false

    // Core Data fetch results
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "analysisDate", ascending: false)]
    ) private var allImages: FetchedResults<ImageMetadata>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "confidence", ascending: false)]
    ) private var allScenes: FetchedResults<SceneClassification>

    private var filteredImages: [ImageMetadata] {
        var results = Array(allImages)

        // Filter by search text
        if !searchText.isEmpty {
            results = results.filter { image in
                let path = image.filePath ?? ""
                return path.lowercased().contains(searchText.lowercased())
            }
        }

        // Filter by faces
        if showOnlyFaces {
            results = results.filter { image in
                return image.faceCount > 0
            }
        }

        // Filter by text
        if showOnlyText {
            results = results.filter { image in
                return image.hasText
            }
        }

        // Filter by scene
        if let scene = selectedScene {
            results = results.filter { image in
                guard let scenes = image.sceneClassifications as? Set<SceneClassification> else {
                    return false
                }
                return scenes.contains { sceneObj in
                    return sceneObj.label == scene
                }
            }
        }

        return results
    }

    private var sceneStatistics: [(scene: String, count: Int)] {
        var sceneCounts: [String: Int] = [:]

        for scene in allScenes {
            let label = scene.label ?? "Unknown"
            sceneCounts[label, default: 0] += 1
        }

        return sceneCounts
            .sorted { $0.value > $1.value }
            .map { (scene: $0.key, count: $0.value) }
    }

    private var imagesWithFaces: Int {
        allImages.filter { image in
            return image.faceCount > 0
        }.count
    }

    private var imagesWithText: Int {
        allImages.filter { image in
            return image.hasText
        }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Vision Analysis Results", systemImage: "eye.circle.fill")
                    .font(.system(size: 18, weight: .semibold))

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .help("Close window")
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Tab Selection
            Picker("View", selection: $selectedTab) {
                Text("Overview").tag("overview")
                Text("Browse").tag("browse")
                Text("Scenes").tag("scenes")
            }
            .pickerStyle(.segmented)
            .padding()

            // Content based on selected tab
            Group {
                if selectedTab == "overview" {
                    overviewTab
                } else if selectedTab == "browse" {
                    browseTab
                } else if selectedTab == "scenes" {
                    scenesTab
                }
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var overviewTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Summary Statistics
                VStack(alignment: .leading, spacing: 16) {
                    Text("Analysis Summary")
                        .font(.system(size: 16, weight: .semibold))

                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 16) {
                        StatCard(
                            title: "Total Analyzed",
                            value: "\(allImages.count)",
                            icon: "photo.stack",
                            color: .blue
                        )

                        StatCard(
                            title: "Photos with Faces",
                            value: "\(imagesWithFaces)",
                            icon: "person.crop.square",
                            color: .green
                        )

                        StatCard(
                            title: "Photos with Text",
                            value: "\(imagesWithText)",
                            icon: "text.magnifyingglass",
                            color: .orange
                        )
                    }
                }

                Divider()

                // Top Scenes
                VStack(alignment: .leading, spacing: 12) {
                    Text("Top Detected Scenes")
                        .font(.system(size: 16, weight: .semibold))

                    ForEach(sceneStatistics.prefix(10), id: \.scene) { stat in
                        HStack {
                            Text(stat.scene)
                                .font(.system(size: 13))

                            Spacer()

                            Text("\(stat.count)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)

                            // Progress bar
                            GeometryReader { geometry in
                                Rectangle()
                                    .fill(Color.accentColor.opacity(0.3))
                                    .frame(
                                        width: geometry.size.width *
                                            (Double(stat.count) / Double(sceneStatistics.first?.count ?? 1))
                                    )
                            }
                            .frame(width: 100, height: 4)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(2)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding()
        }
    }

    private var browseTab: some View {
        VStack(spacing: 0) {
            // Search and Filters
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search by filename...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)

                Toggle("Faces Only", isOn: $showOnlyFaces)
                    .toggleStyle(.checkbox)

                Toggle("Text Only", isOn: $showOnlyText)
                    .toggleStyle(.checkbox)

                if selectedScene != nil {
                    Button(action: { selectedScene = nil }) {
                        Label("Clear Scene Filter", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding()

            Divider()

            // Results List
            if filteredImages.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "photo.badge.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.5))

                    Text("No images match your filters")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredImages, id: \.self) { image in
                    ImageResultRow(image: image) {
                        // On scene click, filter by that scene
                        if let scene = $0 {
                            selectedScene = scene
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var scenesTab: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 150, maximum: 200))
            ], spacing: 16) {
                ForEach(sceneStatistics, id: \.scene) { stat in
                    VStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.accentColor.opacity(0.1))
                                .frame(height: 80)

                            VStack {
                                Text(stat.scene)
                                    .font(.system(size: 14, weight: .medium))
                                    .multilineTextAlignment(.center)

                                Text("\(stat.count) photos")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }

                        Button(action: {
                            selectedScene = stat.scene
                            selectedTab = "browse"
                        }) {
                            Text("Browse")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
            .padding()
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
            }

            Text(value)
                .font(.system(size: 24, weight: .semibold))

            Text(title)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct ImageResultRow: View {
    let image: ImageMetadata
    let onSceneClick: (String?) -> Void

    private var fileName: String {
        let path = image.filePath ?? ""
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private var scenes: [String] {
        guard let sceneSet = image.sceneClassifications as? Set<SceneClassification> else {
            return []
        }

        return sceneSet
            .compactMap { $0.label }
            .sorted()
            .prefix(3)
            .map { $0 }
    }

    private var faceCount: Int {
        Int(image.faceCount)
    }

    private var hasText: Bool {
        image.hasText
    }

    private var dimensions: String {
        // Use original dimensions if available, otherwise fall back to analysis dimensions
        let width = image.originalWidth > 0 ? image.originalWidth : image.imageWidth
        let height = image.originalHeight > 0 ? image.originalHeight : image.imageHeight
        return "\(width)×\(height)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(fileName)
                    .font(.system(size: 13, weight: .medium))

                Spacer()

                Text(dimensions)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 12) {
                // Scenes
                if !scenes.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(scenes, id: \.self) { scene in
                            Button(action: { onSceneClick(scene) }) {
                                Text(scene)
                                    .font(.system(size: 11))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.1))
                                    .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Spacer()

                // Indicators
                if faceCount > 0 {
                    Label("\(faceCount)", systemImage: "person.crop.square")
                        .font(.system(size: 11))
                        .foregroundColor(.green)
                }

                if hasText {
                    Image(systemName: "text.magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(.vertical, 8)
    }
}

// Window Manager
@MainActor
final class VisionResultsWindowManager: NSObject, ObservableObject, Sendable {
    static let shared = VisionResultsWindowManager()
    private var window: NSWindow?

    @MainActor
    func showVisionResults() {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let contentView = VisionResultsView()
            .environment(\.managedObjectContext, EventLogger.shared.container.viewContext)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.center()
        window.title = "Vision Analysis Results"
        window.contentView = NSHostingView(rootView: contentView)
        window.isReleasedWhenClosed = false
        window.level = .floating

        self.window = window
        window.makeKeyAndOrderFront(nil)
    }

    @MainActor
    func closeWindow() {
        window?.close()
        window = nil
    }
}