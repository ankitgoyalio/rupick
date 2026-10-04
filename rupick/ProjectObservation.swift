// swiftformat:disable acronyms
import CoreServices
import Darwin
import Foundation

// MARK: - ProjectCatalogInventory

/// One traversal supplies both the observation baseline and initial catalog discovery.
struct ProjectCatalogInventory: Sendable {
    let root: URL
    var metadata = [String: String]()
    var entries = [URL]()
    var skipped = 0
    var error: String?

    static func read(_ root: URL, observingChanges: Bool = true) -> Self {
        let root = ProjectFileLocation.canonical(root)
        let access = FileAccessLease(urls: [root], adapter: .native)
        defer { access.release() }
        var inventory = Self(root: root)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            inventory.error = "The project folder is unavailable. Choose it again."
            inventory.metadata[root.path] = "unavailable"
            return inventory
        }

        let keys: Set<URLResourceKey> = observingChanges
            ? [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey, .fileResourceIdentifierKey]
            : [.isDirectoryKey, .isSymbolicLinkKey]
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys), errorHandler: { url, _ in
            inventory.metadata[url.path] = "unavailable"
            inventory.skipped += 1
            return true
        }) else {
            inventory.error = "The project folder could not be read. Choose it again."
            inventory.metadata[root.path] = "unavailable"
            return inventory
        }

        let rules = ProjectIgnoreRules(root: root)
        for case let url as URL in files {
            if Task.isCancelled {
                return inventory
            }
            guard let values = try? url.resourceValues(forKeys: keys) else {
                inventory.metadata[url.path] = "unavailable"
                inventory.skipped += 1
                continue
            }

            if values.isSymbolicLink == true || url.lastPathComponent == ".git" {
                files.skipDescendants()
                continue
            }
            do {
                let ignored = try rules.ignores(url, isDirectory: values.isDirectory == true)
                if ignored, observingChanges == false || url.lastPathComponent != ".gitignore" {
                    if values.isDirectory == true {
                        files.skipDescendants()
                    }
                    continue
                }
                if url.pathExtension == "imageset", values.isDirectory == true, ignored == false {
                    if observingChanges == false {
                        files.skipDescendants()
                    }
                    var parent = url.deletingLastPathComponent()
                    while parent.path != root.path, parent.pathExtension != "xcassets", parent.pathExtension != "imageset" {
                        parent.deleteLastPathComponent()
                    }
                    if parent.pathExtension == "xcassets",
                       try rules.ignores(url.appendingPathComponent("Contents.json"), isDirectory: false) == false
                    {
                        inventory.entries.append(url)
                    }
                }
            } catch {
                inventory.error = "The project's Git ignore rules could not be read. Check folder access and try again."
                inventory.metadata[url.path] = "unavailable"
                return inventory
            }
            if observingChanges, url.lastPathComponent == ".gitignore" || url.pathComponents.contains(where: { $0.hasSuffix(".xcassets") }) {
                var attributes = stat()
                let status = url.path.withCString { lstat($0, &attributes) }
                let changed = status == 0 ? "\(attributes.st_ctimespec.tv_sec):\(attributes.st_ctimespec.tv_nsec)" : "unavailable"
                inventory.metadata[url.path] = "\(changed):\(values.fileSize ?? 0):\(values.contentModificationDate?.timeIntervalSince1970 ?? 0):\(values.creationDate?.timeIntervalSince1970 ?? 0):\(String(describing: values.fileResourceIdentifier))"
            }
        }
        inventory.entries.sort { $0.path < $1.path }
        return inventory
    }
}

// MARK: - CatalogFileState

/// Metadata reconciliation runs off the UI actor and suppresses duplicate kernel events.
private actor CatalogFileState {
    private let root: URL
    private let baseline: Task<ProjectCatalogInventory, Never>
    private var initialInventory: ProjectCatalogInventory?
    private var active = true
    private var previous: [String: String]?

    init(root: URL) {
        self.root = root
        baseline = Task.detached { ProjectCatalogInventory.read(root) }
    }

    func ready() async {
        guard previous == nil else {
            return
        }

        let initial = await baseline.value
        if active, previous == nil {
            previous = initial.metadata
            initialInventory = initial
        }
    }

    func takeInitialInventory() async -> ProjectCatalogInventory? {
        await ready()
        defer { initialInventory = nil }
        return initialInventory
    }

    func changed() async -> Bool {
        await ready()
        guard active else {
            return false
        }

        let current = ProjectCatalogInventory.read(root).metadata
        guard current != previous else {
            return false
        }

        previous = current
        initialInventory = nil
        return true
    }

    nonisolated func cancel() {
        baseline.cancel()
    }

    func close() async {
        active = false
        baseline.cancel()
        _ = await baseline.value
        initialInventory = nil
        previous = nil
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

    func takeInitialInventory() async -> ProjectCatalogInventory? {
        await files.takeInitialInventory()
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
        let root = ProjectFileLocation.canonical(root)
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
