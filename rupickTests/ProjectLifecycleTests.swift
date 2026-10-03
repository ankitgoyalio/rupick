import Foundation
@testable import rupick
import Synchronization
import Testing

// MARK: - ProjectLifecycleTests

@MainActor
struct ProjectLifecycleTests {
    private let root = URL(fileURLWithPath: "/project")
    private let first = URL(fileURLWithPath: "/incoming/first.png")
    private let second = URL(fileURLWithPath: "/incoming/second.jpe")

    @Test func reopeningSameFolderStartsFreshAndRejectsOldIntake() async throws {
        let scan = ControlledScan()
        let access = AccessRecorder()
        let session = makeSession(scan: scan, access: access)
        let work = session.open(root: root, incoming: [first])
        await scan.waitForRequests(1)
        await scan.complete(0, snapshot: snapshot(incoming: [first], groups: [group("old")]))
        await work.value
        let oldID = session.id
        let oldStore = session.thumbnails.id
        let invalid = try #require(session.beginIncoming(count: 1))
        session.receiveIncoming(URL(fileURLWithPath: "/unsupported.svg"), batch: invalid, index: 0)
        #expect(session.notice != nil)
        let pending = try #require(session.beginIncoming(count: 1))
        let reopen = session.open(root: root)
        #expect(session.id != oldID)
        #expect(session.thumbnails.id != oldStore)
        #expect(session.results.isEmpty && session.duplicateGroups.isEmpty)
        #expect(session.selection == nil && session.notice == nil)
        session.receiveIncoming(first, batch: pending, index: 0)
        #expect(session.results.isEmpty)
        await scan.waitForRequests(2)
        await scan.complete(1, snapshot: snapshot())
        await reopen.value
        await session.close().value
        #expect(access.isBalanced)
    }

    @Test func refreshPinsReviewRepresentationFallbackBeforeAlternativeReturns() async {
        let scan = ControlledScan()
        let session = makeSession(scan: scan)
        let exact = Representation(id: "exact", url: first, label: "Exact", matches: true)
        let alternative = Representation(id: "alternative", url: second, label: "Alternative", matches: false)
        func result(_ representations: [Representation]) -> IncomingResult {
            IncomingResult(url: first, candidates: [AssetCandidate(id: "asset", name: "Asset", location: "Assets", representations: representations)])
        }
        let opening = session.open(root: root, incoming: [first])
        await scan.waitForRequests(1)
        await scan.complete(0, snapshot: ScanSnapshot(results: [result([exact, alternative])]))
        await opening.value
        session.selectRepresentation(for: first, candidateID: "asset", representationID: alternative.id)
        session.keepAsNew(first)
        let refresh = session.refresh(incoming: [first])
        await scan.waitForRequests(2)
        await scan.complete(1, snapshot: ScanSnapshot(results: [result([exact])]))
        await refresh.value
        #expect(session.review(for: first).representationIDs["asset"] == exact.id)
        #expect(session.review(for: first).outcome == .keepAsNew)
        let restored = session.refresh(incoming: [first])
        await scan.waitForRequests(3)
        await scan.complete(2, snapshot: ScanSnapshot(results: [result([exact, alternative])]))
        await restored.value
        #expect(session.review(for: first).representationIDs["asset"] == exact.id)
        await session.close().value
    }

    @Test func batchesAndFilesRetainSubmissionOrderDespiteReverseCompletion() async throws {
        let scan = ControlledScan()
        let access = AccessRecorder()
        let session = makeSession(scan: scan, access: access)
        let initial = session.open(root: root)
        await scan.waitForRequests(1)
        await scan.complete(0, snapshot: snapshot())
        await initial.value
        let earlier = try #require(session.beginIncoming(count: 4))
        let later = try #require(session.beginIncoming(count: 2))
        let third = URL(fileURLWithPath: "/incoming/third.png")
        session.receiveIncoming(third, batch: later, index: 1)
        session.receiveIncoming(second, batch: later, index: 0)
        #expect(session.results.isEmpty)
        #expect(access.active(third) == 1)
        session.receiveIncoming(nil, batch: earlier, index: 3)
        session.receiveIncoming(URL(fileURLWithPath: "/incoming/text.txt"), batch: earlier, index: 2)
        session.receiveIncoming(second, batch: earlier, index: 1)
        session.receiveIncoming(first, batch: earlier, index: 0)
        // Repeated provider completion must not accept a new file or change order.
        session.receiveIncoming(third, batch: earlier, index: 0)
        #expect(session.results.map(\.url) == [first, second, third])
        #expect(session.notice != nil)
        #expect(session.hasPendingIncoming == false)
        await scan.waitForRequests(2)
        #expect(await scan.inputs(1) == [first, second, third])
        let closing = session.close()
        await scan.complete(1, snapshot: snapshot(incoming: [first, second, third]))
        await closing.value
        #expect(access.isBalanced)
    }

