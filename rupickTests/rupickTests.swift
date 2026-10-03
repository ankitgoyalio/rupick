import Foundation
import ImageIO
@testable import rupick
import Testing
import UniformTypeIdentifiers

// MARK: - ProjectSessionTests

@MainActor
struct ProjectSessionTests {
    @Test func openingProjectGroupsDistinctEntriesWithoutIncomingImages() async throws {
        let fixture = try FixtureProject()
        defer { fixture.remove() }
        let image = try fixture.image("red.png")
        let blue = try fixture.image("blue.png", pixels: [0, 0, 255, 255])
        try fixture.asset("A.xcassets/Icon.imageset", images: [image, image, blue])
        try fixture.asset("B.xcassets/Icon.imageset", images: [image])
        try fixture.asset("B.xcassets/Third.imageset", images: [image])
        try fixture.asset("B.xcassets/Unique.imageset", images: [blue, blue])
        let session = ProjectSession()
        await session.open(root: fixture.root, incoming: []).value
        #expect(session.state == .complete)
        #expect(session.results.isEmpty)
        #expect(session.duplicateGroups.count == 2)
        #expect(session.duplicateGroups.map { $0.members.count }.sorted() == [2, 3])
        let group = try #require(session.duplicateGroups.first { $0.members.count == 3 })
        #expect(group.members.map(\.location) == ["A.xcassets/Icon.imageset", "B.xcassets/Icon.imageset", "B.xcassets/Third.imageset"])
        #expect(group.members[0].representations.map(\.matches) == [true, true, false])
    }

    @Test(arguments: [
        ([255, 0, 0, 255, 2, 3, 4, 0], 2, true),
        ([254, 0, 0, 255, 2, 3, 4, 0], 2, false),
        ([255, 0, 0, 255, 2, 3, 4, 1], 2, false),
        ([255, 0, 0, 255, 2, 3, 4, 0], 1, false),
        ([255, 0, 0, 255, 2, 3, 4, 0, 0, 0, 0, 0], 3, false),
    ])
    func projectDuplicatesUseExactNormalizedContent(pixels: [UInt8], width: Int, matches: Bool) async throws {
        let fixture = try FixtureProject()
        defer { fixture.remove() }
        let original = try fixture.image("original.png", pixels: [255, 0, 0, 255, 90, 80, 70, 0], width: 2)
        let other = try fixture.image("other.png", pixels: pixels, width: width, metadata: "Different metadata")
        try fixture.asset("Assets.xcassets/A.imageset", images: [original, original])
        try fixture.asset("Assets.xcassets/B.imageset", images: [other])
        let session = ProjectSession()
        await session.open(root: fixture.root, incoming: []).value
        #expect(session.duplicateGroups.count == (matches ? 1 : 0))
        #expect(session.isIncomplete == false)
    }

    @Test func ignoredAndUnreadableFilesDoNotHideProjectDuplicates() async throws {
        let fixture = try FixtureProject()
        defer { fixture.remove() }
        let image = try fixture.image("red.png")
        for name in ["A", "B", "Ignored"] {
            try fixture.asset("Assets.xcassets/\(name).imageset", images: [image])
        }
        let broken = fixture.root.appendingPathComponent("broken.png")
        try Data("invalid".utf8).write(to: broken)
        try fixture.asset("Assets.xcassets/Bad.imageset", images: [broken])
        try fixture.asset("Excluded.xcassets/Bad.imageset", images: [broken])
        try fixture.asset("Excluded.xcassets/Copy.imageset", images: [image])
        try Data("Excluded.xcassets/\n**/Ignored.imageset/variant0.png\n".utf8).write(to: fixture.root.appendingPathComponent(".gitignore"))
        let session = ProjectSession()
        await session.open(root: fixture.root, incoming: []).value
        #expect(session.duplicateGroups.count == 1)
        #expect(session.duplicateGroups[0].members.map(\.name) == ["A", "B"])
        #expect(session.skipped == 1)
        #expect(session.isIncomplete)
        #expect(session.state == .complete)
    }

