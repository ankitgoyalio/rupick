import Foundation
@testable import rupick
import Testing

// MARK: - ProjectWorkspaceTests

@MainActor
struct ProjectWorkspaceTests {
    @Test func openingAliasesKeepsOneSessionAndClosingLeavesOtherProjectAlone() throws {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let workspace = ProjectWorkspace(defaults: defaults, bookmarks: .paths)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try workspace.open(root)
        let alias = try workspace.open(root.appendingPathComponent("."))
        #expect(first == alias)
        let left = workspace.session(for: first)
        #expect(left === workspace.session(for: alias))
        let otherRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: otherRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: otherRoot) }
        let other = try workspace.open(otherRoot)
        let right = workspace.session(for: other)
        #expect(left !== right)
        workspace.close(first, session: left)
        #expect(workspace.session(for: other) === right)
        let reopened = workspace.session(for: first)
        #expect(reopened !== left)
        workspace.close(first, session: left)
        #expect(workspace.session(for: first) === reopened)
        workspace.close(first, session: reopened)
        workspace.close(other, session: right)
    }

    @Test func recentsSurviveRelaunchAndUnavailableFoldersAreRejected() throws {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = ProjectWorkspace(defaults: defaults, bookmarks: .paths)
        let url = try workspace.open(root)
        let restored = ProjectWorkspace(defaults: defaults, bookmarks: .paths)
        let recent = try #require(restored.recents.first)
        #expect(try restored.reopen(recent) == url)
        #expect(restored.recents.count == 1)
        try FileManager.default.removeItem(at: root)
        #expect(throws: (any Error).self) { try restored.reopen(recent) }
        #expect(restored.recents.count == 1)
    }
}

private extension ProjectBookmarkAdapter {
    static let paths = Self(create: { Data($0.path.utf8) }, resolve: {
        URL(fileURLWithPath: String(decoding: $0, as: UTF8.self))
    })
}
