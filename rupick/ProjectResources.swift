import Darwin
import Foundation
import Synchronization

// MARK: - FileAccessAdapter

/// Internal adapters keep resource accounting testable without exposing it to views.
struct FileAccessAdapter: Sendable {
    let acquire: @Sendable (URL) -> Bool
    let release: @Sendable (URL) -> Void

    static let native = FileAccessAdapter(
        acquire: { $0.startAccessingSecurityScopedResource() },
        release: { $0.stopAccessingSecurityScopedResource() }
    )
}

// MARK: - FileAccessLease

final class FileAccessLease: Sendable {
    private let urls: Mutex<[URL]>
    private let adapter: FileAccessAdapter

    init(urls: [URL], adapter: FileAccessAdapter) {
        self.adapter = adapter
        self.urls = Mutex(urls.filter { adapter.acquire($0) })
    }

    func release() {
        let acquired = urls.withLock { urls in
            let acquired = urls
            urls = []
            return acquired
        }
        acquired.forEach { adapter.release($0) }
    }

    deinit {
        release()
    }
}

// MARK: - ProjectFileLocation

/// Foundation can preserve /tmp aliases while enumeration returns /private/tmp.
/// Use the filesystem's canonical location for discovery and ignore-rule boundaries.
enum ProjectFileLocation {
    static func canonical(_ url: URL) -> URL {
        guard let path = url.path.withCString({ realpath($0, nil) }) else {
            return url.standardizedFileURL
        }

        defer { free(path) }
        return URL(fileURLWithPath: String(cString: path), isDirectory: url.hasDirectoryPath)
    }
}