    @Test func provisionalProjectGroupsSurviveCancellationAndNewSessionsResetThem() async throws {
        let fixture = try FixtureProject()
        defer { fixture.remove() }
        let image = try fixture.image("red.png")
        for index in 0 ..< 100 {
            try fixture.asset("Assets.xcassets/A\(index).imageset", images: [image])
        }
        let session = ProjectSession()
        let work = session.open(root: fixture.root, incoming: [])
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while session.duplicateGroups.isEmpty, session.isRunning, ContinuousClock.now < deadline {
            await Task.yield()
        }
        #expect(session.isRunning)
        #expect(session.duplicateGroups.isEmpty == false)
        session.cancel()
        let retained = session.duplicateGroups
        await work.value
        #expect(session.state == .cancelled)
        #expect(session.isIncomplete)
        #expect(session.duplicateGroups == retained)
        let missing = fixture.root.appendingPathComponent("missing")
        await session.open(root: missing, incoming: []).value
        #expect(session.state == .failed)
        #expect(session.duplicateGroups.isEmpty)
    }

    @Test func missingRepresentationDoesNotDiscardReadableGroupMembers() async throws {
        let fixture = try FixtureProject()
        defer { fixture.remove() }
        let image = try fixture.image("red.png")
        try fixture.asset("Assets.xcassets/A.imageset", images: [image, image])
        try fixture.asset("Assets.xcassets/B.imageset", images: [image])
        try FileManager.default.removeItem(at: fixture.root.appendingPathComponent("Assets.xcassets/A.imageset/variant1.png"))
        let session = ProjectSession()
        await session.open(root: fixture.root, incoming: []).value
        #expect(session.duplicateGroups.count == 1)
        #expect(session.skipped == 1)
        #expect(session.isIncomplete)
    }

