import Foundation
import Observation

// MARK: - Representation

struct Representation: Codable, Identifiable, Sendable, Equatable {
    let id: String
    let url: URL
    let label: String
    let matches: Bool
    var contentVersion: String?
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
    var contentVersion: String?
    var status = ComparisonStatus.waiting
    var needsRecovery = false

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

struct ReusedAsset: Codable, Sendable, Equatable {
    let candidateID: String
    let name: String
    let location: String
    let representation: Representation
}

// MARK: - ReviewOutcome

enum ReviewOutcome: Codable, Sendable, Equatable {
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

// MARK: - ReviewNotice

enum ReviewNotice: Codable, Sendable, Equatable {
    case incomingChanged
    case selectedMatchChanged
    case newMatchFound

    var title: LocalizedStringResource {
        switch self {
        case .incomingChanged,
             .selectedMatchChanged:
            "Review again"

        case .newMatchFound:
            "New match found"
        }
    }

    var label: LocalizedStringResource {
        switch self {
        case .incomingChanged:
            "Image changed. Review this image again."

        case .selectedMatchChanged:
            "The reused image changed or is no longer a match. Choose a match or keep this image as new."

        case .newMatchFound:
            "New match found. Your decision is unchanged. Compare the new match to revisit it."
        }
    }
}

// MARK: - IncomingReview

struct IncomingReview: Codable, Sendable, Equatable {
    var outcome: ReviewOutcome?
    var notice: ReviewNotice?
    private var contentVersion: String?
    private var matchIDs = Set<String>()
    var representationIDs = [String: String]()

    mutating func record(_ outcome: ReviewOutcome, for result: IncomingResult) {
        self.outcome = outcome
        notice = nil
        contentVersion = result.contentVersion
        matchIDs = Self.matches(in: result)
    }

    mutating func invalidateIncoming() {
        guard outcome != nil else {
            return
        }

        outcome = nil
        notice = .incomingChanged
    }

    mutating func reconcile(with result: IncomingResult) {
        representationIDs = Dictionary(uniqueKeysWithValues: result.candidates.compactMap { candidate in
            guard let selected = representationIDs[candidate.id] else {
                return nil
            }

            let representation = candidate.representations.first { $0.id == selected } ?? candidate.representations.first(where: \.matches)
            return representation.map { (candidate.id, $0.id) }
        })
        guard outcome != nil else {
            return
        }

        guard contentVersion == result.contentVersion else {
            invalidateIncoming()
            return
        }

        if case let .reuse(asset) = outcome {
            guard let candidate = result.candidates.first(where: { $0.id == asset.candidateID }),
                  let representation = candidate.representations.first(where: { $0.id == asset.representation.id && $0.matches }),
                  representation.contentVersion == asset.representation.contentVersion,
                  representation.url == asset.representation.url,
                  representation.label == asset.representation.label
            else {
                outcome = nil
                notice = .selectedMatchChanged
                return
            }

            outcome = .reuse(candidate: candidate, representation: representation)
        }
        notice = Self.matches(in: result).subtracting(matchIDs).isEmpty ? nil : .newMatchFound
    }

    private static func matches(in result: IncomingResult) -> Set<String> {
        Set(result.candidates.flatMap { $0.representations.filter(\.matches).map(\.id) })
    }
}

// MARK: - ScanSnapshot

struct ScanSnapshot: Sendable {
    var results: [IncomingResult]
    var duplicateGroups = [DuplicateGroup]()
    var discovered = 0
    var compared = 0
    var decoded = 0
    var imageDecodes = 0
    var skipped = 0
    var phase = "Discovering image assets…"
    var error: String?
}

// MARK: - SidebarSelection

enum SidebarSelection: Codable, Hashable {
    case group(String)
    case incoming(URL)
}

// MARK: - ProjectSession

@MainActor @Observable
final class ProjectSession {
    struct Dependencies: Sendable {
        let access: FileAccessAdapter
        let scan: @Sendable (URL, [URL], ProjectCatalogInventory?, @escaping @Sendable (ScanSnapshot) async -> Void) async -> Void

        var observation = ProjectObservationAdapter.disabled
        var incomingObservation = IncomingObservationAdapter.disabled

        static var native: Dependencies {
            let cache = CatalogComparisonCache()
            return Dependencies(access: .native, scan: { root, incoming, inventory, publish in
                await CatalogComparison.run(root: root, incoming: incoming, cache: cache, inventory: inventory, publish: publish)
            }, observation: .native, incomingObservation: .native)
        }
    }

