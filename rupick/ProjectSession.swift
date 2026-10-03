import Foundation
import Observation

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

// MARK: - ProjectSession

@MainActor @Observable
final class ProjectSession {
    private(set) var root: URL?
    private(set) var results = [IncomingResult]()
    private(set) var duplicateGroups = [DuplicateGroup]()
    private(set) var state = SearchState.idle
    var isRunning: Bool {
        state == .running
    }

    var isIncomplete: Bool {
        skipped > 0 || state == .cancelled || state == .failed
    }

    private(set) var discovered = 0
    private(set) var compared = 0
    private(set) var decoded = 0
    private(set) var skipped = 0
    private(set) var phase = "Choose a project folder to begin."
    private(set) var error: String?
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var latestSnapshot: ScanSnapshot?

    @discardableResult
    func start(root: URL, incoming: [URL]) -> Task<Void, Never> {
        worker?.cancel()
        var seen = Set<URL>()
        let incoming = incoming.filter { seen.insert($0).inserted }
        let token = UUID()
        generation = token
        latestSnapshot = nil
        let refreshing = self.root == root
        let previous = Dictionary(uniqueKeysWithValues: results.map { ($0.url, $0) })
        self.root = root
        if refreshing == false {
            duplicateGroups = []
        }
        results = incoming.map { refreshing ? previous[$0] ?? IncomingResult(url: $0) : IncomingResult(url: $0) }
        if refreshing {
            for index in results.indices where results[index].error == nil {
                results[index].status = .comparing
            }
        }
        discovered = 0; compared = 0; decoded = 0; skipped = 0; error = nil
        phase = "Discovering image assets…"
        state = .running
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            guard let session = self else {
                return
            }

            let rootAccess = root.startAccessingSecurityScopedResource()
            let access = incoming.filter { $0.startAccessingSecurityScopedResource() }
            defer {
                if rootAccess {
                    root.stopAccessingSecurityScopedResource()
                }
                access.forEach { $0.stopAccessingSecurityScopedResource() }
            }
            let publisher = ScanPublisher { snapshot in await session.receive(snapshot, token: token) }
            await CatalogComparison.run(root: root, incoming: incoming) { snapshot in await publisher.receive(snapshot) }
            await publisher.finish()
            await session.finish(token: token)
        }
        worker = task
        return task
    }

    func cancel() {
        guard isRunning else {
            return
        }

        worker?.cancel()
        worker = nil
        generation = UUID()
        latestSnapshot = nil
        state = .cancelled
        markResultsIncomplete()
        phase = "Search cancelled. Results are incomplete."
    }

    private func receive(_ snapshot: ScanSnapshot, token: UUID) {
        guard token == generation else {
            return
        }

        latestSnapshot = snapshot
        // Retain inspected content while replacement results are still arriving.
        // Completion always replaces it, including when files have disappeared or changed.
        let previous = Dictionary(uniqueKeysWithValues: results.map { ($0.url, $0) })
        results = snapshot.results.map { update in
            guard update.error == nil, update.candidates.isEmpty,
                  var retained = previous[update.url], retained.candidates.isEmpty == false
            else {
                return update
            }

            retained.status = .comparing
            return retained
        }
        for group in snapshot.duplicateGroups {
            if let index = duplicateGroups.firstIndex(where: { $0.id == group.id }) {
                duplicateGroups[index] = group
            } else {
                duplicateGroups.append(group)
            }
        }
        discovered = snapshot.discovered
        compared = snapshot.compared
        decoded = snapshot.decoded
        skipped = snapshot.skipped
        phase = snapshot.phase
        error = snapshot.error
    }

    private func finish(token: UUID) {
        guard token == generation else {
            return
        }

        if let snapshot = latestSnapshot {
            results = snapshot.results; duplicateGroups = snapshot.duplicateGroups
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
        phase = error == nil ? "Search complete" : "Search failed"
        worker = nil
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
