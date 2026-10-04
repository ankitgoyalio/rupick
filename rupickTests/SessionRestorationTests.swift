import Foundation
@testable import rupick
import Testing

// MARK: - SessionRestorationTests

@MainActor
struct SessionRestorationTests {
    @Test(arguments: [false, true]) func missingIncomingRetainsEntryAndLocateChecksContentBeforeRestoringReview(changed: Bool) async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let original = fixture.appendingPathComponent("Incoming/renamed.png")
        let replacement = fixture.appendingPathComponent("reconnected.png")
        let bytes = try Data(contentsOf: original)
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let first = ProjectWorkspace(defaults: defaults, bookmarks: .testPaths)
        let identity = try first.open(fixture)
        let session = first.session(for: identity)
        await session.refresh(incoming: [original]).value
        session.keepAsNew(original)
        first.prepareForTermination()
        await session.close().value
        try FileManager.default.removeItem(at: original)
        let next = ProjectWorkspace(defaults: defaults, bookmarks: .testPaths)
        _ = try next.restore(identity)
        let resumed = next.session(for: identity)
        await resumed.refresh(incoming: resumed.results.map(\.url)).value
        #expect(resumed.results.count == 1)
        #expect(resumed.results[0].needsRecovery)
        #expect(resumed.reviewedCount == 0)
        let replacementBytes = changed ? try Data(contentsOf: fixture.appendingPathComponent("Incoming/new.png")) : bytes
        try replacementBytes.write(to: replacement)
        resumed.locateIncoming(original, at: replacement)
        await resumed.refresh(incoming: [replacement]).value
        #expect(resumed.review(for: replacement).outcome == (changed ? nil : .keepAsNew))
        #expect(resumed.review(for: replacement).notice == (changed ? .incomingChanged : nil))
        resumed.removeIncoming(replacement)
        await resumed.refresh(incoming: []).value
        #expect(resumed.results.isEmpty)
        #expect(try Data(contentsOf: replacement) == replacementBytes)
        next.prepareForTermination()
        #expect(ProjectWorkspace(defaults: defaults, bookmarks: .testPaths).restorationIdentities == [identity])
        await resumed.close().value
    }

    @Test(arguments: [false, true]) func changedIncomingResetsBothOutcomesOnRelaunch(reuse: Bool) async throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let workspace = ProjectWorkspace(defaults: defaults, bookmarks: .testPaths)
        let identity = try workspace.open(root)
        let session = workspace.session(for: identity)
        let input = root.appendingPathComponent("Incoming/renamed.png")
        await session.refresh(incoming: [input]).value
        if reuse {
            let candidate = try #require(session.results[0].candidates.first)
            let representation = try #require(candidate.representations.first(where: { $0.matches }))
            #expect(session.reuseAsset(for: input, candidateID: candidate.id, representationID: representation.id))
        } else {
            session.keepAsNew(input)
        }
        workspace.prepareForTermination()
        await session.close().value
        try Data(contentsOf: root.appendingPathComponent("Incoming/new.png")).write(to: input)
        let restored = ProjectWorkspace(defaults: defaults, bookmarks: .testPaths)
        _ = try restored.restore(identity)
        let resumed = restored.session(for: identity)
        await resumed.refresh(incoming: [input]).value
        #expect(resumed.review(for: input).outcome == nil)
        #expect(resumed.review(for: input).notice == .incomingChanged)
        await resumed.close().value
    }

    @Test func changedSelectedReuseMatchRequiresAnotherDecisionAfterRelaunch() async throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let workspace = ProjectWorkspace(defaults: defaults, bookmarks: .testPaths)
        let identity = try workspace.open(root)
        let session = workspace.session(for: identity)
        let input = root.appendingPathComponent("Incoming/renamed.png")
        await session.refresh(incoming: [input]).value
        let candidate = try #require(session.results[0].candidates.first)
        let representation = try #require(candidate.representations.first(where: { $0.matches }))
        #expect(session.reuseAsset(for: input, candidateID: candidate.id, representationID: representation.id))
        workspace.prepareForTermination()
        await session.close().value
        try Data(contentsOf: root.appendingPathComponent("Incoming/new.png")).write(to: representation.url)
        let restored = ProjectWorkspace(defaults: defaults, bookmarks: .testPaths)
        _ = try restored.restore(identity)
        let resumed = restored.session(for: identity)
        await resumed.refresh(incoming: [input]).value
        #expect(resumed.review(for: input).outcome == nil)
        #expect(resumed.review(for: input).notice == .selectedMatchChanged)
        await resumed.close().value
    }

    @Test func failedIncomingBookmarkRequiresLocateEvenWhenFileExists() async throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let workspace = ProjectWorkspace(defaults: defaults, bookmarks: .testPaths)
        let identity = try workspace.open(root)
        let input = root.appendingPathComponent("Incoming/new.png")
        let session = workspace.session(for: identity)
        await session.refresh(incoming: [input]).value
        session.keepAsNew(input)
        workspace.prepareForTermination()
        await session.close().value
        let failing = ProjectBookmarkAdapter(create: ProjectBookmarkAdapter.testPaths.create, resolve: { data in
            let url = URL(fileURLWithPath: String(decoding: data, as: UTF8.self))
            if url.pathExtension == "png" {
                throw CocoaError(.fileReadNoPermission)
            }
            return url
        })
        let next = ProjectWorkspace(defaults: defaults, bookmarks: failing)
        _ = try next.restore(identity)
        let resumed = next.session(for: identity)
        await resumed.refresh(incoming: [input]).value
        #expect(resumed.results[0].needsRecovery)
        #expect(resumed.reviewedCount == 0)
        resumed.locateIncoming(input, at: input)
        await resumed.refresh(incoming: [input]).value
        #expect(resumed.review(for: input).outcome == .keepAsNew)
        await resumed.close().value
    }

    @Test func unavailableProjectOffersRecoveryAndPreservesPendingReview() async throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let workspace = ProjectWorkspace(defaults: defaults, bookmarks: .testPaths)
        let identity = try workspace.open(root)
        let input = root.appendingPathComponent("Incoming/new.png")
        let session = workspace.session(for: identity)
        await session.refresh(incoming: [input]).value
        session.keepAsNew(input)
        workspace.prepareForTermination()
        await session.close().value
        let failing = ProjectBookmarkAdapter(create: ProjectBookmarkAdapter.testPaths.create, resolve: { data in
            let url = URL(fileURLWithPath: String(decoding: data, as: UTF8.self))
            if url.pathExtension.isEmpty {
                throw CocoaError(.fileReadNoPermission)
            }
            return url
        })
        let next = ProjectWorkspace(defaults: defaults, bookmarks: failing)
        _ = try next.restore(identity)
        let resumed = next.session(for: identity)
        #expect(resumed.state == .failed)
        #expect(resumed.error != nil)
        #expect(resumed.reviewedCount == 0)
        #expect(resumed.results.map(\.url) == [input])
        try next.locateProject(identity, at: root)
        await resumed.refresh(incoming: [input]).value
        #expect(resumed.review(for: input).outcome == .keepAsNew)
        next.close(identity, session: resumed)
        #expect(ProjectWorkspace(defaults: defaults, bookmarks: .testPaths).restorationIdentities.isEmpty)
    }

    @Test func storageFailuresAndUnsupportedVersionsAreVisible() async throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let bad = SessionStorage(load: { Data(#"{"version":2,"projects":[]}"#.utf8) }, save: { _ in
            throw CocoaError(.fileWriteNoPermission)
        })
        let workspace = ProjectWorkspace(defaults: defaults, bookmarks: .testPaths, storage: bad)
        #expect(workspace.restorationError != nil)
        #expect(workspace.restorationIdentities.isEmpty)
        let identity = try workspace.open(root)
        #expect(workspace.session(for: identity).persistenceError != nil)
        await workspace.session(for: identity).close().value
    }

    private func makeFixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("fixtures/ExactMatching")
        try FileManager.default.copyItem(at: source, to: root)
        return root
    }

    @Test func relaunchRestoresSelectionAndBothOutcomesAfterValidation() async throws {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("fixtures/ExactMatching")
        try FileManager.default.copyItem(at: fixture, to: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = ProjectWorkspace(defaults: defaults, bookmarks: .testPaths)
        let identity = try workspace.open(root)
        let session = workspace.session(for: identity)
        let duplicate = root.appendingPathComponent("Incoming/renamed.png")
        let newImage = root.appendingPathComponent("Incoming/new.png")
        await session.refresh(incoming: [duplicate, newImage]).value
        let candidate = try #require(session.results[0].candidates.first)
        let representation = try #require(candidate.representations.first(where: { $0.matches }))
        #expect(session.reuseAsset(for: duplicate, candidateID: candidate.id, representationID: representation.id))
        session.keepAsNew(newImage)
        let alternative = try #require(candidate.representations.first(where: { $0.matches == false }))
        session.selectRepresentation(for: duplicate, candidateID: candidate.id, representationID: alternative.id)
        session.select(.incoming(newImage))
        workspace.prepareForTermination()
        let restored = ProjectWorkspace(defaults: defaults, bookmarks: .testPaths)
        #expect(restored.restorationIdentities == [identity])
        _ = try restored.restore(identity)
        let resumed = restored.session(for: identity)
        #expect(resumed.reviewedCount == 0)
        await resumed.refresh(incoming: resumed.results.map(\.url)).value
        #expect(resumed.selection == .incoming(newImage))
        #expect(resumed.results.map(\.url) == [duplicate, newImage])
        #expect(resumed.review(for: newImage).outcome == .keepAsNew)
        #expect(resumed.review(for: duplicate).representationIDs[candidate.id] == alternative.id)
        #expect(resumed.review(for: duplicate).outcome == session.review(for: duplicate).outcome)
        await session.close().value
        await resumed.close().value
    }
}

extension ProjectBookmarkAdapter {
    static let testPaths = Self(create: { Data($0.path.utf8) }, resolve: {
        URL(fileURLWithPath: String(decoding: $0, as: UTF8.self))
    })
}
