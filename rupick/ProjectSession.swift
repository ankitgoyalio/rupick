import Foundation
import Observation

struct Representation: Identifiable, Sendable, Equatable {
    let id: String
    let url: URL
    let label: String
    let matches: Bool
}

struct AssetCandidate: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let location: String
    let representations: [Representation]
}

struct DuplicateGroup: Identifiable, Sendable, Equatable {
    let id: String
    var members: [AssetCandidate]
}

enum ComparisonStatus: Sendable {
    case waiting, decoding, comparing, complete, incomplete, unreadable
}

enum SearchState: Sendable {
    case idle, running, complete, cancelled, failed
}

struct IncomingResult: Identifiable, Sendable, Equatable {
    var id: URL {
        url
    }

    let url: URL
    var candidates: [AssetCandidate] = []
    var error: String?
    var status: ComparisonStatus = .waiting

    var statusText: String {
        switch status {
        case .waiting: "Waiting for catalog scan…"
        case .decoding: "Reading image…"
        case .comparing: "Comparing · \(candidates.count) provisional matches"
        case .unreadable: "Image unavailable"
        case .incomplete: "Incomplete search · \(candidates.count) matches so far"
        case .complete: candidates.isEmpty ? "No matches found" : "\(candidates.count) exact matches"
        }
    }
}

struct ScanSnapshot: Sendable {
    var results: [IncomingResult]
    var duplicateGroups: [DuplicateGroup] = []
    var discovered = 0
    var compared = 0
    var decoded = 0
    var skipped = 0
    var phase = "Discovering image assets…"
    var error: String?
}

@MainActor @Observable
final class ProjectSession {
    private(set) var root: URL?
    private(set) var results: [IncomingResult] = []
    private(set) var duplicateGroups: [DuplicateGroup] = []
    private(set) var state: SearchState = .idle
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

    @discardableResult
    func start(root: URL, incoming: [URL]) -> Task<Void, Never> {
        worker?.cancel()
        var seen = Set<URL>()
        let incoming = incoming.filter { seen.insert($0).inserted }
        let token = UUID()
        generation = token
        self.root = root
        duplicateGroups = []
        results = incoming.map { IncomingResult(url: $0) }
        discovered = 0; compared = 0; decoded = 0; skipped = 0; error = nil
        phase = "Discovering image assets…"
        state = .running
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            guard let session = self else { return }
            let rootAccess = root.startAccessingSecurityScopedResource()
            let access = incoming.filter { $0.startAccessingSecurityScopedResource() }
            defer {
                if rootAccess {
                    root.stopAccessingSecurityScopedResource()
                }
                access.forEach { $0.stopAccessingSecurityScopedResource() }
            }
            await CatalogComparison.run(root: root, incoming: incoming) { snapshot in
                await session.receive(snapshot, token: token)
            }
            await session.finish(token: token)
        }
        worker = task
        return task
    }

    func cancel() {
        guard isRunning else { return }
        worker?.cancel()
        worker = nil
        generation = UUID()
        state = .cancelled
        markResultsIncomplete()
        phase = "Search cancelled. Results are incomplete."
    }

    private func receive(_ snapshot: ScanSnapshot, token: UUID) {
        guard token == generation else { return }
        results = snapshot.results
        duplicateGroups = snapshot.duplicateGroups
        discovered = snapshot.discovered
        compared = snapshot.compared
        decoded = snapshot.decoded
        skipped = snapshot.skipped
        phase = snapshot.phase
        error = snapshot.error
    }

    private func finish(token: UUID) {
        guard token == generation else { return }
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
