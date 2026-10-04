import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - ContentView

struct ContentView: View {
    @Binding var project: URL?
    @Environment(ProjectWorkspace.self) private var workspace
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @State private var session = ProjectSession()
    @State private var projectError: String?
    @State private var dropTargeted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    #if DEBUG
        @State private var stressDataset = StressDataset.demo
        @State private var preparingStress = false
        @State private var fixtureError: String?
    #endif

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                if session.root == nil {
                    WelcomeView(notice: projectError ?? session.notice, openProject: pickProject, recents: workspace.recents, reopen: reopenProject)
                } else {
                    NavigationSplitView {
                        VStack(alignment: .leading) {
                            Text(session.root?.lastPathComponent ?? "No project selected")
                                .font(.headline)
                                .padding(.horizontal)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(session.root?.path ?? "Choose a project folder")
                                .accessibilityIdentifier("projectHeading")
                            List(selection: Binding(get: { session.selection }, set: { session.select($0) })) {
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
                                            Label(session.review(for: result.url).outcome?.label ?? "Unreviewed",
                                                  systemImage: session.review(for: result.url).outcome == nil ? "circle" : "checkmark.circle")
                                                .font(.caption)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                            if let notice = session.review(for: result.url).notice {
                                                Text(notice.title).font(.caption).foregroundStyle(.secondary)
                                            }
                                        }
                                        .tag(SidebarSelection.incoming(result.url))
                                        .accessibilityIdentifier("incoming-" + result.url.lastPathComponent)
                                    }
                                }
                            }
                        }
                        .navigationSplitViewColumnWidth(min: 220, ideal: 260)
                    } detail: {
                        if case let .incoming(url) = session.selection,
                           let result = session.results.first(where: { $0.url == url })
                        {
                            ComparisonDetail(result: result, session: session)
                        } else if let root = session.root {
                            if case let .group(id) = session.selection,
                               let group = session.duplicateGroups.first(where: { $0.id == id })
                            {
                                DuplicateInspection(group: group, root: root).id(group.id)
                            } else {
                                ContentUnavailableView(duplicateStatus, systemImage: "photo.on.rectangle.angled",
                                                       description: Text("Choose Images to compare incoming images with this project."))
                            }
                        } else {
                            WelcomeView(notice: projectError ?? session.notice, openProject: pickProject, recents: workspace.recents, reopen: reopenProject)
                        }
                    }
                    .id(session.id)
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
                            .help("Open a project in its own window and discover its image assets.")
                        recentProjectsMenu
                        Button("Choose Images…", systemImage: "photo.badge.plus") { pickImages() }
                            .accessibilityIdentifier("chooseImages")
                            .keyboardShortcut("i")
                            .disabled(session.root == nil)
                            .help(session.root == nil
                                ? Text("Open a project folder first.")
                                : Text("Choose PNG or JPEG images to find exact matches."))
                        if session.canCancel {
                            Button("Cancel Search") { session.cancel() }
                                .help("Stop the search and keep the matches found so far.")
                        }
                    }
                    .frame(maxHeight: .infinity)
                    .clipped()

                    VStack(alignment: .leading) {
                        if let notice = session.notice {
                            Text(notice).foregroundStyle(.orange)
                        }
                        #if DEBUG
                            if let fixtureError {
                                Text(fixtureError).foregroundStyle(.orange)
                            }
                        #endif
                        SessionProgress(session: session)
                    }
                    .padding()
                    .background(.bar)
                    .accessibilityIdentifier("searchFooter")
                }
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
        .environment(session.thumbnails)
        .frame(minWidth: session.root == nil ? 480 : 950,
               maxWidth: session.root == nil ? 480 : .infinity,
               minHeight: session.root == nil ? 600 : 620,
               maxHeight: session.root == nil ? 600 : .infinity)
        #if DEBUG
            .preferredColorScheme(ProcessInfo.processInfo.environment["RUPICK_STRESS_APPEARANCE"] == "light" ? .light : nil)
            .task(id: stressDataset) {
                guard ProcessInfo.processInfo.environment["RUPICK_STRESS_UI"] == "1" else {
                    return
                }

                fixtureError = nil
                preparingStress = true
                defer { preparingStress = false }
                let dataset = stressDataset
                let task = Task.detached(priority: .utility) {
                    let root = try dataset.makeProject()
                    do { return try (root, dataset.makeIncomingImages(in: root)) }
                    catch { try? FileManager.default.removeItem(at: root); throw error }
                }
                do {
                    let (root, incoming) = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
                    guard Task.isCancelled == false else {
                        try? FileManager.default.removeItem(at: root); return
                    }

                    session.openFixture(root: root, incoming: incoming)
                } catch {
                    if Task.isCancelled == false {
                        fixtureError = "Could not prepare fixture data."
                    }
                }
            }
        #endif
            .onChange(of: project, initial: true) { _, identity in
                guard let identity else {
                    return
                }

                do {
                    let restored = try workspace.restore(identity)
                    let restoredSession = workspace.session(for: restored)
                    if session !== restoredSession {
                        session.close()
                        session = restoredSession
                    }
                    if project != restored {
                        project = restored
                    }
                } catch {
                    projectError = "Project unavailable. Choose its folder again to restore access."
                    project = nil
                }
            }
            .onDisappear {
                if let project {
                    workspace.close(project, session: session)
                } else {
                    session.close()
                }
            }
            .alert("Could Not Open Project", isPresented: Binding(get: { projectError != nil && session.root != nil }, set: {
                if $0 == false {
                    projectError = nil
                }
            })) {
                Button("OK") { projectError = nil }
            } message: { Text(projectError ?? "") }
            .navigationTitle(session.root?.lastPathComponent ?? "rupick")
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
        let openingSession = session
        let sessionID = openingSession.id
        let panel = NSOpenPanel()
        panel.title = "Choose a project folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.begin { response in
            guard response == .OK, openingSession.id == sessionID, let url = panel.url else {
                return
            }

            routeProject { try workspace.open(url) }
        }
    }

    private var recentProjectsMenu: some View {
        RecentProjectsMenu(recents: workspace.recents, reopen: reopenProject)
    }

    private func reopenProject(_ recent: RecentProject) {
        routeProject { try workspace.reopen(recent) }
    }

    private func routeProject(_ resolve: () throws -> URL) {
        do {
            let identity = try resolve()
            projectError = nil
            openWindow(value: identity)
            if project == nil {
                dismiss()
            }
        } catch {
            projectError = "Project unavailable. Choose its folder again to restore access."
        }
    }

    private func pickImages() {
        guard let batch = session.beginIncoming(count: 1) else {
            return
        }

        let panel = NSOpenPanel()
        panel.title = "Choose incoming images"
        panel.allowedContentTypes = [.png, .jpeg]
        panel.allowsMultipleSelection = true
        panel.begin { response in
            if response == .OK {
                session.receiveIncoming(panel.urls, batch: batch)
            } else {
                session.abandonIncoming(batch: batch)
            }
        }
    }

    private func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let batch = session.beginIncoming(count: providers.count) else {
            return false
        }

        for (index, provider) in providers.enumerated() {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                let url = data.flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                Task { @MainActor in session.receiveIncoming(url, batch: batch, index: index) }
            }
        }
        return true
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
                    .scaleEffect(reduceMotion || session.state == .complete ? 1 : 0.95)
                    .accessibilityHidden(true)
                    // Completion arrives asynchronously; navigation and review actions remain immediate.
                    .animation(session.state == .complete ? .timingCurve(0.23, 1, 0.32, 1, duration: reduceMotion ? 0.1 : 0.16) : nil, value: session.state)
                Text(session.phase).accessibilityIdentifier("searchStatus")
                Spacer()
                Text("\(session.compared, format: .number) / \(session.discovered, format: .number) assets compared")
                    .monospacedDigit()
                Button("Comparison Details", systemImage: "info.circle") { showLimitations.toggle() }
                    .popover(isPresented: $showLimitations) {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            Text("Exact image comparison").font(.headline)
                            Text("Catalog changes update results automatically while this project is open.")
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
            if session.results.isEmpty == false {
                Text("\(session.reviewedCount, format: .number) of \(session.results.count, format: .number) incoming images reviewed")
                    .font(.caption)
                    .monospacedDigit()
                    .accessibilityIdentifier("reviewProgress")
            }
            if session.isRunning {
                if session.discovered > 0 {
                    ProgressView(value: Double(session.compared), total: Double(session.discovered))
                } else {
                    ProgressView().controlSize(.small)
                }
                Text(session.results.isEmpty ? String(localized: "Results are provisional while the catalog scan runs.") : String(localized: "Results are provisional · \(session.decoded.formatted()) / \(session.results.count.formatted()) incoming images processed"))
                    .font(.caption)
                    .monospacedDigit()
            }
            if let error = session.observationError {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
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

// MARK: - WelcomeView

private struct WelcomeView: View {
    let notice: String?
    let openProject: () -> Void
    let recents: [RecentProject]
    let reopen: (RecentProject) -> Void
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 96, height: 96)
                    .background(.blue.gradient, in: RoundedRectangle(cornerRadius: 22))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22)
                            .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                    }
                    .accessibilityHidden(true)
                VStack(spacing: 4) {
                    Text("rupick").font(.title2.bold())
                    Text("Version \(version)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Button("Open Project…", action: openProject)
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .keyboardShortcut("o")
                .accessibilityIdentifier("openProject")
                .help("Open a project in its own window and discover its image assets.")
            if recents.isEmpty == false {
                RecentProjectsMenu(recents: recents, reopen: reopen)
            }
            VStack(spacing: 8) {
                Text("Find matching images").font(.headline)
                Text("Open a project folder to find exact duplicates in its image assets. Then compare incoming images with the project.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if let notice {
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, minHeight: 180)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
        }
        .frame(maxWidth: 360)
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - RecentProjectsMenu

private struct RecentProjectsMenu: View {
    let recents: [RecentProject]
    let reopen: (RecentProject) -> Void

    var body: some View {
        Menu("Recent Projects", systemImage: "clock") {
            ForEach(recents) { recent in
                Button { reopen(recent) } label: {
                    Text("\(recent.name) · \(recent.id.deletingLastPathComponent().path)")
                }
            }
        }
        .disabled(recents.isEmpty)
        .accessibilityIdentifier("recentProjects")
    }
}

// MARK: - DuplicateInspection

private struct DuplicateInspection: View {
    let group: DuplicateGroup
    let root: URL
    @State private var leftID = ""
    @State private var rightID = ""
    @State private var previewOptions = PreviewOptions()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DuplicateHeader(memberCount: group.members.count)
                PreviewControls(options: $previewOptions)
                HStack(alignment: .top) {
                    DuplicateMemberPanel(members: group.members, root: root, selectedID: $leftID, fallback: group.members[0], previewOptions: previewOptions)
                    DuplicateMemberPanel(members: group.members, root: root, selectedID: $rightID, fallback: group.members[1], previewOptions: previewOptions)
                }
                Text("Participating assets").font(.headline)
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(group.members) { member in DuplicateParticipant(member: member) }
                }
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
    let previewOptions: PreviewOptions
    @State private var choosingMember = false
    @State private var query = ""
    @State private var pendingMemberID: String?
    var body: some View {
        let member = members.first { $0.id == selectedID } ?? fallback
        VStack(alignment: .leading) {
            if members.count == 2 {
                Text(member.name)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(member.name)
                    .textSelection(.enabled)
            } else if members.count <= 50 {
                Picker("Asset", selection: Binding(
                    get: { member.id },
                    set: { selectedID = $0 }
                )) {
                    ForEach(members) { candidate in
                        Text("\(candidate.name) · \(candidate.location)").tag(candidate.id)
                    }
                }
                .help(member.name)
                .accessibilityIdentifier("duplicateMemberPicker")
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
                .accessibilityValue(member.name)
                .help(member.name)
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
            Text(member.location)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(member.location)
                .textSelection(.enabled)
            DuplicateMemberPreview(member: member, root: root, previewOptions: previewOptions).id(member.id)
        }
        .frame(maxWidth: .infinity)
        .onChange(of: member.id, initial: true) { _, id in selectedID = id }
    }
}

// MARK: - DuplicateMemberPreview

private struct DuplicateMemberPreview: View {
    let member: AssetCandidate
    let root: URL
    let previewOptions: PreviewOptions
    @State private var selectedID = ""
    private var representation: Representation? {
        member.representations.first { $0.id == selectedID } ?? member.representations.first(where: \.matches)
    }

    var body: some View {
        VStack(alignment: .leading) {
            Picker("Image file", selection: Binding(
                get: { representation?.id ?? "" },
                set: { selectedID = $0 }
            )) {
                ForEach(member.representations) { variant in
                    Text("\(variant.url.lastPathComponent) · \(variant.label) · \(variant.matches ? "Exact match" : "Alternative")").tag(variant.id)
                }
            }.accessibilityIdentifier("duplicateRepresentationPicker")
            if let representation {
                ImagePreview(url: representation.url,
                             title: representation.matches ? "Exact match" : "Alternative representation", accessURL: root,
                             sharedOptions: previewOptions)
            }
        }
        .onChange(of: representation?.id, initial: true) { _, id in selectedID = id ?? "" }
    }
}

// MARK: - ComparisonDetail

private struct ComparisonDetail: View {
    let result: IncomingResult
    let session: ProjectSession
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(result.url.lastPathComponent).font(.title).accessibilityIdentifier("comparisonHeading")
                if let error = result.error {
                    Text(error).foregroundStyle(.red)
                } else if session.state == .failed {
                    Text("Search failed. Close this project window, then reopen the folder to retry.").foregroundStyle(.red)
                } else {
                    Text(result.statusLabel).accessibilityIdentifier("comparisonStatus")
                }
                ReviewSummary(review: session.review(for: result.url), isRunning: session.isRunning) {
                    session.keepAsNew(result.url)
                }
                HStack(alignment: .top, spacing: 16) {
                    ImagePreview(url: result.url, title: "Incoming")
                    if result.candidates.isEmpty == false {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(result.candidates) { candidate in
                                CandidateInspection(root: session.root, candidate: candidate, incoming: result.url, session: session)
                            }
                        }.frame(maxWidth: .infinity)
                    }
                }
            }.padding()
        }
        .accessibilityIdentifier("comparisonScrollView")
    }
}