    @ObservationIgnored var didChange: (() -> Void)?
    @ObservationIgnored private var blockedIncoming = Set<URL>()
    @ObservationIgnored private var pendingReviews = [URL: IncomingReview]()
    @ObservationIgnored private var restoredSelection: SidebarSelection?
    private(set) var persistenceError: String?
    private(set) var root: URL?
    private(set) var results = [IncomingResult]()
    private(set) var reviews = [URL: IncomingReview]()
    private(set) var duplicateGroups = [DuplicateGroup]()
    private(set) var state = SearchState.idle
    private(set) var thumbnails: ThumbnailStore
    private(set) var observationError: String?
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
    /// Normalization work in the latest scan, exposed for workflow diagnostics.
    private(set) var imageDecodes = 0
    private(set) var skipped = 0
    private(set) var phase = "Choose a project folder to begin."
    private(set) var error: String?
    @ObservationIgnored private let dependencies: Dependencies
    @ObservationIgnored private var observation: ProjectObservation?
    @ObservationIgnored private var incomingObservation: IncomingObservation?
    @ObservationIgnored private var incomingObservationID = UUID()
    @ObservationIgnored private var refreshDelay: Task<Void, Never>?
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var workers = [UUID: Task<Void, Never>]()
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var latestSnapshot: ScanSnapshot?
    @ObservationIgnored private var projectAccess: FileAccessLease?
    @ObservationIgnored private var incomingAccess = [URL: FileAccessLease]()
    @ObservationIgnored private let incomingQueue: IncomingQueue
    @ObservationIgnored private var temporaryRoot: URL?
    @ObservationIgnored private var retiredPreviews = [Task<Void, Never>]()
    @ObservationIgnored private var cleanup: Task<Void, Never>?

    init(dependencies: Dependencies = .native) {
        self.dependencies = dependencies
        incomingQueue = IncomingQueue(access: dependencies.access)
        thumbnails = ThumbnailStore(access: dependencies.access)
    }

    deinit {
        workers.values.forEach { $0.cancel() }
        refreshDelay?.cancel()
        incomingObservation?.cancel()
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
        pendingReviews[incoming]?.representationIDs[candidateID] = representationID
        didChange?()
    }

    @discardableResult
    func reuseAsset(for incoming: URL, candidateID: String, representationID: String) -> Bool {
        guard isRunning == false, state != .failed,
              let result = results.first(where: { $0.url == incoming }), result.error == nil,
              let candidate = result.candidates.first(where: { $0.id == candidateID }),
              let representation = candidate.representations.first(where: { $0.id == representationID && $0.matches })
        else {
            return false
        }

        pendingReviews[incoming] = nil
        reviews[incoming, default: IncomingReview()].record(.reuse(candidate: candidate, representation: representation), for: result)
        selectRepresentation(for: incoming, candidateID: candidateID, representationID: representationID)
        return true
    }

    func keepAsNew(_ incoming: URL) {
        guard isRunning == false, state != .failed, let result = results.first(where: { $0.url == incoming }), result.needsRecovery == false else {
            return
        }

        pendingReviews[incoming] = nil
        reviews[incoming, default: IncomingReview()].record(.keepAsNew, for: result)
        didChange?()
    }

    @discardableResult
    func open(root: URL, incoming: [URL] = [], replacing sessionID: UUID? = nil) -> Task<Void, Never> {
        guard sessionID == nil || sessionID == id else {
            return Task {}
        }

        close()
        self.root = root
        projectAccess = FileAccessLease(urls: [root], adapter: dependencies.access)
        let sessionID = id
        do {
            observation = try dependencies.observation.start(root) { [weak self] in
                guard let self, id == sessionID else {
                    return
                }

                filesChanged("Catalog changes detected. Updating results…")
            }
        } catch {
            observationError = "Automatic updates are unavailable. Close this project window, then reopen the folder to try again."
        }
        return refresh(incoming: incoming)
    }

    var inaccessibleIncoming: Set<URL> {
        blockedIncoming
    }

    var savedReviews: [URL: IncomingReview] {
        reviews.merging(pendingReviews) { _, pending in pending }
    }

    func reportPersistenceSaved() {
        persistenceError = nil
    }

    func reportPersistenceFailure() {
        persistenceError = "Session could not be saved. Keep this window open and try again before quitting."
    }

