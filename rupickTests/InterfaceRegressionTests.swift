#if DEBUG
import Foundation
import Testing
import ImageIO
import UniformTypeIdentifiers
@testable import rupick

@MainActor
struct InterfaceRegressionTests {
    @Test func singularMatchStatuses() {
        let representation = Representation(id: "image", url: URL(fileURLWithPath: "/image.png"), label: "3x", matches: true)
        let candidate = AssetCandidate(id: "asset", name: "Icon", location: "Assets.xcassets/Icon.imageset", representations: [representation])
        var result = IncomingResult(url: representation.url, candidates: [candidate])
        result.status = .complete
        #expect(result.statusText == "1 exact match")
        result.status = .comparing
        #expect(result.statusText == "Comparing · 1 provisional match")
        result.status = .incomplete
        #expect(result.statusText == "Incomplete search · 1 match so far")
    }

    @Test func refreshRetainsInspectionAndReplacesChangedCatalog() async throws {
        let root = try StressDataset.demo.makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = ProjectSession()
        await session.start(root: root, incoming: []).value
        #expect(session.duplicateGroups.count == 1)
        let previous = session.duplicateGroups
        // Starting the new scan must not blank out the currently inspected group.
        let refresh = session.start(root: root, incoming: [])
        #expect(session.duplicateGroups == previous)
        await refresh.value
        #expect(session.duplicateGroups == previous)
        try FileManager.default.removeItem(at: root.appendingPathComponent("Packages"))
        await session.start(root: root, incoming: []).value
        #expect(session.duplicateGroups.isEmpty)
        #expect(session.state == .complete)
    }

    @Test func addingInputsKeepsExistingComparisonUntilRefreshCompletes() async throws {
        let root = try StressDataset.demo.makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Packages/Feature0/Resources/Assets.xcassets/Image0.imageset/illustration-dark-contrast@3x.png")
        let first = root.appendingPathComponent("first.png")
        let second = root.appendingPathComponent("second.png")
        try FileManager.default.copyItem(at: source, to: first)
        try FileManager.default.copyItem(at: source, to: second)
        let session = ProjectSession()
        await session.start(root: root, incoming: [first]).value
        let candidates = try #require(session.results.first).candidates
        #expect(!candidates.isEmpty)
        let refresh = session.start(root: root, incoming: [first, second])
        #expect(session.results.first?.candidates == candidates)
        #expect(session.results.first?.status == .comparing)
        await refresh.value
        #expect(session.results.count == 2)
        #expect(session.results.allSatisfy { $0.candidates.count == candidates.count && $0.status == .complete })
    }

    @Test func thumbnailsReusePixelsAndInvalidateChangedFiles() async throws {
        let root = try StressDataset.one.makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Packages/Feature0/Resources/Assets.xcassets/Image0.imageset/illustration-dark-contrast@3x.png")
        let cache = ThumbnailCache()
        let first = try #require(await cache.load(url: url, scope: root, fullSize: false))
        let second = try #require(await cache.load(url: url, scope: root, fullSize: false))
        #expect(first.pixels === second.pixels)
        #expect(first.width == 2 && first.height == 1)
        try Data("corrupt".utf8).write(to: url)
        #expect(await cache.load(url: url, scope: root, fullSize: false) == nil)
    }

    @Test func cancelledThumbnailRequestDoesNotDecode() async throws {
        let root = try StressDataset.one.makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Packages/Feature0/Resources/Assets.xcassets/Image0.imageset/illustration-dark-contrast@3x.png")
        let cache = ThumbnailCache()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await cache.load(url: url, scope: root, fullSize: false)
        }
        #expect(await task.value == nil)
    }

    @Test(arguments: [StressDataset.empty, .one, .worst, .thousand])
    func stressCatalogs(dataset: StressDataset) async throws {
        let root = try dataset.makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = ProjectSession()
        await session.start(root: root, incoming: []).value
        #expect(session.state == .complete)
        switch dataset {
        case .empty: #expect(session.discovered == 0 && session.duplicateGroups.isEmpty)
        case .one: #expect(session.discovered == 1 && session.duplicateGroups.isEmpty)
        case .worst:
            #expect(session.duplicateGroups.contains { $0.members.count == 16 })
            #expect(session.skipped == 3)
        case .thousand: #expect(session.duplicateGroups.first?.members.count == 1000)
        case .demo: break
        }
    }
}

#endif
