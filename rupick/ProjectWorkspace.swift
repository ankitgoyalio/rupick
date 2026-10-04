import Foundation
import Observation

// MARK: - RecentProject

struct RecentProject: Codable, Identifiable, Equatable {
    let id: URL
    let bookmark: Data
    var name: String {
        id.lastPathComponent
    }
}

// MARK: - ProjectBookmarkAdapter

/// Persistent access is separate from project identity and session ownership.
struct ProjectBookmarkAdapter: Sendable {
    let create: @Sendable (URL) throws -> Data
    let resolve: @Sendable (Data) throws -> URL

    static let native = Self(create: {
        try $0.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                            includingResourceValuesForKeys: nil, relativeTo: nil)
    }, resolve: {
        var stale = false
        return try URL(resolvingBookmarkData: $0, options: [.withSecurityScope, .withoutUI],
                       relativeTo: nil, bookmarkDataIsStale: &stale)
    })
}

// MARK: - ProjectWorkspace

@MainActor @Observable
final class ProjectWorkspace {
    private(set) var recents: [RecentProject]
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let bookmarks: ProjectBookmarkAdapter
    @ObservationIgnored private var sessions = [URL: ProjectSession]()
    private static let storageKey = "recentProjects"

    init(defaults: UserDefaults = .standard, bookmarks: ProjectBookmarkAdapter = .native) {
        self.defaults = defaults
        self.bookmarks = bookmarks
        recents = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode([RecentProject].self, from: $0) } ?? []
    }

    /// Validate while the grant is active, then transfer access to the session before releasing it.
    func open(_ url: URL) throws -> URL {
        let access = FileAccessLease(urls: [url], adapter: .native)
        defer { access.release() }
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isReadableKey])
        guard values.isDirectory == true, values.isReadable == true else {
            throw CocoaError(.fileReadNoPermission)
        }

        let identity = URL(fileURLWithPath: ProjectFileLocation.canonical(url).path, isDirectory: true)
        let bookmark = try bookmarks.create(url)
        let session = session(for: identity)
        if session.root == nil {
            session.open(root: url)
        }
        recents.removeAll { $0.id == identity }
        recents.insert(RecentProject(id: identity, bookmark: bookmark), at: 0)
        recents = Array(recents.prefix(10))
        try defaults.set(JSONEncoder().encode(recents), forKey: Self.storageKey)
        return identity
    }

    func reopen(_ recent: RecentProject) throws -> URL {
        // Refresh the bookmark on every successful open, including moved folders and stale grants.
        let identity = try open(bookmarks.resolve(recent.bookmark))
        if identity != recent.id {
            recents.removeAll { $0.id == recent.id }
            try defaults.set(JSONEncoder().encode(recents), forKey: Self.storageKey)
        }
        return identity
    }

    func restore(_ identity: URL) throws -> URL {
        if let recent = recents.first(where: { $0.id == identity }) {
            return try reopen(recent)
        }
        return try open(identity)
    }

    var openProjects: Set<URL> {
        Set(sessions.keys)
    }

    func session(for identity: URL) -> ProjectSession {
        if let session = sessions[identity] {
            return session
        }
        let session = ProjectSession()
        sessions[identity] = session
        return session
    }

    func close(_ identity: URL, session: ProjectSession) {
        guard sessions[identity] === session else {
            return
        }

        sessions.removeValue(forKey: identity)
        session.close()
    }
}
