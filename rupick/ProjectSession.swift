import Foundation
import Observation
import UniformTypeIdentifiers

// MARK: - Representation

struct Representation: Identifiable, Sendable, Equatable {
    let id: String
    let url: URL
    let label: String
    let matches: Bool
}

// MARK: - AssetCandidate

struct AssetCandidate: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let location: String
    let representations: [Representation]
}

// MARK: - DuplicateGroup

struct DuplicateGroup: Identifiable, Sendable, Equatable {
    let id: String
    var members: [AssetCandidate]
}

// MARK: - ComparisonStatus

enum ComparisonStatus: Sendable {
    case waiting
    case decoding
    case comparing
    case complete
    case incomplete
    case unreadable
}

// MARK: - SearchState

enum SearchState: Sendable {
    case idle
    case running
    case complete
    case cancelled
    case failed
}

// MARK: - IncomingResult

struct IncomingResult: Identifiable, Sendable, Equatable {
    var id: URL {
        url
    }

    let url: URL
    var candidates = [AssetCandidate]()
    var error: String?
    var status = ComparisonStatus.waiting

    var statusText: String {
        String(localized: statusLabel)
    }

    var statusLabel: LocalizedStringResource {
        switch status {
        case .waiting:
            return "Waiting for catalog scan…"

        case .decoding:
            return "Reading image…"

        case .comparing:
            if candidates.count == 1 {
                return "Comparing · 1 provisional match"
            }
            return "Comparing · \(candidates.count.formatted()) provisional matches"

        case .unreadable:
            return "Image unavailable"

        case .incomplete:
            if candidates.count == 1 {
                return "Incomplete search · 1 match so far"
            }
            return "Incomplete search · \(candidates.count.formatted()) matches so far"

        case .complete:
            switch candidates.count {
            case 0:
                return "No matches found"

            case 1:
                return "1 exact match"

            default:
                return "\(candidates.count.formatted()) exact matches"
            }
        }
    }
}

// MARK: - ReusedAsset

struct ReusedAsset: Sendable, Equatable {
    let candidateID: String
    let name: String
    let location: String
    let representation: Representation
}

// MARK: - ReviewOutcome

enum ReviewOutcome: Sendable, Equatable {
    case keepAsNew
    case reuse(ReusedAsset)

    static func reuse(candidate: AssetCandidate, representation: Representation) -> Self {
        .reuse(ReusedAsset(candidateID: candidate.id, name: candidate.name,
                           location: candidate.location, representation: representation))
    }

    var label: LocalizedStringResource {
        switch self {
        case .keepAsNew:
            "Reviewed · Keep as new"

        case let .reuse(asset):
            "Reviewed · Reuse \(asset.name)"
        }
    }
}

// MARK: - IncomingReview

struct IncomingReview: Sendable, Equatable {
    var outcome: ReviewOutcome?
    var representationIDs = [String: String]()
}

// MARK: - ScanSnapshot

struct ScanSnapshot: Sendable {
    var results: [IncomingResult]
    var duplicateGroups = [DuplicateGroup]()
    var discovered = 0
    var compared = 0
    var decoded = 0
    var skipped = 0
    var phase = "Discovering image assets…"
    var error: String?
}

// MARK: - SidebarSelection

enum SidebarSelection: Hashable {
    case group(String)
    case incoming(URL)
}

// MARK: - ProjectSession

@MainActor @Observable
final class ProjectSession {
    struct Dependencies: Sendable {
        let access: FileAccessAdapter
        let scan: @Sendable (URL, [URL], @escaping @Sendable (ScanSnapshot) async -> Void) async -> Void

        static let native = Dependencies(access: .native, scan: { root, incoming, publish in
            await CatalogComparison.run(root: root, incoming: incoming, publish: publish)
        })
    }

    private struct IncomingBatch {
        let id: UUID
        var urls: [URL?]
        var remaining: Set<Int>
        var access = [URL: FileAccessLease]()
    }

