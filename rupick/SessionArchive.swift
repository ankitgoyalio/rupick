import Foundation

// MARK: - SessionArchive

/// Versioned, local-only session records. Results and thumbnails are rebuilt, never trusted from disk.
struct SessionArchive: Codable {
    var version = 1
    var projects = [SavedProjectSession]()
}

// MARK: - SavedFileReference

struct SavedFileReference: Codable {
    let url: URL
    var bookmark: Data?
}

// MARK: - SavedIncoming

struct SavedIncoming: Codable {
    var reference: SavedFileReference
    let review: IncomingReview
}

// MARK: - SavedProjectSession

struct SavedProjectSession: Codable {
    let identity: URL
    var reference: SavedFileReference
    var incoming: [SavedIncoming]
    let selection: SidebarSelection?
}

// MARK: - SessionStorage

/// Storage is a system boundary, shared by the production workspace and restoration tests.
@MainActor
struct SessionStorage {
    let load: () throws -> Data?
    let save: (Data) throws -> Void

    static func local(_ defaults: UserDefaults) -> Self {
        Self(load: { defaults.data(forKey: "projectSessions") }, save: {
            defaults.set($0, forKey: "projectSessions")
        })
    }
}
