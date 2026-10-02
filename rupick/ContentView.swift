import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var session = ProjectSession()
    @State private var selectedIncoming: URL?
    @State private var projectAccess: URL?
    @State private var incomingAccess: [URL] = []
    @State private var dropNotice: String?
    @State private var dropTargeted = false

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading) {
                Text(session.root?.lastPathComponent ?? "No project selected")
                    .font(.headline).padding(.horizontal)
                List(session.results, selection: $selectedIncoming) { result in
                    VStack(alignment: .leading) {
                        Text(result.url.lastPathComponent)
                        Text(result.statusText)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(result.url)
                    .accessibilityIdentifier("incoming-" + result.url.lastPathComponent)
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            if let result = session.results.first(where: { $0.url == selectedIncoming }) {
                ComparisonDetail(result: result, root: session.root, searchFailed: session.state == .failed)
            } else {
                ContentUnavailableView("Find an existing image", systemImage: "photo.on.rectangle.angled",
                    description: Text("Choose your project folder, then choose or drop PNG or JPEG images to compare with its image assets."))
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading) {
                if let dropNotice { Text(dropNotice).foregroundStyle(.orange) }
                SessionProgress(session: session)
            }.padding().background(.bar)
        }
        .toolbar {
            Button("Open Project…", systemImage: "folder") { pickProject() }
                .accessibilityIdentifier("openProject").keyboardShortcut("o")
                .help("Choose a project folder and discover its image assets.")
            Button("Choose Images…", systemImage: "photo.badge.plus") { pickImages() }
                .accessibilityIdentifier("chooseImages").keyboardShortcut("i")
                .disabled(session.root == nil)
                .help(session.root == nil
                      ? Text("Open a project folder first.")
                      : Text("Choose PNG or JPEG images to find exact matches."))
            if session.isRunning {
                Button("Cancel Search") { session.cancel() }
                    .help("Stop the search and keep the matches found so far.")
            }
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 12).stroke(.tint, lineWidth: 3).padding(6).allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted, perform: acceptDrop)
        .frame(minWidth: 950, minHeight: 620)
        .onDisappear {
            session.cancel()
            releaseAccess()
        }
    }

    private func pickProject() {
        let panel = NSOpenPanel()
        panel.title = "Choose a project folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            session.cancel()
            releaseAccess()
            if url.startAccessingSecurityScopedResource() { projectAccess = url }
            selectedIncoming = nil
            dropNotice = nil
            session.start(root: url, incoming: [])
        }
    }

    private func pickImages() {
        let panel = NSOpenPanel()
        panel.title = "Choose incoming images"
        panel.allowedContentTypes = [.png, .jpeg]
        panel.allowsMultipleSelection = true
        panel.begin { response in
            guard response == .OK else { return }
            dropNotice = nil
            addImages(panel.urls)
        }
    }

    private func addImages(_ urls: [URL]) {
        guard let root = session.root else { return }
        let images = urls.filter { url in
            guard url.isFileURL, let type = UTType(filenameExtension: url.pathExtension) else { return false }
            return type.conforms(to: .png) || type.conforms(to: .jpeg)
        }
        if images.count != urls.count { dropNotice = "Some files were not added. Choose PNG or JPEG files." }
        let existing = session.results.map(\.url)
        var seen = Set(existing)
        let added = images.filter { seen.insert($0).inserted }
        guard !added.isEmpty else { return }
        for url in added where url.startAccessingSecurityScopedResource() { incomingAccess.append(url) }
        session.start(root: root, incoming: existing + added)
        selectedIncoming = added.first
    }

    private func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        guard session.root != nil else {
            dropNotice = "Open a project folder before dropping images."
            return false
        }
        dropNotice = nil
        let root = session.root
        let batch = IncomingDropBatch(count: providers.count) { urls in
            guard session.root == root else { return }
            if urls.count != providers.count { dropNotice = "Some dropped files could not be opened. Use Choose Images to try again." }
            addImages(urls)
        }
        for (index, provider) in providers.enumerated() {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                let url = data.flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                Task { @MainActor in batch.receive(url, at: index) }
            }
        }
        return !providers.isEmpty
    }

    private func releaseAccess() {
        projectAccess?.stopAccessingSecurityScopedResource()
        projectAccess = nil
        incomingAccess.forEach { $0.stopAccessingSecurityScopedResource() }
        incomingAccess = []
    }
}