    @discardableResult
    func restore(root: URL, incoming: [URL], reviews: [URL: IncomingReview], selection: SidebarSelection?, unavailable: Bool = false, blockedIncoming: Set<URL> = []) -> Task<Void, Never> {
        let task: Task<Void, Never>
        if unavailable {
            close()
            self.root = root
            results = incoming.map { IncomingResult(url: $0) }
            state = .failed
            error = "The project folder is unavailable. Locate its folder to restore access."
            phase = "Search failed"
            markResultsIncomplete()
            task = Task {}
        } else {
            task = open(root: root, incoming: incoming)
        }
        self.blockedIncoming = blockedIncoming
        pendingReviews = reviews
        restoredSelection = selection
        self.selection = selection
        didChange?()
        return task
    }

    func removeIncoming(_ url: URL) {
        blockedIncoming.remove(url)
        reviews[url] = nil
        pendingReviews[url] = nil
        if selection == .incoming(url) {
            restoredSelection = nil
            selection = nil
        }
        refresh(incoming: results.map(\.url).filter { $0 != url })
    }

    func locateIncoming(_ original: URL, at replacement: URL) {
        guard results.contains(where: { $0.url == original }),
              original == replacement || results.contains(where: { $0.url == replacement }) == false
        else {
            return
        }

        blockedIncoming.remove(original)
        incomingAccess.removeValue(forKey: original)?.release()
        let review = pendingReviews.removeValue(forKey: original) ?? reviews.removeValue(forKey: original)
        reviews[original] = nil
        if let review {
            pendingReviews[replacement] = review
        }
        let incoming = results.map { $0.url == original ? replacement : $0.url }
        if selection == .incoming(original) {
            restoredSelection = nil
            selection = .incoming(replacement)
        }
        refresh(incoming: incoming)
    }

    private func filesChanged(_ updatePhase: String) {
        // Reject current completions immediately, including during the quiet period.
        worker?.cancel()
        generation = UUID()
        latestSnapshot = nil
        state = .running
        for index in results.indices where results[index].error == nil {
            results[index].status = .comparing
        }
        phase = updatePhase
        refreshDelay?.cancel()
        refreshDelay = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            guard let self, Task.isCancelled == false else {
                return
            }

            refreshDelay = nil
            refresh(incoming: results.map(\.url))
        }
    }

    #if DEBUG
        @discardableResult
        func openFixture(root: URL, incoming: [URL] = []) -> Task<Void, Never> {
            let work = open(root: root, incoming: incoming)
            selection = nil
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

        refreshDelay?.cancel()
        refreshDelay = nil
        retiredPreviews.append(thumbnails.close())
        thumbnails = ThumbnailStore(access: dependencies.access)
        worker?.cancel()
        var seen = Set<URL>()
        let incoming = incoming.filter { seen.insert($0).inserted }
        for url in incoming where incomingAccess[url] == nil {
            incomingAccess[url] = FileAccessLease(urls: [url], adapter: dependencies.access)
        }
        incomingAccess = incomingAccess.filter { seen.contains($0.key) }
        incomingObservation?.cancel()
        if let incomingObservation {
            retiredPreviews.append(incomingObservation.task)
        }
        let observationID = UUID()
        incomingObservationID = observationID
        incomingObservation = dependencies.incomingObservation.start(incoming) { [weak self] changes in
            guard let self, incomingObservationID == observationID else {
                return
            }

            // A scan may already include an event delivered after its baseline was read.
            guard changes.contains(where: { change in
                results.first(where: { $0.url == change.url })?.contentVersion != change.contentVersion
            }) else {
                return
            }

            // Only the replacement scan can establish the current content version.
            // Reject obsolete work now, and reconcile decisions with that scan's results.
            filesChanged("Incoming images changed. Updating results…")
        }
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
        discovered = 0; compared = 0; decoded = 0; imageDecodes = 0; skipped = 0; error = nil
        phase = "Discovering image assets…"
        state = .running
        didChange?()
        // Acquire before scheduling: a close can release window grants before the worker starts.
        let access = FileAccessLease(urls: [root] + incoming, adapter: dependencies.access)
        let scan = dependencies.scan
        let observation = observation
        let incomingObservation = incomingObservation
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            defer { access.release() }
            let publisher = ScanPublisher { [weak self] snapshot in
                await self?.receive(snapshot, token: token)
            }
            await incomingObservation?.ready()
            let inventory = await observation?.takeInitialInventory()
            guard Task.isCancelled == false else {
                await self?.retire(token: token)
                return
            }

            await scan(root, incoming, inventory) { snapshot in await publisher.receive(snapshot) }
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
        restoredSelection = nil
        self.selection = selection
        didChange?()
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
        let batch = incomingQueue.begin(count: count)
        hasPendingIncoming = incomingQueue.hasPending
        return batch
    }

