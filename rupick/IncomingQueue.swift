import Foundation
import UniformTypeIdentifiers

// MARK: - IncomingQueue

/// Session-owned intake for picker selections and asynchronous file providers.
/// Register before loading, then complete a whole selection or individual slots.
/// Only a completed prefix is settled, preserving batch and file submission order.
/// Reset invalidates all pending callbacks and releases their file-access leases.
@MainActor
final class IncomingQueue {
    struct Settlement {
        let urls: [URL]
        let access: [URL: FileAccessLease]
        let rejected: Bool
    }

    private struct Batch {
        let id: UUID
        var urls: [URL?]
        var remaining: Set<Int>
        var access = [URL: FileAccessLease]()
    }

    private let access: FileAccessAdapter
    private var batches = [Batch]()

    var hasPending: Bool {
        batches.isEmpty == false
    }

    init(access: FileAccessAdapter) {
        self.access = access
    }

    func begin(count: Int) -> UUID? {
        guard count > 0 else {
            return nil
        }

        let id = UUID()
        batches.append(Batch(id: id, urls: Array(repeating: nil, count: count), remaining: Set(0 ..< count)))
        return id
    }

    /// A picker reserves one slot before its final selection count is known.
    func receive(_ urls: [URL], batch: UUID, excluding accepted: [URL]) -> Settlement? {
        guard let index = batches.firstIndex(where: { $0.id == batch }),
              batches[index].remaining.isEmpty == false
        else {
            return nil
        }

        batches[index].urls = urls.map { Optional($0) }
        batches[index].remaining = []
        for url in urls {
            acquire(url, at: index)
        }
        return settle(excluding: accepted)
    }

    func receive(_ url: URL?, batch: UUID, index: Int, excluding accepted: [URL]) -> Settlement? {
        guard let batchIndex = batches.firstIndex(where: { $0.id == batch }),
              batches[batchIndex].remaining.remove(index) != nil
        else {
            return nil
        }

        batches[batchIndex].urls[index] = url
        if let url {
            acquire(url, at: batchIndex)
        }
        return settle(excluding: accepted)
    }

    func abandon(batch: UUID, excluding accepted: [URL]) -> Settlement? {
        guard let index = batches.firstIndex(where: { $0.id == batch }) else {
            return nil
        }

        batches.remove(at: index)
        return settle(excluding: accepted)
    }

    func reset() {
        batches = []
    }

    private func acquire(_ url: URL, at index: Int) {
        if batches[index].access[url] == nil {
            batches[index].access[url] = FileAccessLease(urls: [url], adapter: access)
        }
    }

    /// Accepted leases travel with the URLs; rejected and duplicate leases retire here.
    private func settle(excluding accepted: [URL]) -> Settlement? {
        var seen = Set(accepted)
        var urls = [URL]()
        var leases = [URL: FileAccessLease]()
        var rejected = false
        var settled = false
        while let first = batches.first, first.remaining.isEmpty {
            let batch = batches.removeFirst()
            settled = true
            for url in batch.urls {
                guard let url, url.isFileURL,
                      let type = UTType(filenameExtension: url.pathExtension),
                      type.conforms(to: .png) || type.conforms(to: .jpeg)
                else {
                    rejected = true
                    continue
                }

                if seen.insert(url).inserted {
                    urls.append(url)
                    leases[url] = batch.access[url]
                }
            }
        }
        return settled ? Settlement(urls: urls, access: leases, rejected: rejected) : nil
    }
}
