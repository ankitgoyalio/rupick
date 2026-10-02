import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var session = ProjectSession()
    @State private var selectedIncoming: URL?
    @State private var selectedGroup: String?
    @State private var projectAccess: URL?
    @State private var incomingAccess: [URL] = []
    @State private var dropNotice: String?
    @State private var dropTargeted = false

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading) {
                Text(session.root?.lastPathComponent ?? "No project selected")
                    .font(.headline).padding(.horizontal)
                Button("Project Duplicates") { selectedIncoming = nil }
                    .accessibilityIdentifier("projectDuplicates").padding(.horizontal)
                if selectedIncoming == nil {
                    List(session.duplicateGroups, selection: $selectedGroup) { group in
                        VStack(alignment: .leading) {
                            Text("\(group.members.count) assets with equal content")
                            Text(group.members.map(\.name).joined(separator: ", "))
                                .font(.caption).foregroundStyle(.secondary)
                        }.tag(group.id).accessibilityIdentifier("duplicateGroup")
                    }
                }
                if !session.results.isEmpty {
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
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            if let result = session.results.first(where: { $0.url == selectedIncoming }) {
                ComparisonDetail(result: result, root: session.root, searchFailed: session.state == .failed)
            } else if let root = session.root {
                if let group = session.duplicateGroups.first(where: { $0.id == selectedGroup }) ?? session.duplicateGroups.first {
                    DuplicateInspection(group: group, root: root).id(group.id)
                } else {
                    ContentUnavailableView(duplicateStatus, systemImage: "photo.on.rectangle.angled",
                        description: Text("Choose Images to compare incoming images with this project."))
                }
            } else {
                ContentUnavailableView("Find an existing image", systemImage: "photo.on.rectangle.angled",
                    description: Text("Choose a project folder to find exact duplicates among its image assets, or choose or drop incoming PNG or JPEG images to compare."))
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

    private var duplicateStatus: String {
        if session.isRunning { return "Looking for exact duplicates…" }
        if session.state == .failed { return "Duplicate scan failed" }
        if session.isIncomplete { return "Incomplete scan · no exact duplicates found so far" }
        return "No exact duplicates found"
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
            selectedGroup = nil
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
            Text("\(session.duplicateGroups.count) exact duplicate groups")
                .font(.caption).accessibilityIdentifier("duplicateGroupCount")
            if session.isRunning {
                if session.discovered > 0 {
                    ProgressView(value: Double(session.compared), total: Double(session.discovered))
                } else { ProgressView().controlSize(.small) }
                Text("\(session.duplicateGroups.count) provisional duplicate groups. \(session.decoded) / \(session.results.count) incoming images processed. Results are provisional while the search runs.").font(.caption)
            }
            if let error = session.error { Text(error).foregroundStyle(.red) }
            if session.skipped > 0 {
                Text("Incomplete scan: \(session.skipped) unreadable or unsupported catalog entries or images were skipped.")
                    .foregroundStyle(.orange).font(.caption)
            }
            Text("Equal content does not mean assets are interchangeable or safe to delete. Project files are read only.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Exact matches only. Resized copies and images with changed transparent padding are not detected. No matches does not guarantee an image is safe to import.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct DuplicateInspection: View {
    let group: DuplicateGroup
    let root: URL
    @State private var leftID: String = ""
    @State private var rightID: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DuplicateHeader(memberCount: group.members.count)
                HStack(alignment: .top) {
                    DuplicateMemberPanel(members: group.members, root: root, selectedID: $leftID, fallback: group.members[0])
                    DuplicateMemberPanel(members: group.members, root: root, selectedID: $rightID, fallback: group.members[1])
                }
                DuplicateParticipants(members: group.members)
            }.padding()
        }
    }

}

private struct DuplicateHeader: View {
    let memberCount: Int
    var body: some View {
        VStack(alignment: .leading) {
            Text("Exact duplicate content").font(.title)
            Text("\(memberCount) distinct assets participate in this group.")
        }
    }
}

private struct DuplicateParticipants: View {
    let members: [AssetCandidate]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Participating assets").font(.headline)
            ForEach(members) { member in
                DuplicateParticipant(member: member)
            }
        }
    }
}

private struct DuplicateParticipant: View {
    let member: AssetCandidate
    var body: some View {
        VStack(alignment: .leading) {
            Text(member.name).font(.headline)
            Text(member.location).font(.caption).textSelection(.enabled)
            ForEach(member.representations) { representation in
                if representation.matches {
                    Text("\(representation.url.lastPathComponent) · \(representation.label)")
                        .font(.caption)
                }
            }
        }
    }
}

private struct DuplicateMemberPanel: View {
    let members: [AssetCandidate]
    let root: URL
    @Binding var selectedID: String
    let fallback: AssetCandidate
    var body: some View {
        let member = members.first { $0.id == selectedID } ?? fallback
        VStack(alignment: .leading) {
            Picker("Asset", selection: $selectedID) {
                Text("\(fallback.name) · \(fallback.location)").tag("")
                ForEach(members) { candidate in
                    Text("\(candidate.name) · \(candidate.location)").tag(candidate.id)
                }
            }.accessibilityIdentifier("duplicateMemberPicker")
            DuplicateMemberPreview(member: member, root: root).id(member.id)
        }.frame(maxWidth: .infinity)
    }
}

private struct DuplicateMemberPreview: View {
    let member: AssetCandidate
    let root: URL
    @State private var selectedID = ""
    private var representation: Representation? {
        member.representations.first { $0.id == selectedID } ?? member.representations.first(where: \.matches)
    }
    var body: some View {
        VStack(alignment: .leading) {
            Text(member.name).font(.headline)
            Text(member.location).font(.caption).textSelection(.enabled)
            Picker("Representation", selection: $selectedID) {
                Text("Matching representation").tag("")
                ForEach(member.representations) { variant in
                    Text("\(variant.url.lastPathComponent) · \(variant.label) — \(variant.matches ? "Exact match" : "Alternative")").tag(variant.id)
                }
            }.accessibilityIdentifier("duplicateRepresentationPicker")
            if let representation {
                ImagePreview(url: representation.url,
                    title: representation.matches ? "Exact match" : "Alternative representation", accessURL: root)
            }
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