    @discardableResult
    func receiveIncoming(_ urls: [URL], batch: UUID) -> Task<Void, Never>? {
        accept(incomingQueue.receive(urls, batch: batch, excluding: results.map(\.url)))
    }

    @discardableResult
    func receiveIncoming(_ url: URL?, batch: UUID, index: Int) -> Task<Void, Never>? {
        accept(incomingQueue.receive(url, batch: batch, index: index, excluding: results.map(\.url)))
    }

    @discardableResult
    func abandonIncoming(batch: UUID) -> Task<Void, Never>? {
        accept(incomingQueue.abandon(batch: batch, excluding: results.map(\.url)))
    }

    private func accept(_ settlement: IncomingQueue.Settlement?) -> Task<Void, Never>? {
        hasPendingIncoming = incomingQueue.hasPending
        guard let settlement else {
            return nil
        }

        notice = settlement.rejected ? "Some files were not added. Choose PNG or JPEG files, or use Choose Images to try again." : nil
        guard settlement.urls.isEmpty == false else {
            return nil
        }

        incomingAccess.merge(settlement.access) { existing, _ in existing }
        return refresh(incoming: results.map(\.url) + settlement.urls)
    }

    func cancel() {
        guard canCancel else {
            return
        }

        incomingQueue.reset()
        hasPendingIncoming = false
        refreshDelay?.cancel()
        refreshDelay = nil
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
        let retiredObservation = observation
        retiredObservation?.stop()
        observation = nil
        observationError = nil
        refreshDelay?.cancel()
        refreshDelay = nil
        worker?.cancel()
        workers.values.forEach { $0.cancel() }
        let retiring = Array(workers.values)
        workers = [:]
        worker = nil
        generation = UUID()
        id = UUID()
        incomingQueue.reset()
        hasPendingIncoming = false
        latestSnapshot = nil
        projectAccess?.release()
        projectAccess = nil
        incomingAccess.values.forEach { $0.release() }
        incomingAccess = [:]
        incomingObservationID = UUID()
        incomingObservation?.cancel()
        let previews = retiredPreviews + [thumbnails.close()] + [incomingObservation?.task].compactMap { $0 }
        incomingObservation = nil
        retiredPreviews = []
        thumbnails = ThumbnailStore(access: dependencies.access)
        let temporary = temporaryRoot
        temporaryRoot = nil
        blockedIncoming = []; pendingReviews = [:]; restoredSelection = nil
        root = nil; results = []; reviews = [:]; duplicateGroups = []; selection = nil; notice = nil
        state = .idle
        discovered = 0; compared = 0; decoded = 0; imageDecodes = 0; skipped = 0; error = nil
        phase = "Choose a project folder to begin."
        let previousCleanup = cleanup
        let task = Task { [weak self] in
            await previousCleanup?.value
            await retiredObservation?.close()
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

    private func receive(_ update: ScanSnapshot, token: UUID) {
        guard token == generation else {
            return
        }

        var snapshot = update
        for index in snapshot.results.indices where blockedIncoming.contains(snapshot.results[index].url) {
            snapshot.results[index].candidates = []
            snapshot.results[index].contentVersion = nil
            snapshot.results[index].needsRecovery = true
            snapshot.results[index].status = .unreadable
            snapshot.results[index].error = "Access to this image could not be restored. Locate it to grant access again."
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
        imageDecodes = snapshot.imageDecodes
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

    private func retire(token: UUID) {
        workers[token] = nil
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
            if result.needsRecovery || error != nil {
                if let review = reviews.removeValue(forKey: result.url) {
                    pendingReviews[result.url] = review
                }
                continue
            }
            if let pending = pendingReviews.removeValue(forKey: result.url) {
                reviews[result.url] = pending
            }
            guard var review = reviews[result.url] else {
                continue
            }

            review.reconcile(with: result)
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
        if let restoredSelection {
            selection = restoredSelection
            self.restoredSelection = nil
        }
        reconcileSelection()
        didChange?()
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
