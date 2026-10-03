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
