import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - ContentView

struct ContentView: View {
    @State private var session = ProjectSession()
    @State private var selectedIncoming: URL?
    @State private var selectedGroup: String?
    @State private var projectAccess: URL?
    @State private var incomingAccess = [URL]()
    @State private var dropNotice: String?
    @State private var dropTargeted = false
    @State private var thumbnails = ThumbnailStore()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    #if DEBUG
        @State private var stressDataset = StressDataset.demo
        @State private var stressRoot: URL?
        @State private var preparingStress = false
    #endif

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                NavigationSplitView {
                    VStack(alignment: .leading) {
                        Text(session.root?.lastPathComponent ?? "No project selected")
                            .font(.headline)
                            .padding(.horizontal)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(session.root?.path ?? "Choose a project folder")
                            .accessibilityIdentifier("projectHeading")
                        Button("Project Duplicates") { selectedIncoming = nil }
                            .accessibilityIdentifier("projectDuplicates")
                            .padding(.horizontal)
                        List(selection: sidebarSelection) {
                            Section("Project Duplicates") {
                                ForEach(session.duplicateGroups) { group in
                                    VStack(alignment: .leading) {
                                        Text("\(group.members.count) assets with equal content")
                                        Text(group.members.prefix(2).map(\.name).joined(separator: ", ") +
                                            (group.members.count > 2 ? " +\(group.members.count - 2) more" : ""))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                    .tag(SidebarSelection.group(group.id))
                                    .accessibilityIdentifier("duplicateGroup")
                                }
                            }
                            Section("Incoming Images") {
                                ForEach(session.results) { result in
                                    VStack(alignment: .leading) {
                                        Text(result.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                                        Text(result.url.deletingLastPathComponent().path)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                            .help(result.url.path)
                                        Text(result.statusLabel).font(.caption).foregroundStyle(.secondary)
                                    }
                                    .tag(SidebarSelection.incoming(result.url))
                                    .accessibilityIdentifier("incoming-" + result.url.lastPathComponent)
                                }
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
                .toolbar {
                    #if DEBUG
                        if ProcessInfo.processInfo.environment["RUPICK_STRESS_UI"] == "1" {
                            Picker("Fixture data", selection: $stressDataset) {
                                ForEach(StressDataset.allCases) { dataset in Text(dataset.title).tag(dataset) }
                            }
                            .accessibilityIdentifier("stressDatasetPicker")
                            .disabled(preparingStress)
                        }
                    #endif
                    Button("Open Project…", systemImage: "folder") { pickProject() }
                        .accessibilityIdentifier("openProject")
                        .keyboardShortcut("o")
                        .help("Choose a project folder and discover its image assets.")
                    Button("Choose Images…", systemImage: "photo.badge.plus") { pickImages() }
                        .accessibilityIdentifier("chooseImages")
                        .keyboardShortcut("i")
                        .disabled(session.root == nil)
                        .help(session.root == nil
                            ? Text("Open a project folder first.")
                            : Text("Choose PNG or JPEG images to find exact matches."))
                    if session.isRunning {
                        Button("Cancel Search") { session.cancel() }
                            .help("Stop the search and keep the matches found so far.")
                    }
                }
                .frame(maxHeight: .infinity)
                .clipped()

                VStack(alignment: .leading) {
                    if let dropNotice {
                        Text(dropNotice).foregroundStyle(.orange)
                    }
                    SessionProgress(session: session)
                }
                .padding()
                .background(.bar)
                .accessibilityIdentifier("searchFooter")
            }
            // Reapply the measured toolbar inset once, keeping both columns below it.
            .padding(.top, geometry.safeAreaInsets.top)
        }
        // Measure the full window; the stack above owns the top inset and footer space.
        .ignoresSafeArea(.container, edges: .top)
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.tint, lineWidth: 3)
                .padding(6)
                .opacity(dropTargeted ? 1 : 0)
                .allowsHitTesting(false)
                .animation(dropTargeted ? nil : .timingCurve(0.23, 1, 0.32, 1, duration: reduceMotion ? 0.1 : 0.125), value: dropTargeted)
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted, perform: acceptDrop)
        .environment(thumbnails)
        .onChange(of: session.duplicateGroups.map(\.id)) { _, ids in
            if let selectedGroup, ids.contains(selectedGroup) == false {
                self.selectedGroup = ids.first
            }
        }
        .frame(minWidth: 950, minHeight: 620)
        #if DEBUG
            .task(id: stressDataset) {
                guard ProcessInfo.processInfo.environment["RUPICK_STRESS_UI"] == "1" else {
                    return
                }

                preparingStress = true
                defer { preparingStress = false }
                let dataset = stressDataset
                let task = Task.detached(priority: .utility) { try dataset.makeProject() }
                do {
                    let root = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
                    guard Task.isCancelled == false else {
                        try? FileManager.default.removeItem(at: root); return
                    }

                    session.cancel()
                    releaseAccess()
                    if let stressRoot {
                        try? FileManager.default.removeItem(at: stressRoot)
                    }
                    stressRoot = root
                    thumbnails = ThumbnailStore()
                    selectedIncoming = nil; selectedGroup = nil; dropNotice = nil
                    session.start(root: root, incoming: [])
                } catch {
                    if Task.isCancelled == false {
                        dropNotice = "Could not prepare fixture data."
                    }
                }
            }
        #endif
            .onDisappear {
                session.cancel()
                releaseAccess()
                thumbnails = ThumbnailStore()
                #if DEBUG
                    if let stressRoot {
                        try? FileManager.default.removeItem(at: stressRoot)
                    }
                #endif
            }
    }

    private enum SidebarSelection: Hashable {
        case group(String)
        case incoming(URL)
    }

    private var sidebarSelection: Binding<SidebarSelection?> {
        Binding(get: {
            if let selectedIncoming {
                return .incoming(selectedIncoming)
            }
            if let id = selectedGroup ?? session.duplicateGroups.first?.id {
                return .group(id)
            }
            return nil
        }, set: { selection in
            switch selection {
            case let .group(id):
                selectedGroup = id; selectedIncoming = nil

            case let .incoming(url):
                selectedIncoming = url

            case nil:
                break
            }
        })
    }

    private var duplicateStatus: String {
        if session.isRunning {
            return "Looking for exact duplicates…"
        }
        if session.state == .failed {
            return "Duplicate scan failed"
        }
        if session.isIncomplete {
            return "Incomplete scan · no exact duplicates found so far"
        }
        return "No exact duplicates found"
    }

    private func pickProject() {
        let panel = NSOpenPanel()
        panel.title = "Choose a project folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                return
            }

            session.cancel()
            releaseAccess()
            thumbnails = ThumbnailStore()
            if url.startAccessingSecurityScopedResource() {
                projectAccess = url
            }
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
            guard response == .OK else {
                return
            }

            dropNotice = nil
            addImages(panel.urls)
        }
    }

    private func addImages(_ urls: [URL]) {
        guard let root = session.root else {
            return
        }

        let images = urls.filter { url in
            guard url.isFileURL, let type = UTType(filenameExtension: url.pathExtension) else {
                return false
            }

            return type.conforms(to: .png) || type.conforms(to: .jpeg)
        }
        if images.count != urls.count {
            dropNotice = "Some files were not added. Choose PNG or JPEG files."
        }
        let existing = session.results.map(\.url)
        var seen = Set(existing)
        let added = images.filter { seen.insert($0).inserted }
        guard added.isEmpty == false else {
            return
        }

        for url in added where url.startAccessingSecurityScopedResource() {
            incomingAccess.append(url)
        }
        thumbnails = ThumbnailStore()
        session.start(root: root, incoming: existing + added)
        if selectedIncoming == nil {
            selectedIncoming = added.first
        }
    }

    private func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        guard session.root != nil else {
            dropNotice = "Open a project folder before dropping images."
            return false
        }

        dropNotice = nil
        let root = session.root
        let batch = IncomingDropBatch(count: providers.count) { urls in
            guard session.root == root else {
                return
            }

            if urls.count != providers.count {
                dropNotice = "Some dropped files could not be opened. Use Choose Images to try again."
            }
            addImages(urls)
        }
        for (index, provider) in providers.enumerated() {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                let url = data.flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                Task { @MainActor in batch.receive(url, at: index) }
            }
        }
        return providers.isEmpty == false
    }

    private func releaseAccess() {
        projectAccess?.stopAccessingSecurityScopedResource()
        projectAccess = nil
        incomingAccess.forEach { $0.stopAccessingSecurityScopedResource() }
        incomingAccess = []
    }
}