    @Test func invalidPathsAndSymbolicLinksAreIsolatedFromProjectGroups() async throws {
        let fixture = try FixtureProject()
        let outside = try FixtureProject()
        defer { fixture.remove(); outside.remove() }
        let image = try fixture.image("red.png")
        let external = try outside.image("external.png")
        try fixture.asset("Assets.xcassets/A.imageset", images: [image])
        try fixture.asset("Assets.xcassets/B.imageset", images: [image])
        let a = fixture.root.appendingPathComponent("Assets.xcassets/A.imageset")
        try FileManager.default.createSymbolicLink(at: a.appendingPathComponent("link.png"), withDestinationURL: external)
        try Data(#"{"images":[{"filename":"variant0.png"},{"filename":"../../../outside.png"},{"filename":"link.png"}]}"#.utf8).write(to: a.appendingPathComponent("Contents.json"))
        try FileManager.default.createSymbolicLink(at: fixture.root.appendingPathComponent("Linked.xcassets"), withDestinationURL: fixture.root.appendingPathComponent("Assets.xcassets"))
        let session = ProjectSession()
        await session.open(root: fixture.root, incoming: []).value
        #expect(session.discovered == 2)
        #expect(session.duplicateGroups.count == 1)
        #expect(session.duplicateGroups[0].members.map(\.name) == ["A", "B"])
        #expect(session.skipped == 2)
    }

    @Test func projectGroupsNormalizeOrientationAndCompareJPEGContent() async throws {
        let fixture = try FixtureProject()
        defer { fixture.remove() }
        let original = try fixture.image("original.png", pixels: [255, 0, 0, 255, 0, 0, 255, 255], width: 2)
        let rotated = try fixture.image("rotated.png", pixels: [0, 0, 255, 255, 255, 0, 0, 255], width: 1, orientation: 6)
        let jpeg = try fixture.image("original.jpg")
        let otherJPEG = try fixture.image("other.jpg", pixels: [0, 255, 0, 255])
        try fixture.asset("Assets.xcassets/A.imageset", images: [original])
        try fixture.asset("Assets.xcassets/B.imageset", images: [rotated])
        try fixture.asset("Assets.xcassets/C.imageset", images: [jpeg])
        try fixture.asset("Assets.xcassets/D.imageset", images: [jpeg])
        try fixture.asset("Assets.xcassets/E.imageset", images: [otherJPEG])
        let session = ProjectSession()
        await session.open(root: fixture.root, incoming: []).value
        #expect(session.duplicateGroups.map { $0.members.map(\.name) } == [["A", "B"], ["C", "D"]])
    }

    @Test func repeatedMetadataRowsHaveDistinctRepresentationIdentity() async throws {
        let fixture = try FixtureProject()
        defer { fixture.remove() }
        let image = try fixture.image("red.png")
        try fixture.asset("Assets.xcassets/A.imageset", images: [image])
        try fixture.asset("Assets.xcassets/B.imageset", images: [image])
        let metadata = fixture.root.appendingPathComponent("Assets.xcassets/A.imageset/Contents.json")
        try Data(#"{"images":[{"filename":"variant0.png","scale":"1x"},{"filename":"variant0.png","scale":"1x"}]}"#.utf8).write(to: metadata)
        let session = ProjectSession()
        await session.open(root: fixture.root, incoming: []).value
        #expect(session.duplicateGroups.count == 1)
        let representations = session.duplicateGroups[0].members[0].representations
        #expect(representations.count == 2)
        #expect(Set(representations.map(\.id)).count == 2)
        #expect(representations.allSatisfy { $0.matches })
    }

    @Test func mixedBatchHasIndependentCompletionAndFailureStates() async throws {
        let fixture = try FixtureProject()
        defer { fixture.remove() }
        let duplicate = try fixture.image("duplicate.png")
        let newImage = try fixture.image("new.jpg", pixels: [0, 255, 0, 255])
        let broken = fixture.root.appendingPathComponent("broken.png")
        try Data("invalid".utf8).write(to: broken)
        try fixture.asset("Assets.xcassets/Good.imageset", images: [duplicate])
        let session = ProjectSession()
        let work = session.open(root: fixture.root, incoming: [duplicate, broken, newImage, duplicate])
        #expect(session.results.count == 3)
        #expect(session.results.allSatisfy { $0.status == .waiting })
        await work.value
        #expect(session.results.map(\.status) == [.complete, .unreadable, .complete])
        #expect(session.results.map { $0.candidates.count } == [1, 0, 0])
        #expect(session.results[1].statusText == "Image unavailable")
        #expect(session.results[2].statusText == "No matches found")
    }

    @Test func skippedCatalogMakesValidBatchResultsIncomplete() async throws {
        let fixture = try FixtureProject()
        defer { fixture.remove() }
        let duplicate = try fixture.image("duplicate.png")
        let newImage = try fixture.image("new.png", pixels: [0, 255, 0, 255])
        let broken = fixture.root.appendingPathComponent("broken.png")
        try Data("invalid".utf8).write(to: broken)
        try fixture.asset("Assets.xcassets/Good.imageset", images: [duplicate])
        try fixture.asset("Assets.xcassets/Bad.imageset", images: [broken])
        let session = ProjectSession()
        await session.open(root: fixture.root, incoming: [duplicate, newImage, broken]).value
        #expect(session.state == .complete)
        #expect(session.isIncomplete)
        #expect(session.skipped == 1)
        #expect(session.decoded == 3)
        #expect(session.results.map(\.status) == [.incomplete, .incomplete, .unreadable])
        #expect(session.results[0].candidates.count == 1)
        #expect(session.results[1].statusText == "Incomplete search · 0 matches so far")
    }

    @Test func failedScanDoesNotCompleteIncomingComparisons() async {
        let session = ProjectSession()
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        await session.open(root: missing, incoming: [missing.appendingPathComponent("incoming.png")]).value
        #expect(session.state == .failed)
        #expect(session.isIncomplete)
        #expect(session.results[0].status == .incomplete)
        #expect(session.results[0].statusText != "No matches found")
    }

    @Test func ignoredCatalogsDoNotBecomeCandidatesOrIncompleteScans() async throws {
        let fixture = try FixtureProject()
        defer { fixture.remove() }
        let incoming = try fixture.image("incoming.png")
        try fixture.asset("App/Assets.xcassets/Good.imageset", images: [incoming])
        try fixture.asset("Dependencies/Assets.xcassets/Duplicate.imageset", images: [incoming])
        let broken = fixture.root.appendingPathComponent("broken.png")
        try Data("invalid".utf8).write(to: broken)
        try fixture.asset("Dependencies/Assets.xcassets/Broken.imageset", images: [broken])
        try Data("Dependencies/\n".utf8).write(to: fixture.root.appendingPathComponent(".gitignore"))
        let session = ProjectSession()
        await session.open(root: fixture.root, incoming: [incoming]).value
        #expect(session.discovered == 1)
        #expect(session.results[0].candidates.map(\.name) == ["Good"])
        #expect(session.skipped == 0)
        #expect(session.isIncomplete == false)
    }

    @Test func nestedIgnoreRulesReincludeRepresentationsAndKeepExplicitInputs() async throws {
        let fixture = try FixtureProject()
        defer { fixture.remove() }
        let incoming = try fixture.image("incoming.png")
        try fixture.asset("Nested/Assets.xcassets/Kept.imageset", images: [incoming, incoming])
        try fixture.asset("Nested/Assets.xcassets/Omitted.imageset", images: [incoming])
        try fixture.asset("RootOnly.xcassets/Hidden.imageset", images: [incoming])
        try fixture.asset("Nested/RootOnly.xcassets/Visible.imageset", images: [incoming])
        try Data("*.png\n/RootOnly.xcassets/\n".utf8).write(to: fixture.root.appendingPathComponent(".gitignore"))
        try Data("!variant0.png\nOmitted.imageset/\n".utf8).write(to: fixture.root.appendingPathComponent("Nested/.gitignore"))
        let session = ProjectSession()
        await session.open(root: fixture.root, incoming: [incoming]).value
        #expect(session.results[0].error == nil)
        #expect(session.results[0].candidates.map(\.name) == ["Kept", "Visible"])
        #expect(session.results[0].candidates[0].representations.count == 1)
        #expect(session.discovered == 2)
        #expect(session.skipped == 0)
    }

    @Test func ignoreGlobsEscapesAndExcludedParentsFollowGitPatterns() async throws {
        let fixture = try FixtureProject()
        defer { fixture.remove() }
        let incoming = try fixture.image("incoming.png")
        for path in ["Cache.xcassets/Hidden.imageset", "Deep/Cache.xcassets/Hidden.imageset",
                     "Generated/A/B/Assets.xcassets/Hidden.imageset", "Generated/Assets.xcassets/Hidden.imageset",
                     "Escaped/Assets.xcassets/Hidden.imageset", "#literal/Assets.xcassets/Hidden.imageset",
                     "!literal/Assets.xcassets/Hidden.imageset", "Excluded/Assets.xcassets/Hidden.imageset",
                     "Space /Assets.xcassets/Hidden.imageset", "App/Assets.xcassets/Icon1.imageset",
                     "App/Assets.xcassets/Icon2.imageset", "App/Assets.xcassets/IconA.imageset"]
        {
            try fixture.asset(path, images: [incoming])
        }
        let rules = """
        # comment
        **/Cache.xcassets/
        Generated/***/Assets.xcassets/
        Escaped\\/Assets.xcassets/
        \\#literal/
        \\!literal/
        Excluded/
        !Excluded/Assets.xcassets/Hidden.imageset/
        Space\\ /
        Icon[0-9].imageset/
        !Icon2.imageset/
        """
        try Data((rules + "\nunused   \n").utf8).write(to: fixture.root.appendingPathComponent(".gitignore"))
        let session = ProjectSession()
        await session.open(root: fixture.root, incoming: [incoming]).value
        #expect(session.discovered == 2)
        #expect(session.results[0].candidates.map(\.name) == ["Icon2", "IconA"])
        #expect(session.isIncomplete == false)
    }

    @Test func unreadableIgnoreRulesFailRatherThanScanIgnoredCatalogs() async throws {
        let fixture = try FixtureProject()
        defer { fixture.remove() }
        let incoming = try fixture.image("incoming.png")
        try fixture.asset("Assets.xcassets/Icon.imageset", images: [incoming])
        try Data([0xFF]).write(to: fixture.root.appendingPathComponent(".gitignore"))
        let session = ProjectSession()
        await session.open(root: fixture.root, incoming: [incoming]).value
        #expect(session.state == .failed)
        #expect(session.error?.contains("ignore rules") == true)
        #expect(session.results[0].status == .incomplete)
    }

    @Test func ignoringRegularFilesDoesNotPruneSiblingCatalogs() async throws {
        let fixture = try FixtureProject()
        defer { fixture.remove() }
        let incoming = try fixture.image("incoming.png")
        for index in 0 ..< 20 {
            let directory = fixture.root.appendingPathComponent("Folder\(index)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data().write(to: directory.appendingPathComponent(".DS_Store"))
            try fixture.asset("Folder\(index)/Assets.xcassets/Icon.imageset", images: [incoming])
        }
        try Data(".DS_Store\n".utf8).write(to: fixture.root.appendingPathComponent(".gitignore"))
        let session = ProjectSession()
        await session.open(root: fixture.root, incoming: [incoming]).value
        #expect(session.discovered == 20)
        #expect(session.results[0].candidates.count == 20)
        #expect(session.isIncomplete == false)
    }

    @Test func renamedImageMatchesCatalogEntry() async throws {
        let fixture = try FixtureProject()
        defer { fixture.remove() }
        let incoming = try fixture.image("incoming.png")
        try fixture.asset("First.xcassets/Icon.imageset", images: [incoming])
        let session = ProjectSession()
        await session.open(root: fixture.root, incoming: [incoming]).value
        #expect(session.isRunning == false)
        #expect(session.results.first?.candidates.map(\.name) == ["Icon"])
    }

    @Test(arguments: [
        ([255, 0, 0, 255, 2, 3, 4, 0], 2, true),
        ([254, 0, 0, 255, 2, 3, 4, 0], 2, false),
        ([255, 0, 0, 255, 2, 3, 4, 1], 2, false),
        ([255, 0, 0, 255, 2, 3, 4, 0], 1, false),
        ([255, 0, 0, 255, 2, 3, 4, 0, 0, 0, 0, 0], 3, false),
    ])
    func exactPixelRules(pixels: [UInt8], width: Int, matches: Bool) async throws {
        let fixture = try FixtureProject()
        defer { fixture.remove() }
        let original = try fixture.image("original.png", pixels: [255, 0, 0, 255, 90, 80, 70, 0], width: 2)
        let incoming = try fixture.image("renamed.png", pixels: pixels, width: width, metadata: "New metadata")
        try fixture.asset("Assets.xcassets/Icon.imageset", images: [original])
        let session = ProjectSession()
        await session.open(root: fixture.root, incoming: [incoming]).value
        #expect((session.results[0].candidates.count == 1) == matches)
    }

    @Test func lowAlphaDifferencesRemainVisible() async throws {
        let fixture = try FixtureProject()
        defer { fixture.remove() }
        let original = try fixture.image("original.png", pixels: [100, 0, 0, 1])
        let incoming = try fixture.image("incoming.png", pixels: [101, 0, 0, 1])
        try fixture.asset("Assets.xcassets/Icon.imageset", images: [original])
        let session = ProjectSession()
        await session.open(root: fixture.root, incoming: [incoming]).value
        #expect(session.results[0].candidates.isEmpty)
    }

    @Test func groupsRepresentationsAndSeparatesCatalogs() async throws {
        let fixture = try FixtureProject()
        defer { fixture.remove() }
        let incoming = try fixture.image("incoming.png")
        let alternative = try fixture.image("dark.png", pixels: [0, 0, 255, 255])
        try fixture.asset("Nested/First.xcassets/Icon.imageset", images: [incoming, incoming, alternative])
        try fixture.asset("Second.xcassets/Icon.imageset", images: [incoming])
        let session = ProjectSession()
        await session.open(root: fixture.root, incoming: [incoming]).value
        let candidates = session.results[0].candidates
        #expect(candidates.count == 2)
        #expect(Set(candidates.map(\.id)).count == 2)
        #expect(candidates[0].representations.map(\.matches) == [true, true, false])
        #expect(candidates[0].representations[2].label.contains("3x"))
    }

    @Test func jpegRequiresEqualDecodedContent() async throws {
        let fixture = try FixtureProject()
        defer { fixture.remove() }
        let original = try fixture.image("original.jpg")
        let copy = fixture.root.appendingPathComponent("renamed.jpg")
        try FileManager.default.copyItem(at: original, to: copy)
        let changed = try fixture.image("different.jpg", pixels: [0, 255, 0, 255])
        try fixture.asset("Assets.xcassets/Icon.imageset", images: [original])
        let session = ProjectSession()
        await session.open(root: fixture.root, incoming: [copy, changed]).value
        #expect(session.results.map { $0.candidates.count } == [1, 0])
    }

    @Test func orientationNormalizesDimensionsAndPixels() async throws {
        let fixture = try FixtureProject()
        defer { fixture.remove() }
        let original = try fixture.image("original.png", pixels: [255, 0, 0, 255, 0, 0, 255, 255], width: 2)
        let rotated = try fixture.image("rotated.png", pixels: [0, 0, 255, 255, 255, 0, 0, 255], width: 1, orientation: 6)
        try fixture.asset("Assets.xcassets/Icon.imageset", images: [original])
        let session = ProjectSession()
        await session.open(root: fixture.root, incoming: [rotated]).value
        #expect(session.results[0].candidates.count == 1)
    }

    @Test func corruptFilesDoNotHideSuccessfulMatches() async throws {
        let fixture = try FixtureProject()
        defer { fixture.remove() }
        let incoming = try fixture.image("incoming.png")
        let broken = fixture.root.appendingPathComponent("broken.png")
        try Data("invalid".utf8).write(to: broken)
        try fixture.asset("Assets.xcassets/Good.imageset", images: [incoming])
        try fixture.asset("Assets.xcassets/Bad.imageset", images: [broken])
        let session = ProjectSession()
        await session.open(root: fixture.root, incoming: [broken, incoming]).value
        #expect(session.results[0].error != nil)
        #expect(session.results[1].candidates.count == 1)
        #expect(session.skipped == 1)
        #expect(session.error == nil)
    }

    @Test func neverFollowsCatalogOrRepresentationSymlinksOutsideRoot() async throws {
        let fixture = try FixtureProject()
        let outside = try FixtureProject()
        defer { fixture.remove(); outside.remove() }
        let incoming = try outside.image("incoming.png")
        try outside.asset("External.xcassets/Icon.imageset", images: [incoming])
        try FileManager.default.createSymbolicLink(at: fixture.root.appendingPathComponent("External.xcassets"),
                                                   withDestinationURL: outside.root.appendingPathComponent("External.xcassets"))
        try fixture.asset("Local.xcassets/Escape.imageset", images: [incoming])
        let representation = fixture.root.appendingPathComponent("Local.xcassets/Escape.imageset/variant0.png")
        try FileManager.default.removeItem(at: representation)
        try FileManager.default.createSymbolicLink(at: representation, withDestinationURL: incoming)
        let session = ProjectSession()
        await session.open(root: fixture.root, incoming: [incoming]).value
        #expect(session.discovered == 1)
        #expect(session.results[0].candidates.isEmpty)
        #expect(session.skipped == 1)
    }

    @Test func newerSelectionCannotBeOverwrittenByOldWork() async throws {
        let first = try FixtureProject()
        let second = try FixtureProject()
        defer { first.remove(); second.remove() }
        let incoming = try first.image("incoming.png")
        try first.asset("Assets.xcassets/Icon.imageset", images: [incoming])
        let session = ProjectSession()
        let old = session.open(root: first.root, incoming: [incoming])
        let current = session.open(root: second.root, incoming: [incoming])
        await current.value; await old.value
        #expect(session.root == second.root)
        #expect(session.results[0].candidates.isEmpty)
        #expect(session.isRunning == false)
    }

    @Test func provisionalResultsArriveBeforeCompletionAndCanBeCancelled() async throws {
        let fixture = try FixtureProject()
        defer { fixture.remove() }
        let incoming = try fixture.image("incoming.png")
        for index in 0 ..< 100 {
            try fixture.asset("Assets.xcassets/Icon\(index).imageset", images: [incoming])
        }
        let session = ProjectSession()
        let task = session.open(root: fixture.root, incoming: [incoming])
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while session.compared == 0, session.isRunning, ContinuousClock.now < deadline {
            await Task.yield()
        }
        #expect(session.isRunning)
        #expect(session.results[0].status == .comparing)
        #expect(session.decoded == 1)
        #expect(session.compared > 0 && session.compared < session.discovered)
        #expect(session.results[0].candidates.isEmpty == false)
        session.cancel()
        await task.value
        #expect(session.isRunning == false)
        #expect(session.phase.contains("incomplete"))
        #expect(session.results[0].status == .incomplete)
        #expect(session.state == .cancelled)
    }

    @Test func missingRootIsAFailureRatherThanNoMatches() async {
        let session = ProjectSession()
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        await session.open(root: missing, incoming: []).value
        #expect(session.error != nil)
        #expect(session.phase == "Search failed")
    }

    @Test func sixteenBitPrecisionSurvivesLowAlphaNormalization() async throws {
        let fixture = try FixtureProject()
        defer { fixture.remove() }
        // Literal PNGs: RGBA8 [100,12,250,1], equivalent RGBA16 [25700,3084,64250,257],
        // and a visible one-component difference RGBA16 [25701,3084,64250,257].
        let encoded = [
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNI4fnFCAADrgFsrN3y3QAAAABJRU5ErkJggg==",
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABEAYAAABPhRjKAAAAEUlEQVR4nGNISeHh+fWLkREADUIC19RxgVgAAAAASUVORK5CYII=",
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABEAYAAABPhRjKAAAAEUlEQVR4nGNISeXh+fWLkREADUkC2EudSFcAAAAASUVORK5CYII=",
        ]
        var incoming = [URL]()
        for (index, value) in encoded.enumerated() {
            let url = fixture.root.appendingPathComponent("precision\(index).png")
            try #require(Data(base64Encoded: value)).write(to: url)
            incoming.append(url)
        }
        try fixture.asset("Assets.xcassets/LowAlpha.imageset", images: [incoming[0]])
        let session = ProjectSession()
        await session.open(root: fixture.root, incoming: incoming).value
        #expect(session.results.map { $0.candidates.count } == [1, 1, 0])
    }

    @Test func orphanImageSetsAreIgnoredWithoutLeavingRoot() async throws {
        let fixture = try FixtureProject()
        defer { fixture.remove() }
        let incoming = try fixture.image("incoming.png")
        try fixture.asset("Orphan.imageset", images: [incoming])
        try fixture.asset("Nested/Assets.xcassets/Valid.imageset", images: [incoming])
        let session = ProjectSession()
        await session.open(root: fixture.root, incoming: [incoming]).value
        #expect(session.discovered == 1)
        #expect(session.results[0].candidates.map(\.name) == ["Valid"])
    }

    @Test func colourProfilesPreserveVisibleWideGamutDifferences() async throws {
        let fixture = try FixtureProject()
        defer { fixture.remove() }
        let original = try fixture.image("srgb.png")
        let wideGamut = try fixture.image("wide.png", colorSpace: #require(CGColorSpace(name: CGColorSpace.displayP3)))
        try fixture.asset("Assets.xcassets/Red.imageset", images: [original])
        let session = ProjectSession()
        await session.open(root: fixture.root, incoming: [original, wideGamut]).value
        #expect(session.results.map { $0.candidates.count } == [1, 0])
    }
}

// MARK: - FixtureProject

struct FixtureProject {
    let root: URL
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    func image(_ name: String, pixels: [UInt8] = [255, 0, 0, 255], width: Int = 1,
               orientation: Int = 1, metadata: String? = nil, quality: Double = 1,
               colorSpace: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!) throws -> URL
    {
        let url = root.appendingPathComponent(name)
        let data = Data(pixels)
        let provider = CGDataProvider(data: data as CFData)!
        let image = CGImage(width: width, height: pixels.count / 4 / width, bitsPerComponent: 8,
                            bitsPerPixel: 32, bytesPerRow: width * 4, space: colorSpace,
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
                            decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let type = name.hasSuffix(".jpg") ? UTType.jpeg : UTType.png
        let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
        var properties: [CFString: Any] = [kCGImagePropertyOrientation: orientation,
                                           kCGImageDestinationLossyCompressionQuality: quality]
        if let metadata {
            properties[kCGImagePropertyPNGDictionary] = [kCGImagePropertyPNGDescription: metadata]
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }

        return url
    }

    func asset(_ path: String, images: [URL]) throws {
        let folder = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var entries = [[String: String]]()
        for (index, image) in images.enumerated() {
            let name = "variant\(index).\(image.pathExtension)"
            try FileManager.default.copyItem(at: image, to: folder.appendingPathComponent(name))
            entries.append(["filename": name, "idiom": "universal", "scale": "\(index + 1)x"])
        }
        try JSONSerialization.data(withJSONObject: ["images": entries, "info": ["version": 1, "author": "xcode"]]).write(to: folder.appendingPathComponent("Contents.json"))
    }
}