    @Test(arguments: [false, true])
    func failedOrAbandonedBatchAllowsLaterBatchToAdvance(abandon: Bool) async throws {
        let scan = ControlledScan()
        let session = makeSession(scan: scan)
        let opening = session.open(root: root)
        await scan.waitForRequests(1)
        await scan.complete(0, snapshot: snapshot())
        await opening.value
        let earlier = try #require(session.beginIncoming(count: 1))
        let later = try #require(session.beginIncoming(count: 1))
        session.receiveIncoming([second], batch: later)
        #expect(session.results.isEmpty)
        if abandon {
            session.abandonIncoming(batch: earlier)
        } else {
            session.receiveIncoming(nil, batch: earlier, index: 0)
        }
        #expect(session.results.map(\.url) == [second])
        #expect((session.notice != nil) == (abandon == false))
        await scan.waitForRequests(2)
        let closing = session.close()
        await scan.complete(1, snapshot: snapshot(incoming: [second]))
        await closing.value
    }

    @Test func cancelRetainsInspectionButDiscardsPendingIntakeAndLateScan() async throws {
        let scan = ControlledScan()
        let access = AccessRecorder()
        let session = makeSession(scan: scan, access: access)
        let work = session.open(root: root, incoming: [first])
        await scan.waitForRequests(1)
        let provisional = snapshot(incoming: [first], groups: [group("kept")])
        await scan.publish(0, snapshot: provisional)
        session.select(.group("kept"))
        let store = session.thumbnails.id
        let pending = try #require(session.beginIncoming(count: 1))
        let later = try #require(session.beginIncoming(count: 1))
        session.receiveIncoming(second, batch: later, index: 0)
        session.cancel()
        #expect(session.state == .cancelled)
        #expect(session.results[0].status == .incomplete)
        #expect(session.selection == .group("kept"))
        #expect(session.thumbnails.id == store)
        #expect(access.active(second) == 0)
        session.receiveIncoming(second, batch: pending, index: 0)
        await scan.complete(0, snapshot: snapshot())
        await work.value
        #expect(session.state == .cancelled)
        #expect(session.duplicateGroups == provisional.duplicateGroups)
        #expect(session.results.map(\.url) == [first])
        let newBatch = try #require(session.beginIncoming(count: 1))
        session.receiveIncoming([second], batch: newBatch)
        #expect(session.state == .running)
        await scan.waitForRequests(2)
        let closing = session.close()
        await scan.complete(1, snapshot: snapshot(incoming: [first, second]))
        await closing.value
        #expect(access.isBalanced)
    }

    @Test func cancellationAfterCompletedScanStillInvalidatesPendingPicker() async throws {
        let scan = ControlledScan()
        let session = makeSession(scan: scan)
        let opening = session.open(root: root)
        await scan.waitForRequests(1)
        await scan.complete(0, snapshot: snapshot())
        await opening.value
        let pending = try #require(session.beginIncoming(count: 1))
        #expect(session.canCancel && session.isRunning == false)
        session.cancel()
        session.receiveIncoming([first], batch: pending)
        #expect(session.state == .cancelled && session.results.isEmpty)
        await session.close().value
    }

    @Test func refreshPreservesSelectionThenFallsBackOnlyWhenIdentityDisappears() async throws {
        let scan = ControlledScan()
        let session = makeSession(scan: scan)
        let opening = session.open(root: root)
        await scan.waitForRequests(1)
        await scan.complete(0, snapshot: snapshot(groups: [group("first"), group("selected")]))
        await opening.value
        session.select(.group("selected"))
        let batch = try #require(session.beginIncoming(count: 1))
        let added = try #require(session.receiveIncoming([first], batch: batch))
        #expect(session.selection == .group("selected"))
        await scan.waitForRequests(2)
        await scan.publish(1, snapshot: snapshot(incoming: [first]))
        #expect(session.selection == .group("selected"))
        await scan.complete(1, snapshot: snapshot(incoming: [first], groups: [group("first")]))
        await added.value
        #expect(session.selection == .group("first"))
        session.select(.incoming(first))
        let refresh = session.refresh(incoming: [first, second])
        #expect(session.selection == .incoming(first))
        await scan.waitForRequests(3)
        await scan.complete(2, snapshot: snapshot(incoming: [first, second]))
        await refresh.value
        #expect(session.selection == .incoming(first))
        #expect(session.results[0].candidates.isEmpty)
        let fresh = session.open(root: root)
        await scan.waitForRequests(4)
        await scan.complete(3, snapshot: snapshot())
        await fresh.value
        #expect(session.selection == nil && session.duplicateGroups.isEmpty)
        await session.close().value
    }