private struct SessionProgress: View {
    let session: ProjectSession
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(session.phase).accessibilityIdentifier("searchStatus")
                Spacer()
                Text("\(session.compared) / \(session.discovered) assets compared")
            }
            if session.isRunning {
                if session.discovered > 0 {
                    ProgressView(value: Double(session.compared), total: Double(session.discovered))
                } else { ProgressView().controlSize(.small) }
                Text("\(session.decoded) / \(session.results.count) incoming images processed. Results are provisional while the search runs.").font(.caption)
            }
            if let error = session.error { Text(error).foregroundStyle(.red) }
            if session.skipped > 0 {
                Text("Incomplete scan: \(session.skipped) unreadable or unsupported catalog entries or images were skipped.")
                    .foregroundStyle(.orange).font(.caption)
            }
            Text("Exact matches only. Resized copies and images with changed transparent padding are not detected. No matches does not guarantee an image is safe to import.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct ComparisonDetail: View {
    let result: IncomingResult
    let root: URL?
    let searchFailed: Bool
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(result.url.lastPathComponent).font(.title)
                if let error = result.error {
                    Text(error).foregroundStyle(.red)
                } else if searchFailed {
                    Text("Search failed. Open the project folder again to retry.").foregroundStyle(.red)
                } else {
                    Text(result.statusText).accessibilityIdentifier("comparisonStatus")
                }
                if result.candidates.isEmpty {
                    ImagePreview(url: result.url, title: "Incoming")
                }
                ForEach(result.candidates) { candidate in
                    CandidateInspection(incoming: result.url, root: root, candidate: candidate)
                }
            }.padding()
        }
    }
}

private struct CandidateInspection: View {
    let incoming: URL
    let root: URL?
    let candidate: AssetCandidate
    @State private var selectedRepresentation: String?
    private var representation: Representation? {
        candidate.representations.first(where: { $0.id == selectedRepresentation }) ??
        candidate.representations.first(where: \.matches)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(candidate.name).font(.headline)
            Text(candidate.location).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Picker("Representation", selection: Binding(
                get: { representation?.id ?? "" }, set: { selectedRepresentation = $0 })) {
                ForEach(candidate.representations) { variant in
                    Text("\(variant.label) — \(variant.matches ? "Exact match" : "Alternative")").tag(variant.id)
                }
            }.accessibilityIdentifier("representationPicker")
            if let representation {
                HStack(alignment: .top, spacing: 16) {
                    ImagePreview(url: incoming, title: "Incoming")
                    ImagePreview(url: representation.url, title: representation.matches ? "Exact match" : "Alternative representation", accessURL: root)
                }
            }
        }.padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct ImagePreview: View {
    let url: URL
    let title: String
    var accessURL: URL? = nil
    @State private var preview: LoadedPreview?
    private struct LoadedPreview {
        let url: URL
        let image: NSImage
    }
    var body: some View {
        VStack {
            Text(title).font(.subheadline)
            ZStack {
                Rectangle().fill(Color(nsColor: .controlBackgroundColor))
                if let preview, preview.url == url {
                    Image(nsImage: preview.image).resizable().scaledToFit().padding(12)
                } else { Text("Preview unavailable").foregroundStyle(.secondary) }
            }.frame(height: 230)
            Text(url.lastPathComponent).font(.caption).textSelection(.enabled)
        }.frame(maxWidth: .infinity)
        .task(id: url) {
            preview = nil
            let scope = accessURL ?? url
            let thumbnail = await Task.detached(priority: .utility) { () -> CGImage? in
                let acquired = scope.startAccessingSecurityScopedResource()
                defer { if acquired { scope.stopAccessingSecurityScopedResource() } }
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
                return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 800
                ] as CFDictionary)
            }.value
            guard !Task.isCancelled else { return }
            preview = thumbnail.map { LoadedPreview(url: url, image: NSImage(cgImage: $0, size: .zero)) }
        }
    }
}

/// Keep provider completion order from changing the incoming list's order.
@MainActor
private final class IncomingDropBatch {
    private var urls: [URL?]
    private var remaining: Int
    private let completion: ([URL]) -> Void

    init(count: Int, completion: @escaping ([URL]) -> Void) {
        urls = Array(repeating: nil, count: count)
        remaining = count
        self.completion = completion
    }

    func receive(_ url: URL?, at index: Int) {
        urls[index] = url
        remaining -= 1
        if remaining == 0 { completion(urls.compactMap { $0 }) }
    }
}