// MARK: - SessionProgress

private struct SessionProgress: View {
    let session: ProjectSession
    @State private var showLimitations = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .opacity(session.state == .complete && session.isIncomplete == false ? 1 : 0)
                    .accessibilityHidden(true)
                    .animation(.timingCurve(0.23, 1, 0.32, 1, duration: reduceMotion ? 0.1 : 0.16), value: session.state)
                Text(session.phase).accessibilityIdentifier("searchStatus")
                Spacer()
                Text("\(session.compared, format: .number) / \(session.discovered, format: .number) assets compared")
                    .monospacedDigit()
                Button("Comparison Details", systemImage: "info.circle") { showLimitations.toggle() }
                    .popover(isPresented: $showLimitations) {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            Text("Exact image comparison").font(.headline)
                            Text("Equal content does not mean assets are interchangeable or safe to delete. Project files are read only.")
                            Text("Exact matches only. Resized copies and images with changed transparent padding are not detected. No matches does not guarantee an image is safe to import.")
                        }
                        .padding()
                        .frame(width: 360)
                    }
            }
            Text(session.duplicateGroups.count == 1 ? String(localized: "1 exact duplicate group") : String(localized: "\(session.duplicateGroups.count.formatted()) exact duplicate groups"))
                .font(.caption)
                .monospacedDigit()
                .accessibilityIdentifier("duplicateGroupCount")
            if session.isRunning {
                if session.discovered > 0 {
                    ProgressView(value: Double(session.compared), total: Double(session.discovered))
                } else {
                    ProgressView().controlSize(.small)
                }
                Text("Results are provisional · \(session.decoded, format: .number) / \(session.results.count, format: .number) incoming images processed")
                    .font(.caption)
                    .monospacedDigit()
            }
            if let error = session.error {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            }
            if session.skipped > 0 {
                Text("Incomplete scan: \(session.skipped) unreadable or unsupported catalog entries or images were skipped.")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
        }
    }
}