    @Test func partialRefreshRetainsMembersAndAlternativesUntilAuthoritativeCompletion() async {
        let scan = ControlledScan()
        let session = makeSession(scan: scan)
        let opening = session.open(root: root, incoming: [first])
        await scan.waitForRequests(1)
        let alternative = Representation(id: "alternative", url: second, label: "2x", matches: false)
        let original = AssetCandidate(id: "asset", name: "Icon", location: "Icon.imageset", representations: [
            Representation(id: "match", url: first, label: "1x", matches: true), alternative,
        ])
        let another = group("another").members[0]
        let initialGroup = DuplicateGroup(id: "selected", members: [original, another])
        var initial = snapshot(incoming: [first], groups: [initialGroup])
        initial.results[0].candidates = [original, another]
        await scan.complete(0, snapshot: initial)
        await opening.value
        session.select(.group("selected"))
        let refreshing = session.refresh(incoming: [first, second])
        await scan.waitForRequests(2)
        let changed = AssetCandidate(id: original.id, name: original.name, location: original.location,
                                     representations: [original.representations[0]])
        let replacement = group("replacement").members[0]
        var partial = snapshot(incoming: [first, second], groups: [DuplicateGroup(id: "selected", members: [changed, replacement])])
        partial.results[0].candidates = [changed]
        await scan.publish(1, snapshot: partial)
        #expect(session.selection == .group("selected"))
        #expect(session.duplicateGroups[0].members.map(\.id) == [original.id, another.id, replacement.id])
        #expect(session.duplicateGroups[0].members[0].representations.contains(alternative))
        #expect(session.results[0].candidates.map(\.id) == [original.id, another.id])
        #expect(session.results[0].candidates[0].representations.contains(alternative))
        await scan.complete(1, snapshot: partial)
        await refreshing.value
        #expect(session.duplicateGroups == partial.duplicateGroups)
        #expect(session.results[0].candidates == [changed])
        await session.close().value
    }

    @Test func closingWaitsForRetiredWorkersAndKeepsTheirAccessAlive() async throws {
        let scan = ControlledScan()
        let access = AccessRecorder()
        let session = makeSession(scan: scan, access: access)
        let old = session.open(root: root, incoming: [first])
        await scan.waitForRequests(1)
        let pending = try #require(session.beginIncoming(count: 1))
        let projectPanelID = session.id
        let otherRoot = URL(fileURLWithPath: "/other-project")
        let current = session.open(root: otherRoot)
        await scan.waitForRequests(2)
        #expect(access.active(root) == 1) // Old worker still holds its grant.
        session.receiveIncoming([second], batch: pending)
        #expect(session.results.isEmpty)
        let closing = session.close()
        #expect(access.active(otherRoot) == 1)
        #expect(session.root == nil && session.selection == nil)
        await session.open(root: root, replacing: projectPanelID).value
        #expect(session.root == nil)
        await scan.complete(1, snapshot: snapshot(groups: [group("late-new")]))
        await current.value
        #expect(access.active(root) == 1)
        await scan.complete(0, snapshot: snapshot(incoming: [first], groups: [group("late-old")]))
        await old.value
        await closing.value
        #expect(session.state == .idle && session.duplicateGroups.isEmpty)
        #expect(access.isBalanced)
    }

    @Test func deniedAccessIsNeverReleasedAndWindowsAreIndependent() async {
        let scan = ControlledScan()
        let access = AccessRecorder(denied: [first])
        let left = makeSession(scan: scan, access: access)
        let right = makeSession(scan: scan, access: access)
        let leftWork = left.open(root: root, incoming: [first])
        await scan.waitForRequests(1)
        let rightWork = right.open(root: root, incoming: [second])
        await scan.waitForRequests(2)
        left.cancel()
        #expect(right.state == .running && right.results.map(\.url) == [second])
        await scan.complete(0, snapshot: snapshot(incoming: [first]))
        await scan.complete(1, snapshot: snapshot(incoming: [second]))
        await leftWork.value; await rightWork.value
        await left.close().value
        #expect(access.active(root) == 1)
        await right.close().value
        #expect(access.isBalanced)
        #expect(access.active(first) == 0)
    }

