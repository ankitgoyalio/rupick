import CoreImage
import CryptoKit
import Darwin
import Foundation
import ImageIO
import Synchronization
import UniformTypeIdentifiers

// MARK: - NormalizedImage

private struct NormalizedImage {
    let image: CIImage
    let width: Int
    let height: Int

    /// Inspect the same source bytes that will be decoded. Reject oversized headers
    /// before ImageIO allocates a bitmap, and reserve the floating-point output size.
    static func decodedByteCount(data: Data) throws -> Int {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source),
              [UTType.png.identifier, UTType.jpeg.identifier].contains(type as String),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = (properties[kCGImagePropertyPixelWidth as String] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight as String] as? NSNumber)?.intValue
        else {
            throw CocoaError(.fileReadCorruptFile)
        }

        guard width > 0, height > 0, width <= 8192, height <= 8192,
              width * height <= 16_777_216
        else {
            throw CocoaError(.fileReadTooLarge)
        }

        return width * height * 4 * MemoryLayout<Float>.size
    }

    static func makeContext() -> CIContext {
        CIContext(options: [.useSoftwareRenderer: true, .outputPremultiplied: false,
                            .workingFormat: CIFormat.RGBAf,
                            .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedSRGB)!])
    }

    init(data: Data) throws {
        _ = try Self.decodedByteCount(data: data)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source),
              [UTType.png.identifier, UTType.jpeg.identifier].contains(type as String),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        let orientation = (properties?[kCGImagePropertyOrientation as String] as? NSNumber)?.int32Value ?? 1
        image = CIImage(cgImage: cgImage).oriented(forExifOrientation: orientation)
        width = Int(image.extent.width); height = Int(image.extent.height)
        // Bound temporary decode memory; an oversized file is reported, never called a non-match.
        guard width > 0, height > 0, width <= 8192, height <= 8192,
              width * height <= 16_777_216
        else {
            throw CocoaError(.fileReadTooLarge)
        }
    }
}

// MARK: - ImageDecodeBudget

