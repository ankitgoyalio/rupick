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
    @ObservationIgnored private let storage: SessionStorage?
    @ObservationIgnored private var archive = SessionArchive()
    private(set) var restorationError: String?
    private(set) var isTerminating = false
    private(set) var didRestoreWindows = false
    var restorationIdentities: [URL] {
        archive.projects.map(\.identity)
    }

    private static let storageKey = "recentProjects"

    init(defaults: UserDefaults = .standard, bookmarks: ProjectBookmarkAdapter = .native, storage: SessionStorage? = nil, persistsSessions: Bool = true) {
        self.defaults = defaults
        self.bookmarks = bookmarks
        self.storage = persistsSessions ? (storage ?? .local(defaults)) : nil
        do {
            if let data = try self.storage?.load() {
                let saved = try JSONDecoder().decode(SessionArchive.self, from: data)
                guard saved.version == 1, Set(saved.projects.map(\.identity)).count == saved.projects.count,
                      saved.projects.allSatisfy({ project in
                          project.identity.isFileURL && project.reference.url.isFileURL &&
                              project.incoming.allSatisfy { $0.reference.url.isFileURL } &&
                              Set(project.incoming.map { $0.reference.url }).count == project.incoming.count
                      })
                else {
                    throw CocoaError(.fileReadCorruptFile)
                }

                archive = saved
            }
        } catch {
            restorationError = "Saved sessions could not be restored. Open your project folders to begin again."
        }
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
        if let saved = archive.projects.first(where: { $0.identity == identity }), sessions[identity] == nil {
            resume(saved, root: url, unavailable: false)
        }
        let session = session(for: identity)
        if session.root == nil {
            session.open(root: url)
        }
        recents.removeAll { $0.id == identity }
        recents.insert(RecentProject(id: identity, bookmark: bookmark), at: 0)
        recents = Array(recents.prefix(10))
        try defaults.set(JSONEncoder().encode(recents), forKey: Self.storageKey)
        checkpoint(identity)
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
        if sessions[identity]?.root != nil {
            return identity
        }
        if let saved = archive.projects.first(where: { $0.identity == identity }) {
            do {
                guard let bookmark = saved.reference.bookmark else {
                    throw CocoaError(.fileReadNoPermission)
                }

                let root = try bookmarks.resolve(bookmark)
                let access = FileAccessLease(urls: [root], adapter: .native)
                defer { access.release() }
                let values = try root.resourceValues(forKeys: [.isDirectoryKey, .isReadableKey])
                guard values.isDirectory == true, values.isReadable == true else {
                    throw CocoaError(.fileReadNoPermission)
                }

                let identity = URL(fileURLWithPath: ProjectFileLocation.canonical(root).path, isDirectory: true)
                if identity != saved.identity {
                    archive.projects.removeAll { $0.identity == saved.identity }
                    if sessions[identity] == nil {
                        let moved = try SavedProjectSession(identity: identity, reference: SavedFileReference(url: root, bookmark: bookmarks.create(root)),
                                                            incoming: saved.incoming, selection: saved.selection)
                        resume(moved, root: root, unavailable: false)
                    }
                } else {
                    resume(saved, root: root, unavailable: false)
                }
                return identity
            } catch {
                resume(saved, root: saved.reference.url, unavailable: true)
            }
            return identity
        }
        if let recent = recents.first(where: { $0.id == identity }) {
            return try reopen(recent)
        }
        return try open(identity)
    }

    func restoreWindows() -> [URL] {
        guard didRestoreWindows == false else {
            return []
        }

        didRestoreWindows = true
        return restorationIdentities
    }

    private func resume(_ saved: SavedProjectSession, root: URL, unavailable: Bool) {
        let session = session(for: saved.identity)
        var reviews = [URL: IncomingReview]()
        var urls = [URL]()
        var blocked = Set<URL>()
        var selection = saved.selection
        for incoming in saved.incoming {
            let resolved = incoming.reference.bookmark.flatMap { try? bookmarks.resolve($0) }
            let url = resolved ?? incoming.reference.url
            if resolved == nil {
                blocked.insert(url)
            }
            guard urls.contains(url) == false else {
                continue
            }

            urls.append(url)
            reviews[url] = incoming.review
            if selection == .incoming(incoming.reference.url) {
                selection = .incoming(url)
            }
        }
        session.restore(root: root, incoming: urls, reviews: reviews, selection: selection, unavailable: unavailable, blockedIncoming: blocked)
    }

    @discardableResult
    func locateProject(_ identity: URL, at root: URL) throws -> URL {
        let access = FileAccessLease(urls: [root], adapter: .native)
        defer { access.release() }
        let values = try root.resourceValues(forKeys: [.isDirectoryKey, .isReadableKey])
        guard values.isDirectory == true, values.isReadable == true else {
            throw CocoaError(.fileReadNoPermission)
        }

        let bookmark = try bookmarks.create(root)
        guard let session = sessions[identity] else {
            return identity
        }

        let canonical = URL(fileURLWithPath: ProjectFileLocation.canonical(root).path, isDirectory: true)
        guard canonical == identity || sessions[canonical] == nil else {
            throw CocoaError(.fileReadInvalidFileName)
        }

        let reviews = session.savedReviews
        let incoming = session.results.map(\.url)
        let selection = session.selection
        session.restore(root: root, incoming: incoming, reviews: reviews, selection: selection, blockedIncoming: session.inaccessibleIncoming)
        if let index = archive.projects.firstIndex(where: { $0.identity == identity }) {
            archive.projects[index].reference = SavedFileReference(url: root, bookmark: bookmark)
        }
        if canonical != identity {
            sessions.removeValue(forKey: identity)
            sessions[canonical] = session
            session.didChange = { [weak self] in self?.checkpoint(canonical) }
            archive.projects.removeAll { $0.identity == identity }
        }
        checkpoint(canonical)
        return canonical
    }

    @discardableResult
    func saveSessions() -> Bool {
        for identity in sessions.keys {
            checkpoint(identity)
        }
        return sessions.values.allSatisfy { $0.persistenceError == nil }
    }

    @discardableResult
    func prepareForTermination() -> Bool {
        guard saveSessions() else {
            return false
        }

        isTerminating = true
        return true
    }

    private func checkpoint(_ identity: URL) {
        guard let storage, let session = sessions[identity], let root = session.root else {
            return
        }

        let old = archive.projects.first { $0.identity == identity }
        let reference = SavedFileReference(url: root, bookmark: (try? bookmarks.create(root)) ?? old?.reference.bookmark)
        let incoming = session.results.map { result in
            SavedIncoming(reference: SavedFileReference(url: result.url, bookmark: (try? bookmarks.create(result.url)) ??
                              old?.incoming.first(where: { $0.reference.url == result.url })?.reference.bookmark),
            review: session.savedReviews[result.url] ?? IncomingReview())
        }
        let saved = SavedProjectSession(identity: identity, reference: reference, incoming: incoming, selection: session.selection)
        if let index = archive.projects.firstIndex(where: { $0.identity == identity }) {
            archive.projects[index] = saved
        } else {
            archive.projects.append(saved)
        }
        do {
            try storage.save(JSONEncoder().encode(archive))
            session.reportPersistenceSaved()
        } catch { session.reportPersistenceFailure() }
    }

    func session(for identity: URL) -> ProjectSession {
        if let session = sessions[identity] {
            return session
        }
        let session = ProjectSession()
        sessions[identity] = session
        session.didChange = { [weak self] in self?.checkpoint(identity) }
        return session
    }

    func close(_ identity: URL, session: ProjectSession) {
        guard isTerminating == false, sessions[identity] === session else {
            return
        }

        sessions.removeValue(forKey: identity)
        session.didChange = nil
        archive.projects.removeAll { $0.identity == identity }
        do { try storage?.save(JSONEncoder().encode(archive)) }
        catch { restorationError = "The closed session could not be removed from saved sessions." }
        session.close()
    }
}