    #if DEBUG
        @Test func reopenedFixtureSurvivesCleanupOfEarlierOpening() async throws {
            let scan = ControlledScan()
            let session = makeSession(scan: scan)
            let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: temporary) }
            let old = session.openFixture(root: temporary)
            await scan.waitForRequests(1)
            let retiring = session.close()
            let current = session.open(root: temporary)
            await scan.waitForRequests(2)
            await scan.complete(0, snapshot: snapshot())
            await old.value
            await retiring.value
            #expect(FileManager.default.fileExists(atPath: temporary.path))
            await scan.complete(1, snapshot: snapshot())
            await current.value
            #expect(FileManager.default.fileExists(atPath: temporary.path))
            await session.close().value
            #expect(FileManager.default.fileExists(atPath: temporary.path) == false)
        }

        @Test func temporaryFixtureIsRemovedOnlyAfterOutstandingWorkExits() async throws {
            let scan = ControlledScan()
            let session = makeSession(scan: scan)
            let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: temporary) }
            let work = session.openFixture(root: temporary)
            await scan.waitForRequests(1)
            let closing = session.close()
            #expect(FileManager.default.fileExists(atPath: temporary.path))
            await scan.complete(0, snapshot: snapshot())
            await work.value
            await closing.value
            #expect(FileManager.default.fileExists(atPath: temporary.path) == false)
        }
    #endif

    #if DEBUG
        @Test func previewsReleaseAccessAndClosedStoresRejectNewRequests() async throws {
            let root = try StressDataset.one.makeProject()
            defer { try? FileManager.default.removeItem(at: root) }
            let url = root.appendingPathComponent("Packages/Feature0/Resources/Assets.xcassets/Image0.imageset/illustration-dark-contrast@3x.png")
            let access = AccessRecorder()
            let store = ThumbnailStore(access: access.adapter)
            let thumbnail = await store.load(url: url, scope: root)
            #expect(thumbnail != nil)
            #expect(access.isBalanced)
            let closing = store.close()
            #expect(await store.load(url: url, scope: root) == nil)
            await closing.value
            #expect(access.isBalanced)
        }
    #endif

    private func makeSession(scan: ControlledScan, access: AccessRecorder = AccessRecorder()) -> ProjectSession {
        ProjectSession(dependencies: .init(access: access.adapter, scan: { root, incoming, publish in
            await scan.run(root: root, incoming: incoming, publish: publish)
        }))
    }

    private func snapshot(incoming: [URL] = [], groups: [DuplicateGroup] = []) -> ScanSnapshot {
        ScanSnapshot(results: incoming.map { IncomingResult(url: $0) }, duplicateGroups: groups)
    }

    private func group(_ id: String) -> DuplicateGroup {
        DuplicateGroup(id: id, members: ["A", "B"].map { name in
            AssetCandidate(id: id + name, name: name, location: name + ".imageset", representations: [
                Representation(id: id + name, url: first, label: "1x", matches: true),
            ])
        })
    }
}

// MARK: - ControlledScan

/// Deliberately ignores cancellation so tests can deliver obsolete work deterministically.
private actor ControlledScan {
    private struct Request {
        let incoming: [URL]
        let publish: @Sendable (ScanSnapshot) async -> Void
        let completion: CheckedContinuation<Void, Never>
    }

    private var requests = [Request]()
    private var waiters = [(Int, CheckedContinuation<Void, Never>)]()

    func run(root _: URL, incoming: [URL], publish: @escaping @Sendable (ScanSnapshot) async -> Void) async {
        await withCheckedContinuation { continuation in
            requests.append(Request(incoming: incoming, publish: publish, completion: continuation))
            let ready = waiters.filter { $0.0 <= requests.count }
            waiters.removeAll { $0.0 <= requests.count }
            ready.forEach { $0.1.resume() }
        }
    }

    func waitForRequests(_ count: Int) async {
        if requests.count >= count {
            return
        }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }

    func inputs(_ index: Int) -> [URL] {
        requests[index].incoming
    }

    func publish(_ index: Int, snapshot: ScanSnapshot) async {
        await requests[index].publish(snapshot)
    }

    func complete(_ index: Int, snapshot: ScanSnapshot) async {
        await requests[index].publish(snapshot)
        requests[index].completion.resume()
    }
}

// MARK: - AccessRecorder

private final class AccessRecorder: Sendable {
    private struct Counts {
        var active = [URL: Int]()
        var unbalanced = false
    }

    private let counts = Mutex(Counts())
    private let denied: Set<URL>

    init(denied: Set<URL> = []) {
        self.denied = denied
    }

    var adapter: FileAccessAdapter {
        FileAccessAdapter(acquire: { [self] url in
            guard denied.contains(url) == false else {
                return false
            }

            counts.withLock { $0.active[url, default: 0] += 1 }
            return true
        }, release: { [self] url in
            counts.withLock {
                $0.active[url, default: 0] -= 1
                if $0.active[url, default: 0] < 0 {
                    $0.unbalanced = true
                }
            }
        })
    }

    func active(_ url: URL) -> Int {
        counts.withLock { $0.active[url, default: 0] }
    }

    var isBalanced: Bool {
        counts.withLock { $0.unbalanced == false && $0.active.values.allSatisfy { $0 == 0 } }
    }
}