    private(set) var root: URL?
    private(set) var results = [IncomingResult]()
    private(set) var reviews = [URL: IncomingReview]()
    private(set) var duplicateGroups = [DuplicateGroup]()
    private(set) var state = SearchState.idle
    private(set) var thumbnails: ThumbnailStore
    private(set) var notice: String?
    private(set) var selection: SidebarSelection?
    /// Also resets view-local inspection state when the same folder is reopened.
    private(set) var id = UUID()

    var isRunning: Bool {
        state == .running
    }

    var isIncomplete: Bool {
        skipped > 0 || state == .cancelled || state == .failed
    }

    private(set) var hasPendingIncoming = false
    var canCancel: Bool {
        isRunning || hasPendingIncoming
    }

    private(set) var discovered = 0
    private(set) var compared = 0
    private(set) var decoded = 0
    private(set) var skipped = 0
    private(set) var phase = "Choose a project folder to begin."
    private(set) var error: String?
    @ObservationIgnored private let dependencies: Dependencies
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var workers = [UUID: Task<Void, Never>]()
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var latestSnapshot: ScanSnapshot?
    @ObservationIgnored private var projectAccess: FileAccessLease?
    @ObservationIgnored private var incomingAccess = [URL: FileAccessLease]()
    @ObservationIgnored private var batches = [IncomingBatch]()
    @ObservationIgnored private var temporaryRoot: URL?
    @ObservationIgnored private var retiredPreviews = [Task<Void, Never>]()
    @ObservationIgnored private var cleanup: Task<Void, Never>?

    init(dependencies: Dependencies = .native) {
        self.dependencies = dependencies
        thumbnails = ThumbnailStore(access: dependencies.access)
    }

    deinit {
        workers.values.forEach { $0.cancel() }
    }

    var reviewedCount: Int {
        results.count { reviews[$0.url]?.outcome != nil }
    }

    func review(for incoming: URL) -> IncomingReview {
        reviews[incoming] ?? IncomingReview()
    }

    func selectRepresentation(for incoming: URL, candidateID: String, representationID: String) {
        guard results.first(where: { $0.url == incoming })?.candidates.contains(where: {
            $0.id == candidateID && $0.representations.contains(where: { $0.id == representationID })
        }) == true else {
            return
        }

        reviews[incoming, default: IncomingReview()].representationIDs[candidateID] = representationID
    }

    @discardableResult
    func reuseAsset(for incoming: URL, candidateID: String, representationID: String) -> Bool {
        guard isRunning == false,
              let result = results.first(where: { $0.url == incoming }), result.error == nil,
              let candidate = result.candidates.first(where: { $0.id == candidateID }),
              let representation = candidate.representations.first(where: { $0.id == representationID && $0.matches })
        else {
            return false
        }

        reviews[incoming, default: IncomingReview()].outcome = .reuse(candidate: candidate, representation: representation)
        selectRepresentation(for: incoming, candidateID: candidateID, representationID: representationID)
        return true
    }

    func keepAsNew(_ incoming: URL) {
        guard isRunning == false, results.contains(where: { $0.url == incoming }) else {
            return
        }

        reviews[incoming, default: IncomingReview()].outcome = .keepAsNew
    }

    @discardableResult
    func open(root: URL, incoming: [URL] = [], replacing sessionID: UUID? = nil) -> Task<Void, Never> {
        guard sessionID == nil || sessionID == id else {
            return Task {}
        }

        close()
        self.root = root
        projectAccess = FileAccessLease(urls: [root], adapter: dependencies.access)
        return refresh(incoming: incoming)
    }

    #if DEBUG
        @discardableResult
        func openFixture(root: URL, incoming: [URL] = []) -> Task<Void, Never> {
            let work = open(root: root, incoming: incoming)
            temporaryRoot = root
            return work
        }
    #endif

