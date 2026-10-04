// swiftformat:disable acronyms
import CoreServices
import Darwin
import Foundation

// MARK: - CatalogFileState

/// Metadata reconciliation runs off the UI actor and suppresses duplicate kernel events.
private actor CatalogFileState {
    private let root: URL
    private let baseline: Task<[String: String], Never>
    private var active = true
    private var previous: [String: String]?

    init(root: URL) {
        self.root = root
        baseline = Task.detached { Self.inventory(root) }
    }

    func ready() async {
        if previous == nil {
            previous = await baseline.value
        }
    }

    func changed() async -> Bool {
        await ready()
        guard active else {
            return false
        }

        let current = Self.inventory(root)
        guard current != previous else {
            return false
        }

        previous = current
        return true
    }

    nonisolated func cancel() {
        baseline.cancel()
    }

    func close() async {
        active = false
        baseline.cancel()
        _ = await baseline.value
        previous = nil
    }

    private static func inventory(_ root: URL) -> [String: String] {
        let access = FileAccessLease(urls: [root], adapter: .native)
        defer { access.release() }
        var state = [String: String]()
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey, .fileResourceIdentifierKey]
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys), errorHandler: { url, _ in
            state[url.path] = "unavailable"
            return true
        }) else {
            return [root.path: "unavailable"]
        }

        let rules = ProjectIgnoreRules(root: root)
        for case let url as URL in files {
            if Task.isCancelled {
                return state
            }
            guard let values = try? url.resourceValues(forKeys: keys) else {
                state[url.path] = "unavailable"
                continue
            }

            if values.isSymbolicLink == true || url.lastPathComponent == ".git" {
                files.skipDescendants()
                continue
            }
            if url.lastPathComponent != ".gitignore", (try? rules.ignores(url, isDirectory: values.isDirectory == true)) == true {
                if values.isDirectory == true {
                    files.skipDescendants()
                }
                continue
            }
            if url.lastPathComponent == ".gitignore" || url.pathComponents.contains(where: { $0.hasSuffix(".xcassets") }) {
                var attributes = stat()
                let status = url.path.withCString { lstat($0, &attributes) }
                let changed = status == 0 ? "\(attributes.st_ctimespec.tv_sec):\(attributes.st_ctimespec.tv_nsec)" : "unavailable"
                state[url.path] = "\(changed):\(values.fileSize ?? 0):\(values.contentModificationDate?.timeIntervalSince1970 ?? 0):\(values.creationDate?.timeIntervalSince1970 ?? 0):\(String(describing: values.fileResourceIdentifier))"
            }
        }
        return state
    }
}

// MARK: - ProjectObservationAdapter

/// The session owns observation lifetime. Fixtures can supply events without a filesystem.
struct ProjectObservationAdapter: Sendable {
    let start: @MainActor @Sendable (URL, @escaping @MainActor @Sendable () -> Void) throws -> ProjectObservation?

    static let native = ProjectObservationAdapter { root, changed in
        guard let observation = ProjectObservation(root: root, changed: changed) else {
            throw CocoaError(.fileReadUnknown)
        }

        return observation
    }

    static let disabled = ProjectObservationAdapter { _, _ in nil }
}

// MARK: - ProjectObservation

@MainActor
final class ProjectObservation {
    private var stream: FSEventStreamRef?
    private let files: CatalogFileState

    func ready() async {
        await files.ready()
    }

    func close() async {
        stop()
        await files.close()
    }

    private final class Callback: Sendable {
        let changed: @MainActor @Sendable () -> Void
        let root: String
        let files: CatalogFileState
        init(root: String, files: CatalogFileState, changed: @escaping @MainActor @Sendable () -> Void) {
            self.root = root
            self.files = files
            self.changed = changed
        }
    }

    init?(root: URL, changed: @escaping @MainActor @Sendable () -> Void) {
        let root = root.resolvingSymlinksInPath()
        files = CatalogFileState(root: root)
        let path = root.path
        let callback = Callback(root: path, files: files, changed: changed)
        var context = FSEventStreamContext(version: 0,
                                           info: Unmanaged.passUnretained(callback).toOpaque(),
                                           retain: { info in
                                               guard let info else {
                                                   return nil
                                               }

                                               _ = Unmanaged<Callback>.fromOpaque(info).retain()
                                               return info
                                           },
                                           release: { info in
                                               if let info {
                                                   Unmanaged<Callback>.fromOpaque(info).release()
                                               }
                                           }, copyDescription: nil)
        stream = FSEventStreamCreate(nil, { _, info, count, paths, flags, _ in
            guard let info else {
                return
            }

            let callback = Unmanaged<Callback>.fromOpaque(info).takeUnretainedValue()
            let paths = paths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
            let recoveryFlags = UInt32(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagRootChanged | kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagEventIdsWrapped)
            let relevant = (0 ..< count).contains { index in
                let path = String(cString: paths[index])
                guard path == callback.root || path.hasPrefix(callback.root + "/") else {
                    return false
                }

                if flags[index] & recoveryFlags != 0 {
                    return true
                }
                let components = URL(fileURLWithPath: path).pathComponents
                if components.contains(".git") {
                    return false
                }
                return path == callback.root || components.contains(where: { $0.hasSuffix(".xcassets") }) ||
                    components.last == ".gitignore" || flags[index] & UInt32(kFSEventStreamEventFlagItemIsDir) != 0
            }
            if relevant {
                Task { @MainActor in
                    if await callback.files.changed() {
                        callback.changed()
                    }
                }
            }
        }, &context, [path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.15,
        UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot))
        guard let stream else {
            return nil
        }

        FSEventStreamSetDispatchQueue(stream, .main)
        guard FSEventStreamStart(stream) else {
            stop()
            return nil
        }
    }

    func stop() {
        files.cancel()
        guard let stream else {
            return
        }

        self.stream = nil
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    isolated deinit { stop() }
}