// MARK: - ReviewSummary

private struct ReviewSummary: View {
    let review: IncomingReview
    private var outcome: ReviewOutcome? {
        review.outcome
    }

    let isRunning: Bool
    let keepAsNew: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    outcomeLabel
                    Spacer()
                    keepButton
                }
                VStack(alignment: .leading, spacing: 8) {
                    outcomeLabel
                    keepButton
                }
            }
            if let notice = review.notice {
                Text(notice.label)
                    .font(.callout)
                    .accessibilityIdentifier("reviewNotice")
            }
            if case let .reuse(asset) = outcome {
                Text(asset.location).font(.caption).textSelection(.enabled)
                Text("\(asset.representation.url.lastPathComponent) · \(asset.representation.label)")
                    .font(.caption)
                    .textSelection(.enabled)
            }
            Text("Decisions stay in this session. Project files are unchanged.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if isRunning {
                Text("Review when the search finishes.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }

    private var outcomeLabel: some View {
        Label(outcome?.label ?? "Unreviewed", systemImage: outcome == nil ? "circle" : "checkmark.circle.fill")
            .font(.headline)
            .accessibilityIdentifier("reviewOutcome")
    }

    private var keepButton: some View {
        Button("Keep as New", action: keepAsNew)
            .accessibilityIdentifier("keepAsNew")
            .disabled(isRunning)
            .help("Record this image as new, including when exact matches exist.")
    }
}

// MARK: - CandidateInspection

private struct CandidateInspection: View {
    let root: URL?
    let candidate: AssetCandidate
    let incoming: URL
    let session: ProjectSession
    private var representation: Representation? {
        candidate.representations.first(where: { $0.id == session.review(for: incoming).representationIDs[candidate.id] }) ??
            candidate.representations.first(where: \.matches)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(candidate.name)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(candidate.name)
            Text(candidate.location)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(candidate.location)
                .textSelection(.enabled)
            Picker("Representation", selection: Binding(
                get: { representation?.id ?? "" }, set: {
                    session.selectRepresentation(for: incoming, candidateID: candidate.id, representationID: $0)
                }
            )) {
                ForEach(candidate.representations) { variant in
                    Text("\(variant.url.lastPathComponent) · \(variant.label) · \(variant.matches ? "Exact match" : "Alternative")").tag(variant.id)
                }
            }.accessibilityIdentifier("representationPicker")
            if let representation {
                ImagePreview(url: representation.url, title: representation.matches ? "Exact match" : "Alternative representation", accessURL: root)
                Button("Reuse This Asset") {
                    session.reuseAsset(for: incoming, candidateID: candidate.id, representationID: representation.id)
                }
                .accessibilityIdentifier("reuseAsset")
                .disabled(session.isRunning || representation.matches == false)
                .help(representation.matches ? Text("Record this asset and matching image file for the session.") : Text("Choose an exact matching representation to reuse this asset."))
            }
        }
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - PreviewOptions

private struct PreviewOptions {
    var background = PreviewBackground.checkerboard
    var actualSize = false
    var zoom: Double = 1
}

// MARK: - PreviewControls

private struct PreviewControls: View {
    @Binding var options: PreviewOptions

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                backgroundPicker
                sizeControls
            }
            VStack(alignment: .leading, spacing: 8) {
                backgroundPicker
                sizeControls
            }
        }
    }

    private var backgroundPicker: some View {
        Picker("Background", selection: $options.background) {
            ForEach(PreviewBackground.allCases) { style in Text(style.title).tag(style) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel("Preview background")
        .frame(width: 180)
    }

    private var sizeControls: some View {
        HStack {
            Toggle("Actual Size", isOn: $options.actualSize)
                .toggleStyle(.button)
                .help("Inspect one image pixel per display pixel; zoom up to 4×.")
            if options.actualSize {
                Slider(value: $options.zoom, in: 1 ... 4, step: 0.25)
                    .accessibilityLabel("Preview zoom")
                    .frame(width: 120)
                Text(options.zoom, format: .number.precision(.fractionLength(2)))
                    .monospacedDigit()
                    .font(.caption)
            }
        }
    }
}

// MARK: - ImagePreview

private struct ImagePreview: View {
    let url: URL
    let title: String
    var accessURL: URL?
    var sharedOptions: PreviewOptions?
    @Environment(ThumbnailStore.self) private var thumbnails
    @State private var loaded: Thumbnail?
    @State private var failedURL: URL?
    @State private var localOptions = PreviewOptions()
    @Environment(\.displayScale) private var displayScale

    private struct PreviewRequest: Hashable {
        let url: URL
        let actualSize: Bool
        let storeID: UUID
    }

    var body: some View {
        let options = sharedOptions ?? localOptions
        let background = options.background
        let actualSize = options.actualSize
        let zoom = options.zoom
        VStack(spacing: 8) {
            Text(title).font(.subheadline)
            if sharedOptions == nil {
                PreviewControls(options: $localOptions)
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
            if loaded?.url != url {
                loaded = nil
            }
            failedURL = nil
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