    /// Refresh is also used by real-file comparison fixtures and the validation executable.
    @discardableResult
    func refresh(incoming: [URL]) -> Task<Void, Never> {
        guard let root else {
            return Task {}
        }

        retiredPreviews.append(thumbnails.close())
        thumbnails = ThumbnailStore(access: dependencies.access)
        worker?.cancel()
        var seen = Set<URL>()
        let incoming = incoming.filter { seen.insert($0).inserted }
        for url in incoming where incomingAccess[url] == nil {
            incomingAccess[url] = FileAccessLease(urls: [url], adapter: dependencies.access)
        }
        incomingAccess = incomingAccess.filter { seen.contains($0.key) }
        let token = UUID()
        generation = token
        latestSnapshot = nil
        let previous = Dictionary(uniqueKeysWithValues: results.map { ($0.url, $0) })
        results = incoming.map { previous[$0] ?? IncomingResult(url: $0) }
        for index in results.indices where previous[results[index].url] != nil && results[index].error == nil {
            results[index].status = .comparing
        }
        if selection == nil, let first = incoming.first {
            selection = .incoming(first)
        }
        discovered = 0; compared = 0; decoded = 0; skipped = 0; error = nil
        phase = "Discovering image assets…"
        state = .running
        // Acquire before scheduling: a close can release window grants before the worker starts.
        let access = FileAccessLease(urls: [root] + incoming, adapter: dependencies.access)
        let scan = dependencies.scan
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            defer { access.release() }
            let publisher = ScanPublisher { [weak self] snapshot in
                await self?.receive(snapshot, token: token)
            }
            await scan(root, incoming) { snapshot in await publisher.receive(snapshot) }
            await publisher.finish()
            access.release()
            await self?.finish(token: token)
        }
        worker = task
        workers[token] = task
        return task
    }

    func select(_ selection: SidebarSelection?) {
        guard let selection else {
            return
        }

        switch selection {
        case let .incoming(url):
            guard results.contains(where: { $0.url == url }) else {
                return
            }

        case let .group(id):
            guard duplicateGroups.contains(where: { $0.id == id }) else {
                return
            }
        }
        self.selection = selection
    }

    /// Register at submission, before picker or provider callbacks can complete.
    func beginIncoming(count: Int) -> UUID? {
        guard root != nil else {
            notice = "Open a project folder before dropping images."
            return nil
        }

        guard count > 0 else {
            return nil
        }

        notice = nil
        let id = UUID()
        batches.append(IncomingBatch(id: id, urls: Array(repeating: nil, count: count), remaining: Set(0 ..< count)))
        hasPendingIncoming = true
        return id
    }

    @discardableResult
    func receiveIncoming(_ urls: [URL], batch: UUID) -> Task<Void, Never>? {
        guard let index = batches.firstIndex(where: { $0.id == batch }) else {
            return nil
        }

        // A picker registers a single slot before its final selection count is known.
        guard batches[index].remaining.isEmpty == false else {
            return nil
        }

        batches[index].urls = urls.map { Optional($0) }
        batches[index].remaining = []
        for url in urls where batches[index].access[url] == nil {
            batches[index].access[url] = FileAccessLease(urls: [url], adapter: dependencies.access)
        }
        return drainIncoming()
    }

    @discardableResult
    func receiveIncoming(_ url: URL?, batch: UUID, index: Int) -> Task<Void, Never>? {
        guard let batchIndex = batches.firstIndex(where: { $0.id == batch }),
              batches[batchIndex].remaining.remove(index) != nil
        else {
            return nil
        }

        batches[batchIndex].urls[index] = url
        if let url, batches[batchIndex].access[url] == nil {
            batches[batchIndex].access[url] = FileAccessLease(urls: [url], adapter: dependencies.access)
        }
        return drainIncoming()
    }

    @discardableResult
    func abandonIncoming(batch: UUID) -> Task<Void, Never>? {
        guard let index = batches.firstIndex(where: { $0.id == batch }) else {
            return nil
        }

        batches.remove(at: index)
        return drainIncoming()
    }

    private func drainIncoming() -> Task<Void, Never>? {
        var incoming = results.map(\.url)
        var seen = Set(incoming)
        var added = [URL]()
        var rejected = false
        var settled = false
        while let first = batches.first, first.remaining.isEmpty {
            let batch = batches.removeFirst()
            settled = true
            for url in batch.urls {
                guard let url, url.isFileURL,
                      let type = UTType(filenameExtension: url.pathExtension),
                      type.conforms(to: .png) || type.conforms(to: .jpeg)
                else {
                    rejected = true
                    continue
                }

                if seen.insert(url).inserted {
                    incoming.append(url)
                    added.append(url)
                    incomingAccess[url] = batch.access[url]
                }
            }
        }
        hasPendingIncoming = batches.isEmpty == false
        if settled {
            notice = rejected ? "Some files were not added. Choose PNG or JPEG files, or use Choose Images to try again." : nil
        }
        guard added.isEmpty == false else {
            return nil
        }

        return refresh(incoming: incoming)
    }

    func cancel() {
        guard canCancel else {
            return
        }

        batches = []
        hasPendingIncoming = false
        worker?.cancel()
        worker = nil
        generation = UUID()
        latestSnapshot = nil
        state = .cancelled
        markResultsIncomplete()
        phase = "Search cancelled. Results are incomplete."
    }

    /// Returns when retired workers and previews have released their own grants.
    @discardableResult
    func close() -> Task<Void, Never> {
        worker?.cancel()
        workers.values.forEach { $0.cancel() }
        let retiring = Array(workers.values)
        workers = [:]
        worker = nil
        generation = UUID()
        id = UUID()
        batches = []
        hasPendingIncoming = false
        latestSnapshot = nil
        projectAccess?.release()
        projectAccess = nil
        incomingAccess.values.forEach { $0.release() }
        incomingAccess = [:]
        let previews = retiredPreviews + [thumbnails.close()]
        retiredPreviews = []
        thumbnails = ThumbnailStore(access: dependencies.access)
        let temporary = temporaryRoot
        temporaryRoot = nil
        root = nil; results = []; reviews = [:]; duplicateGroups = []; selection = nil; notice = nil
        state = .idle
        discovered = 0; compared = 0; decoded = 0; skipped = 0; error = nil
        phase = "Choose a project folder to begin."
        let previousCleanup = cleanup
        let task = Task { [weak self] in
            await previousCleanup?.value
            for task in retiring {
                await task.value
            }
            for preview in previews {
                await preview.value
            }
            if let temporary {
                if self?.root == temporary {
                    // A fixture folder may have been explicitly reopened while retiring.
                    self?.temporaryRoot = temporary
                } else {
                    try? FileManager.default.removeItem(at: temporary)
                }
            }
        }
        cleanup = task
        return task
    }

    private func receive(_ snapshot: ScanSnapshot, token: UUID) {
        guard token == generation else {
            return
        }

        latestSnapshot = snapshot
        let previous = Dictionary(uniqueKeysWithValues: results.map { ($0.url, $0) })
        // A partial scan cannot yet establish that inspected content has disappeared.
        // Completion replaces this provisional union with the authoritative snapshot.
        results = snapshot.results.map { update in
            guard update.error == nil, let retained = previous[update.url] else {
                return update
            }

            var result = update
            result.candidates = retainingInspection(in: update.candidates, from: retained.candidates)
            if result.candidates != update.candidates {
                result.status = .comparing
            }
            return result
        }
        for group in snapshot.duplicateGroups {
            if let index = duplicateGroups.firstIndex(where: { $0.id == group.id }) {
                duplicateGroups[index].members = retainingInspection(in: group.members, from: duplicateGroups[index].members)
            } else {
                duplicateGroups.append(group)
            }
        }
        reconcileSelection()
        discovered = snapshot.discovered
        compared = snapshot.compared
        decoded = snapshot.decoded
        skipped = snapshot.skipped
        phase = snapshot.phase
        error = snapshot.error
    }

    private func retainingInspection(in updates: [AssetCandidate], from previous: [AssetCandidate]) -> [AssetCandidate] {
        let updated = Dictionary(uniqueKeysWithValues: updates.map { ($0.id, $0) })
        let previousIDs = Set(previous.map(\.id))
        return previous.map { candidate in
            guard let update = updated[candidate.id] else {
                return candidate
            }

            let representations = Dictionary(uniqueKeysWithValues: update.representations.map { ($0.id, $0) })
            let previousRepresentationIDs = Set(candidate.representations.map(\.id))
            return AssetCandidate(id: update.id, name: update.name, location: update.location,
                                  representations: candidate.representations.map { representations[$0.id] ?? $0 } +
                                      update.representations.filter { previousRepresentationIDs.contains($0.id) == false })
        } + updates.filter { previousIDs.contains($0.id) == false }
    }

    private func finish(token: UUID) {
        workers[token] = nil
        guard token == generation else {
            return
        }

        if let snapshot = latestSnapshot {
            results = snapshot.results; duplicateGroups = snapshot.duplicateGroups
        }
        for result in results {
            guard var review = reviews[result.url] else {
                continue
            }

            review.representationIDs = Dictionary(uniqueKeysWithValues: result.candidates.compactMap { candidate in
                guard let selected = review.representationIDs[candidate.id] else {
                    return nil
                }

                let representation = candidate.representations.first { $0.id == selected } ?? candidate.representations.first(where: \.matches)
                return representation.map { (candidate.id, $0.id) }
            })
            reviews[result.url] = review
        }
        latestSnapshot = nil
        state = error == nil ? .complete : .failed
        if isIncomplete {
            markResultsIncomplete()
        } else {
            for index in results.indices where results[index].error == nil {
                results[index].status = .complete
            }
        }
        reconcileSelection()
        phase = error == nil ? "Search complete" : "Search failed"
        worker = nil
    }

    private func reconcileSelection() {
        if case let .incoming(url) = selection, results.contains(where: { $0.url == url }) {
            return
        }
        if case let .group(id) = selection, duplicateGroups.contains(where: { $0.id == id }) {
            return
        }
        selection = duplicateGroups.first.map { .group($0.id) }
    }

    private func markResultsIncomplete() {
        for index in results.indices where results[index].error == nil {
            results[index].status = .incomplete
        }
    }
}

// MARK: - ScanPublisher

/// Keep repeated catalog snapshots from flooding the main actor. First matches,
/// phase changes, errors, and the final snapshot remain immediate.
private actor ScanPublisher {
    private let publish: @Sendable (ScanSnapshot) async -> Void
    private let clock = ContinuousClock()
    private var lastUpdate: ContinuousClock.Instant?
    private var lastPhase: String?
    private var hadMatches = false
    private var pending: ScanSnapshot?

    init(publish: @escaping @Sendable (ScanSnapshot) async -> Void) {
        self.publish = publish
    }

    func receive(_ snapshot: ScanSnapshot) async {
        pending = snapshot
        let now = clock.now
        let hasMatches = snapshot.duplicateGroups.isEmpty == false || snapshot.results.contains { $0.candidates.isEmpty == false }
        let important = lastPhase != snapshot.phase || snapshot.error != nil || (hasMatches && hadMatches == false)
        if important || lastUpdate.map({ $0.duration(to: now) >= .milliseconds(100) }) ?? true {
            lastUpdate = now; lastPhase = snapshot.phase; hadMatches = hasMatches
            await publish(snapshot)
        }
    }

    func finish() async {
        if let pending {
            await publish(pending)
        }
        pending = nil
    }
}