// MARK: - DuplicateInspection

private struct DuplicateInspection: View {
    let group: DuplicateGroup
    let root: URL
    @State private var leftID = ""
    @State private var rightID = ""

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                DuplicateHeader(memberCount: group.members.count)
                HStack(alignment: .top) {
                    DuplicateMemberPanel(members: group.members, root: root, selectedID: $leftID, fallback: group.members[0])
                    DuplicateMemberPanel(members: group.members, root: root, selectedID: $rightID, fallback: group.members[1])
                }
                Text("Participating assets").font(.headline)
                ForEach(group.members) { member in DuplicateParticipant(member: member) }
            }.padding()
        }
        .accessibilityIdentifier("duplicateScrollView")
    }
}

// MARK: - DuplicateHeader

private struct DuplicateHeader: View {
    let memberCount: Int
    var body: some View {
        VStack(alignment: .leading) {
            Text("Exact duplicate content").font(.title)
            Text("\(memberCount) distinct assets participate in this group.")
        }
    }
}

// MARK: - DuplicateParticipant

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

// MARK: - DuplicateMemberPanel

private struct DuplicateMemberPanel: View {
    let members: [AssetCandidate]
    let root: URL
    @Binding var selectedID: String
    let fallback: AssetCandidate
    @State private var choosingMember = false
    @State private var query = ""
    @State private var pendingMemberID: String?
    var body: some View {
        let member = members.first { $0.id == selectedID } ?? fallback
        VStack(alignment: .leading) {
            if members.count <= 50 {
                Picker("Asset", selection: Binding(
                    get: { member.id },
                    set: { selectedID = $0 }
                )) {
                    ForEach(members) { candidate in
                        Text("\(candidate.name) · \(candidate.location)").tag(candidate.id)
                    }
                }.accessibilityIdentifier("duplicateMemberPicker")
            } else {
                Button {
                    pendingMemberID = member.id
                    query = ""
                    choosingMember = true
                } label: {
                    Label(member.name, systemImage: "chevron.up.chevron.down")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .accessibilityLabel("Choose asset")
                .help(member.location)
                .sheet(isPresented: $choosingMember) {
                    VStack {
                        Text("Choose an asset").font(.headline)
                        let filtered = members.filter { query.isEmpty || $0.name.localizedStandardContains(query) || $0.location.localizedStandardContains(query) }
                        List(filtered, selection: $pendingMemberID) { candidate in
                            VStack(alignment: .leading) {
                                Text(candidate.name)
                                Text(candidate.location).font(.caption).foregroundStyle(.secondary)
                            }.tag(candidate.id)
                        }
                        .searchable(text: $query, prompt: "Name or location")
                        .onChange(of: query) { _, _ in pendingMemberID = nil }
                        HStack {
                            Button("Cancel") { choosingMember = false }.keyboardShortcut(.cancelAction)
                            Button("Choose") {
                                if let pendingMemberID {
                                    selectedID = pendingMemberID
                                }
                                choosingMember = false
                            }
                            .disabled(pendingMemberID == nil)
                            .keyboardShortcut(.defaultAction)
                        }
                    }
                    .padding()
                    .frame(minWidth: 500, minHeight: 400)
                }
            }
            DuplicateMemberPreview(member: member, root: root).id(member.id)
        }.frame(maxWidth: .infinity)
    }
}

// MARK: - DuplicateMemberPreview

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

// MARK: - ComparisonDetail

private struct ComparisonDetail: View {
    let result: IncomingResult
    let root: URL?
    let searchFailed: Bool
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                Text(result.url.lastPathComponent).font(.title).accessibilityIdentifier("comparisonHeading")
                if let error = result.error {
                    Text(error).foregroundStyle(.red)
                } else if searchFailed {
                    Text("Search failed. Open the project folder again to retry.").foregroundStyle(.red)
                } else {
                    Text(result.statusLabel).accessibilityIdentifier("comparisonStatus")
                }
                HStack(alignment: .top, spacing: 16) {
                    ImagePreview(url: result.url, title: "Incoming")
                    if result.candidates.isEmpty == false {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(result.candidates) { candidate in
                                CandidateInspection(root: root, candidate: candidate)
                            }
                        }.frame(maxWidth: .infinity)
                    }
                }
            }.padding()
        }
        .accessibilityIdentifier("comparisonScrollView")
    }
}

