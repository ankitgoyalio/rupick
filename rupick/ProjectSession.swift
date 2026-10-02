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

struct IncomingResult: Identifiable, Sendable, Equatable {
    var id: URL { url }
    let url: URL
    var candidates: [AssetCandidate] = []
    var error: String?
}

struct ScanSnapshot: Sendable {
    var results: [IncomingResult]
    var discovered = 0
    var compared = 0
    var skipped = 0
    var phase = "Discovering image assets…"
    var error: String?
}

@MainActor @Observable
final class ProjectSession {
    private(set) var root: URL?
    private(set) var results: [IncomingResult] = []
    private(set) var isRunning = false
    private(set) var discovered = 0
    private(set) var compared = 0
    private(set) var skipped = 0
    private(set) var phase = "Choose a project folder to begin."
    private(set) var error: String?
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()

    @discardableResult
    func start(root: URL, incoming: [URL]) -> Task<Void, Never> {
        worker?.cancel()
        let token = UUID()
        generation = token
        self.root = root
        results = incoming.map { IncomingResult(url: $0) }
        discovered = 0; compared = 0; skipped = 0; error = nil
        phase = "Discovering image assets…"
        isRunning = true
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            guard let session = self else { return }
            let rootAccess = root.startAccessingSecurityScopedResource()
            let access = incoming.filter { $0.startAccessingSecurityScopedResource() }
            defer {
                if rootAccess { root.stopAccessingSecurityScopedResource() }
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
        worker?.cancel()
        generation = UUID()
        isRunning = false
        phase = "Search cancelled. Results are incomplete."
    }

    private func receive(_ snapshot: ScanSnapshot, token: UUID) {
        guard token == generation else { return }
        results = snapshot.results
        discovered = snapshot.discovered
        compared = snapshot.compared
        skipped = snapshot.skipped
        phase = snapshot.phase
        error = snapshot.error
    }

    private func finish(token: UUID) {
        guard token == generation else { return }
        isRunning = false
        phase = error == nil ? "Search complete" : "Search failed"
    }
}
