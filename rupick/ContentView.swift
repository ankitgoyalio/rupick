import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var session = ProjectSession()
    @State private var selectedIncoming: URL?
    @State private var projectAccess: URL?
    @State private var incomingAccess: [URL] = []

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading) {
                Text(session.root?.lastPathComponent ?? "No project selected")
                    .font(.headline).padding(.horizontal)
                List(session.results, selection: $selectedIncoming) { result in
                    VStack(alignment: .leading) {
                        Text(result.url.lastPathComponent)
                        Text(result.error == nil ? "\(result.candidates.count) exact matches" : "Image unavailable")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(result.url)
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            if let result = session.results.first(where: { $0.url == selectedIncoming }) {
                ComparisonDetail(result: result, root: session.root, provisional: session.isRunning,
                                 incomplete: session.skipped > 0 || session.error != nil || session.phase.hasPrefix("Search cancelled"))
            } else {
                ContentUnavailableView("Find an existing image", systemImage: "photo.on.rectangle.angled",
                    description: Text("Choose your project folder, then a PNG or JPEG to compare with its image assets."))
            }
        }
        .safeAreaInset(edge: .bottom) {
            SessionProgress(session: session).padding().background(.bar)
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
            session.start(root: url, incoming: [])
        }
    }

    private func pickImages() {
        let panel = NSOpenPanel()
        panel.title = "Choose incoming images"
        panel.allowedContentTypes = [.png, .jpeg]
        panel.allowsMultipleSelection = true
        panel.begin { response in
            guard response == .OK, let root = session.root else { return }
            let existing = session.results.map(\.url)
            let added = panel.urls.filter { !existing.contains($0) }
            for url in added where url.startAccessingSecurityScopedResource() { incomingAccess.append(url) }
            session.start(root: root, incoming: existing + added)
            selectedIncoming = added.first ?? existing.first
        }
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
                Text("Results are provisional while the search runs.").font(.caption)
            }
            if let error = session.error { Text(error).foregroundStyle(.red) }
            if session.skipped > 0 {
                Text("Incomplete scan: \(session.skipped) unreadable or unsupported catalog entries or images were skipped.")
                    .foregroundStyle(.orange).font(.caption)
            }
            Text("Exact matches only. Resized copies and images with changed transparent padding are not detected.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct ComparisonDetail: View {
    let result: IncomingResult
    let root: URL?
    let provisional: Bool
    let incomplete: Bool
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(result.url.lastPathComponent).font(.title)
                if let error = result.error { Text(error).foregroundStyle(.red) }
                if result.candidates.isEmpty {
                    ImagePreview(url: result.url, title: "Incoming")
                    Text(provisional ? "Searching for exact matches…" :
                         incomplete ? "No matches in the completed portion of the search." : "No matches found")
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