// MARK: - CandidateInspection

private struct CandidateInspection: View {
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
                get: { representation?.id ?? "" }, set: { selectedRepresentation = $0 }
            )) {
                ForEach(candidate.representations) { variant in
                    Text("\(variant.url.lastPathComponent) · \(variant.label) — \(variant.matches ? "Exact match" : "Alternative")").tag(variant.id)
                }
            }.accessibilityIdentifier("representationPicker")
            if let representation {
                HStack(alignment: .top, spacing: 16) {
                    ImagePreview(url: representation.url, title: representation.matches ? "Exact match" : "Alternative representation", accessURL: root)
                }
            }
        }
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - ImagePreview

private struct ImagePreview: View {
    let url: URL
    let title: String
    var accessURL: URL?
    @Environment(ThumbnailStore.self) private var thumbnails
    @State private var loaded: Thumbnail?
    @State private var failedURL: URL?
    @State private var background = PreviewBackground.checkerboard
    @State private var actualSize = false
    @State private var zoom: Double = 1
    @Environment(\.displayScale) private var displayScale

    private struct PreviewRequest: Hashable {
        let url: URL
        let actualSize: Bool
        let storeID: UUID
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(title).font(.subheadline)
            VStack(spacing: 6) {
                Picker("Background", selection: $background) {
                    ForEach(PreviewBackground.allCases) { style in Text(style.title).tag(style) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Preview background")
                HStack {
                    Toggle("Actual Size", isOn: $actualSize)
                        .toggleStyle(.button)
                        .help("Inspect one image pixel per display pixel; zoom up to 4×.")
                    if actualSize {
                        Slider(value: $zoom, in: 1 ... 4, step: 0.25).accessibilityLabel("Preview zoom")
                        Text(zoom, format: .number.precision(.fractionLength(2))).monospacedDigit().font(.caption)
                    }
                }
            }
            ZStack {
                PreviewBackdrop(style: background)
                if let loaded, loaded.url == url {
                    if actualSize {
                        ScrollView([.horizontal, .vertical]) {
                            Image(nsImage: loaded.image)
                                .resizable()
                                .interpolation(.none)
                                .frame(width: CGFloat(loaded.width) * zoom / displayScale, height: CGFloat(loaded.height) * zoom / displayScale)
                        }
                    } else {
                        Image(nsImage: loaded.image).resizable().scaledToFit().padding(12)
                    }
                } else if failedURL == url {
                    Label("Preview unavailable", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(background == .dark ? .white : .black)
                } else {
                    ProgressView("Loading preview…")
                        .controlSize(.small)
                        .tint(background == .dark ? .white : .black)
                        .foregroundStyle(background == .dark ? .white : .black)
                }
            }
            .frame(height: 230)
            .clipped()
            Text(loaded.map { "\($0.width.formatted()) × \($0.height.formatted()) pixels" } ?? " ")
                .font(.caption)
                .monospacedDigit()
            Text(url.lastPathComponent)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(url.path)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity)
        .task(id: PreviewRequest(url: url, actualSize: actualSize, storeID: thumbnails.id)) {
            loaded = nil; failedURL = nil
            let value = await thumbnails.load(url: url, scope: accessURL ?? url, fullSize: actualSize)
            guard Task.isCancelled == false else {
                return
            }

            loaded = value
            if value == nil {
                failedURL = url
            }
        }
    }
}

// MARK: - IncomingDropBatch

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
        if remaining == 0 {
            completion(urls.compactMap { $0 })
        }
    }
}