/// Bound concurrent normalized buffers across retiring and replacement scans.
/// Framework working buffers and source bytes are additional to this allowance.
private actor ImageDecodeBudget {
    static let capacity = 512 * 1024 * 1024
    private struct Waiter {
        let bytes: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private var used = 0
    private var waiters = [Waiter]()

    func acquire(bytes: Int) async {
        // A request that fills the allowance runs alone.
        let bytes = min(bytes, Self.capacity)
        if waiters.isEmpty, used + bytes <= Self.capacity {
            used += bytes
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(Waiter(bytes: bytes, continuation: continuation))
        }
    }

    func release(bytes: Int) {
        used -= min(bytes, Self.capacity)
        while let first = waiters.first, used + first.bytes <= Self.capacity {
            waiters.removeFirst()
            used += first.bytes
            first.continuation.resume()
        }
    }
}

// MARK: - DecodedPixels

private struct DecodedPixels: Equatable, Sendable {
    let width: Int
    let height: Int
    let values: [Float]

    init(image: NormalizedImage, context: CIContext) {
        let width = image.width
        let height = image.height
        self.width = width; self.height = height
        var pixels = [Float](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes {
            context.render(image.image, toBitmap: $0.baseAddress!, rowBytes: width * 16,
                           bounds: image.image.extent, format: .RGBAf,
                           colorSpace: CGColorSpace(name: CGColorSpace.extendedSRGB)!)
        }
        pixels.withUnsafeMutableBufferPointer { buffer in
            let pointer = buffer.baseAddress!
            for offset in stride(from: 0, to: buffer.count, by: 4) {
                if pointer[offset + 3] == 0 {
                    pointer[offset] = 0; pointer[offset + 1] = 0; pointer[offset + 2] = 0
                }
                // Float equality treats negative zero as zero. Canonicalize it before hashing.
                for channel in 0 ..< 4 where pointer[offset + channel] == 0 {
                    pointer[offset + channel] = 0
                }
            }
        }
        values = pixels
    }
}

// MARK: - PixelFingerprint

private struct PixelFingerprint: Hashable, Sendable {
    let width: Int
    let height: Int
    let digest: SHA256.Digest
    let version: String

    /// Source-byte versions track review freshness without changing exact pixel matching.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.width == rhs.width && lhs.height == rhs.height && lhs.digest == rhs.digest
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(width)
        hasher.combine(height)
        hasher.combine(digest)
    }

    init(_ pixels: DecodedPixels, source: Data) {
        width = pixels.width; height = pixels.height
        digest = pixels.values.withUnsafeBytes { SHA256.hash(data: $0) }
        version = SHA256.hash(data: source).description
    }
}

// MARK: - CatalogContents

private struct CatalogContents: Decodable {
    struct Image: Decodable {
        struct Appearance: Decodable { let appearance: String; let value: String }
        let filename: String?
        let idiom: String?
        let scale: String?
        let appearances: [Appearance]?
        var label: String {
            ([idiom ?? "universal", scale ?? "any scale"] +
                (appearances ?? []).map { "\($0.appearance): \($0.value)" }).joined(separator: " · ")
        }
    }

    let images: [Image]
}

// MARK: - ContentBucket

private struct ContentBucket {
    let reference: URL
    var members = [AssetCandidate]()
}

// MARK: - CatalogComparisonCache

/// Per-session cache. Byte identity handles atomic replacement and preserved timestamps.
/// Only immutable pixels cross workers; both entry count and decoded memory are bounded.
final class CatalogComparisonCache: Sendable {
    // CIContext is immutable and Sendable in the SDK and supports concurrent rendering.
    // Share its working resources instead of allocating a renderer for every worker.
    fileprivate let context = NormalizedImage.makeContext()
    private let decodeBudget = ImageDecodeBudget()
    private struct Entry: Sendable {
        let digest: SHA256.Digest
        let pixels: DecodedPixels
        let source: Data
        var cost: Int {
            pixels.values.count * MemoryLayout<Float>.size + source.count
        }
    }

    private struct Identity: Hashable, Sendable {
        let url: URL
        let size: Int64
        let inode: UInt64
        let modifiedSeconds: Int
        let modifiedNanoseconds: Int
        let changedSeconds: Int
        let changedNanoseconds: Int

        init(url: URL) throws {
            var attributes = stat()
            guard url.path.withCString({ stat($0, &attributes) }) == 0 else {
                throw CocoaError(.fileReadUnknown)
            }

            self.url = url
            size = attributes.st_size
            inode = attributes.st_ino
            modifiedSeconds = attributes.st_mtimespec.tv_sec
            modifiedNanoseconds = attributes.st_mtimespec.tv_nsec
            changedSeconds = attributes.st_ctimespec.tv_sec
            changedNanoseconds = attributes.st_ctimespec.tv_nsec
        }
    }

    private struct Verification: Hashable, Sendable {
        let first: Identity
        let second: Identity
    }

    private struct Records: Sendable {
        var fingerprints = [Identity: PixelFingerprint]()
        var verified = Set<Verification>()
        var decoded = 0
    }

    private let records = Mutex(Records())

    fileprivate var decodedImageCount: Int {
        records.withLock { $0.decoded }
    }

    fileprivate func retain(sources: Set<URL>) {
        records.withLock { records in
            records.fingerprints = records.fingerprints.filter { sources.contains($0.key.url) }
            records.verified = records.verified.filter { sources.contains($0.first.url) && sources.contains($0.second.url) }
        }
    }

    fileprivate func fingerprint(url: URL, context: CIContext) throws -> PixelFingerprint {
        let identity = try Identity(url: url)
        if let fingerprint = records.withLock({ $0.fingerprints[identity] }) {
            return fingerprint
        }
        return try fingerprint(data: Data(contentsOf: url), identity: identity, context: context)
    }

    fileprivate func prepareFingerprint(url: URL) async throws -> PixelFingerprint {
        try Task.checkCancellation()
        let identity = try Identity(url: url)
        if let fingerprint = records.withLock({ $0.fingerprints[identity] }) {
            return fingerprint
        }
        let data = try Data(contentsOf: url)
        let bytes = autoreleasepool {
            (try? NormalizedImage.decodedByteCount(data: data)) ?? ImageDecodeBudget.capacity
        }
        await decodeBudget.acquire(bytes: bytes)
        // Queued cancellations still retire their reservation after the active decoder
        // finishes. No cancelled waiter starts a decode or leaves a permit stranded.
        let result = Result {
            try Task.checkCancellation()
            return try autoreleasepool { try fingerprint(data: data, identity: identity, context: context) }
        }
        await decodeBudget.release(bytes: bytes)
        return try result.get()
    }

    private func fingerprint(data: Data, identity: Identity, context: CIContext) throws -> PixelFingerprint {
        let url = identity.url
        let fingerprint = try PixelFingerprint(pixels(data: data, context: context), source: data)
        guard try identity == Identity(url: url) else {
            throw CocoaError(.fileReadUnknown)
        }

        records.withLock { records in
            records.fingerprints = records.fingerprints.filter { $0.key.url != url }
            records.verified = records.verified.filter { $0.first.url != url && $0.second.url != url }
            records.fingerprints[identity] = fingerprint
        }
        return fingerprint
    }

    fileprivate func equal(_ first: URL, _ second: URL, context: CIContext) throws -> Bool {
        let key = try Verification(first: Identity(url: first), second: Identity(url: second))
        if records.withLock({ $0.verified.contains(key) }) {
            return true
        }
        let equal = try pixels(url: first, context: context) == pixels(url: second, context: context)
        if equal, try key.first == Identity(url: first), try key.second == Identity(url: second) {
            records.withLock { _ = $0.verified.insert(key) }
        }
        return equal
    }

    private let entries = Mutex<[Entry]>([])

    fileprivate func pixels(url: URL, context: CIContext) throws -> DecodedPixels {
        try pixels(data: Data(contentsOf: url), context: context)
    }

    private func pixels(data: Data, context: CIContext) throws -> DecodedPixels {
        let digest = SHA256.hash(data: data)
        if let cached = entries.withLock({ entries -> DecodedPixels? in
            guard let index = entries.firstIndex(where: { $0.digest == digest && $0.source == data }) else {
                return nil
            }

            let entry = entries.remove(at: index)
            entries.append(entry)
            return entry.pixels
        }) {
            return cached
        }
        records.withLock { $0.decoded += 1 }
        let pixels = try DecodedPixels(image: NormalizedImage(data: data), context: context)
        let entry = Entry(digest: digest, pixels: pixels, source: data)
        if entry.cost <= 32 * 1024 * 1024 {
            entries.withLock { entries in
                entries.removeAll { $0.digest == digest }
                while entries.isEmpty == false, entries.count >= 128 || entries.reduce(0, { $0 + $1.cost }) + entry.cost > 32 * 1024 * 1024 {
                    entries.removeFirst()
                }
                entries.append(entry)
            }
        }
        return pixels
    }
}

// MARK: - CatalogComparison

enum CatalogComparison {
    private struct PreparedRepresentation: Sendable {
        let id: String
        let url: URL
        let label: String
        let fingerprint: PixelFingerprint?
    }

    private struct PreparedEntry: Sendable {
        let url: URL
        var representations = [PreparedRepresentation]()
        var skipped = 0
    }

    private actor PreparationWorker {
        private let root: URL
        private let cache: CatalogComparisonCache
        private let rules: ProjectIgnoreRules

        init(root: URL, cache: CatalogComparisonCache) {
            self.root = root
            self.cache = cache
            rules = ProjectIgnoreRules(root: root)
        }

        func prepare(entry: URL) async -> PreparedEntry {
            var prepared = PreparedEntry(url: entry)
            func withinRoot(_ url: URL) -> Bool {
                let path = ProjectFileLocation.canonical(url).path
                return path.hasPrefix(root.path.hasSuffix("/") ? root.path : root.path + "/")
            }
            do {
                let contentsURL = entry.appendingPathComponent("Contents.json")
                guard withinRoot(contentsURL), try contentsURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
                    throw CocoaError(.fileReadNoPermission)
                }

                let contents = try JSONDecoder().decode(CatalogContents.self, from: Data(contentsOf: contentsURL))
                for (index, image) in contents.images.enumerated() {
                    if Task.isCancelled {
                        return prepared
                    }
                    guard let filename = image.filename else {
                        continue
                    }

                    let url = entry.appendingPathComponent(filename)
                    guard url.deletingLastPathComponent().standardizedFileURL == entry.standardizedFileURL else {
                        prepared.skipped += 1
                        continue
                    }

                    if try rules.ignores(url, isDirectory: false) {
                        continue
                    }
                    guard withinRoot(url), (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else {
                        prepared.skipped += 1
                        continue
                    }

                    let fingerprint = try? await cache.prepareFingerprint(url: url)
                    if fingerprint == nil {
                        prepared.skipped += 1
                    }
                    prepared.representations.append(PreparedRepresentation(id: url.path + "#" + String(index), url: url,
                                                                           label: image.label, fingerprint: fingerprint))
                }
            } catch {
                prepared.representations = []
                prepared.skipped += 1
            }
            return prepared
        }
    }

    static func run(root: URL, incoming: [URL], cache: CatalogComparisonCache = CatalogComparisonCache(), inventory: ProjectCatalogInventory? = nil, publish: @Sendable (ScanSnapshot) async -> Void) async {
        let initialDecodes = cache.decodedImageCount
        var snapshot = ScanSnapshot(results: incoming.map { IncomingResult(url: $0) })
        let boundary = ProjectFileLocation.canonical(root)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: boundary.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            snapshot.error = "The project folder is unavailable. Choose it again."
            await publish(snapshot); return
        }

        let inventory =
            if let inventory, inventory.root.path == boundary.path {
                inventory
            } else {
                ProjectCatalogInventory.read(boundary, observingChanges: false)
            }
        guard Task.isCancelled == false else {
            return
        }

        snapshot.skipped = inventory.skipped
        snapshot.error = inventory.error
        snapshot.discovered = inventory.entries.count
        await publish(snapshot)
        guard inventory.error == nil else {
            return
        }

        let entries = inventory.entries
        let context = cache.context
        var sources = Set(incoming)
        var incomingFingerprints = [PixelFingerprint?]()
        var buckets = [PixelFingerprint: [ContentBucket]]()
        snapshot.phase = "Reading incoming images…"
        for index in incoming.indices {
            if Task.isCancelled {
                return
            }
            snapshot.results[index].status = .decoding
            await publish(snapshot)
            do {
                try incomingFingerprints.append(autoreleasepool {
                    try cache.fingerprint(url: incoming[index], context: context)
                })
                snapshot.results[index].contentVersion = incomingFingerprints.last.flatMap { $0 }?.version
            } catch {
                // Review freshness still follows source bytes when decoding is unavailable.
                snapshot.results[index].contentVersion = (try? Data(contentsOf: incoming[index])).map {
                    SHA256.hash(data: $0).description
                }
                snapshot.results[index].needsRecovery = FileManager.default.isReadableFile(atPath: incoming[index].path) == false
                snapshot.results[index].status = .unreadable
                incomingFingerprints.append(nil)
                snapshot.results[index].error = snapshot.results[index].needsRecovery
                    ? "This image is missing or inaccessible. Locate it to restore access."
                    : "Could not read this PNG or JPEG. Check file access or choose another image, up to 16 megapixels and 8,192 pixels per side."
            }
            if snapshot.results[index].error == nil {
                snapshot.results[index].status = .comparing
            }
            snapshot.decoded += 1
            await publish(snapshot)
        }
        snapshot.phase = "Comparing image assets…"
        await publish(snapshot)
        // Each batch bounds both active decoders and completed work waiting for ordered assembly.
        let parallelism = min(4, max(1, ProcessInfo.processInfo.activeProcessorCount))
        let workers = (0 ..< parallelism).map { _ in PreparationWorker(root: boundary, cache: cache) }
        for start in stride(from: 0, to: entries.count, by: parallelism) {
            if Task.isCancelled {
                return
            }
            let end = min(start + parallelism, entries.count)
            let prepared = await withTaskGroup(of: PreparedEntry.self, returning: [PreparedEntry].self) { group in
                for index in start ..< end {
                    let entry = entries[index]
                    let worker = workers[index - start]
                    group.addTask {
                        await worker.prepare(entry: entry)
                    }
                }
                var batch = [PreparedEntry]()
                for await entry in group {
                    batch.append(entry)
                }
                return batch.sorted { $0.url.path < $1.url.path }
            }
            for preparedEntry in prepared {
                if Task.isCancelled {
                    return
                }
                let entry = preparedEntry.url
                snapshot.skipped += preparedEntry.skipped
                var variants = [(id: String, url: URL, label: String, matchingInputs: Set<Int>)]()
                var entryBuckets = [(fingerprint: PixelFingerprint, index: Int, representationID: String)]()
                for representation in preparedEntry.representations {
                    if Task.isCancelled {
                        return
                    }
                    let url = representation.url
                    let representationID = representation.id
                    sources.insert(url)
                    let matchingInputs: Set<Int> = autoreleasepool {
                        guard let fingerprint = representation.fingerprint else {
                            return []
                        }

                        var contentBuckets = buckets[fingerprint, default: []]
                        let bucketIndex = contentBuckets.firstIndex {
                            (try? cache.equal($0.reference, url, context: context)) == true
                        } ?? contentBuckets.count
                        if bucketIndex == contentBuckets.count {
                            contentBuckets.append(ContentBucket(reference: url))
                        }
                        buckets[fingerprint] = contentBuckets
                        entryBuckets.append((fingerprint, bucketIndex, representationID))
                        // Hash only narrows the search. Verify every actual match with component equality.
                        return Set(incoming.indices.filter { index in
                            guard incomingFingerprints[index] == fingerprint else {
                                return false
                            }

                            return (try? cache.equal(incoming[index], url, context: context)) == true
                        })
                    }
                    variants.append((representationID, url, representation.label, matchingInputs))
                }
                let location = String(entry.path.dropFirst(boundary.path.hasSuffix("/") ? boundary.path.count : boundary.path.count + 1))
                func candidate(matchingIDs: Set<String>) -> AssetCandidate {
                    AssetCandidate(id: entry.path, name: entry.deletingPathExtension().lastPathComponent,
                                   location: location, representations: variants.map { variant in
                                       Representation(id: variant.id, url: variant.url, label: variant.label,
                                                      matches: matchingIDs.contains(variant.id),
                                                      contentVersion: preparedEntry.representations.first(where: { $0.id == variant.id })?.fingerprint?.version)
                                   })
                }
                // An asset appears once in each content group, with all its alternatives available.
                var updated = Set<String>()
                for content in entryBuckets {
                    let groupID = buckets[content.fingerprint]![content.index].reference.path
                    guard updated.insert(groupID).inserted else {
                        continue
                    }

                    let matchingIDs = Set(entryBuckets.filter {
                        $0.fingerprint == content.fingerprint && $0.index == content.index
                    }
                    .map(\.representationID))
                    let member = candidate(matchingIDs: matchingIDs)
                    buckets[content.fingerprint]![content.index].members.append(member)
                    let bucket = buckets[content.fingerprint]![content.index]
                    if bucket.members.count >= 2 {
                        let group = DuplicateGroup(id: groupID, members: bucket.members)
                        if let index = snapshot.duplicateGroups.firstIndex(where: { $0.id == groupID }) {
                            snapshot.duplicateGroups[index] = group
                        } else {
                            snapshot.duplicateGroups.append(group)
                        }
                    }
                }
                for index in incoming.indices {
                    guard variants.contains(where: { $0.matchingInputs.contains(index) }) else {
                        continue
                    }

                    let matchingIDs = Set(variants.filter { $0.matchingInputs.contains(index) }.map(\.id))
                    snapshot.results[index].candidates.append(candidate(matchingIDs: matchingIDs))
                }
                snapshot.compared += 1
                await publish(snapshot)
            }
        }
        if Task.isCancelled == false {
            cache.retain(sources: sources)
            snapshot.imageDecodes = cache.decodedImageCount - initialDecodes
            await publish(snapshot)
        }
    }
}
