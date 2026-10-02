import Foundation
import Testing
import ImageIO
import UniformTypeIdentifiers
@testable import rupick

@MainActor
struct ProjectSessionTests {
    @Test func renamedImageMatchesCatalogEntry() async throws {
        let fixture = try FixtureProject()
        defer { fixture.remove() }
        let incoming = try fixture.image("incoming.png")
        try fixture.asset("First.xcassets/Icon.imageset", images: [incoming])
        let session = ProjectSession()
        await session.start(root: fixture.root, incoming: [incoming]).value
        #expect(session.isRunning == false)
        #expect(session.results.first?.candidates.map(\.name) == ["Icon"])
    }
    @Test(arguments: [
        ([255, 0, 0, 255, 2, 3, 4, 0], 2, true),
        ([254, 0, 0, 255, 2, 3, 4, 0], 2, false),
        ([255, 0, 0, 255, 2, 3, 4, 1], 2, false),
        ([255, 0, 0, 255, 2, 3, 4, 0], 1, false),
        ([255, 0, 0, 255, 2, 3, 4, 0, 0, 0, 0, 0], 3, false)
    ])
    func exactPixelRules(pixels: [UInt8], width: Int, matches: Bool) async throws {
        let fixture = try FixtureProject()
        defer { fixture.remove() }
        let original = try fixture.image("original.png", pixels: [255, 0, 0, 255, 90, 80, 70, 0], width: 2)
        let incoming = try fixture.image("renamed.png", pixels: pixels, width: width, metadata: "New metadata")
        try fixture.asset("Assets.xcassets/Icon.imageset", images: [original])
        let session = ProjectSession()
        await session.start(root: fixture.root, incoming: [incoming]).value
        #expect((session.results[0].candidates.count == 1) == matches)
    }

    @Test func lowAlphaDifferencesRemainVisible() async throws {
        let fixture = try FixtureProject()
        defer { fixture.remove() }
        let original = try fixture.image("original.png", pixels: [100, 0, 0, 1])
        let incoming = try fixture.image("incoming.png", pixels: [101, 0, 0, 1])
        try fixture.asset("Assets.xcassets/Icon.imageset", images: [original])
        let session = ProjectSession()
        await session.start(root: fixture.root, incoming: [incoming]).value
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
        await session.start(root: fixture.root, incoming: [incoming]).value
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
        await session.start(root: fixture.root, incoming: [copy, changed]).value
        #expect(session.results.map { $0.candidates.count } == [1, 0])
    }

    @Test func orientationNormalizesDimensionsAndPixels() async throws {
        let fixture = try FixtureProject()
        defer { fixture.remove() }
        let original = try fixture.image("original.png", pixels: [255, 0, 0, 255, 0, 0, 255, 255], width: 2)
        let rotated = try fixture.image("rotated.png", pixels: [0, 0, 255, 255, 255, 0, 0, 255], width: 1, orientation: 6)
        try fixture.asset("Assets.xcassets/Icon.imageset", images: [original])
        let session = ProjectSession()
        await session.start(root: fixture.root, incoming: [rotated]).value
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
        await session.start(root: fixture.root, incoming: [broken, incoming]).value
        #expect(session.results[0].error != nil)
        #expect(session.results[1].candidates.count == 1)
        #expect(session.skipped == 1)
        #expect(session.error == nil)
    }

    @Test func neverFollowsCatalogOrRepresentationSymlinksOutsideRoot() async throws {
        let fixture = try FixtureProject(), outside = try FixtureProject()
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
        await session.start(root: fixture.root, incoming: [incoming]).value
        #expect(session.discovered == 1)
        #expect(session.results[0].candidates.isEmpty)
        #expect(session.skipped == 1)
    }

    @Test func newerSelectionCannotBeOverwrittenByOldWork() async throws {
        let first = try FixtureProject(), second = try FixtureProject()
        defer { first.remove(); second.remove() }
        let incoming = try first.image("incoming.png")
        try first.asset("Assets.xcassets/Icon.imageset", images: [incoming])
        let session = ProjectSession()
        let old = session.start(root: first.root, incoming: [incoming])
        let current = session.start(root: second.root, incoming: [incoming])
        await current.value; await old.value
        #expect(session.root == second.root)
        #expect(session.results[0].candidates.isEmpty)
        #expect(!session.isRunning)
    }

    @Test func provisionalResultsArriveBeforeCompletionAndCanBeCancelled() async throws {
        let fixture = try FixtureProject()
        defer { fixture.remove() }
        let incoming = try fixture.image("incoming.png")
        for index in 0..<100 {
            try fixture.asset("Assets.xcassets/Icon\(index).imageset", images: [incoming])
        }
        let session = ProjectSession()
        let task = session.start(root: fixture.root, incoming: [incoming])
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while session.compared == 0 && session.isRunning && ContinuousClock.now < deadline { await Task.yield() }
        #expect(session.isRunning)
        #expect(session.compared > 0 && session.compared < session.discovered)
        #expect(!session.results[0].candidates.isEmpty)
        session.cancel()
        await task.value
        #expect(!session.isRunning)
        #expect(session.phase.contains("incomplete"))
    }

    @Test func missingRootIsAFailureRatherThanNoMatches() async throws {
        let session = ProjectSession()
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        await session.start(root: missing, incoming: []).value
        #expect(session.error != nil)
        #expect(session.phase == "Search failed")
    }


}

struct FixtureProject {
    let root: URL
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
    func image(_ name: String, pixels: [UInt8] = [255, 0, 0, 255], width: Int = 1,
               orientation: Int = 1, metadata: String? = nil, quality: Double = 1) throws -> URL {
        let url = root.appendingPathComponent(name)
        let data = Data(pixels)
        let provider = CGDataProvider(data: data as CFData)!
        let image = CGImage(width: width, height: pixels.count / 4 / width, bitsPerComponent: 8,
            bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let type = name.hasSuffix(".jpg") ? UTType.jpeg : UTType.png
        let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
        var properties: [CFString: Any] = [kCGImagePropertyOrientation: orientation,
                                          kCGImageDestinationLossyCompressionQuality: quality]
        if let metadata { properties[kCGImagePropertyPNGDictionary] = [kCGImagePropertyPNGDescription: metadata] }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return url
    }
    func asset(_ path: String, images: [URL]) throws {
        let folder = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var entries: [[String: String]] = []
        for (index, image) in images.enumerated() {
            let name = "variant\(index).\(image.pathExtension)"
            try FileManager.default.copyItem(at: image, to: folder.appendingPathComponent(name))
            entries.append(["filename": name, "idiom": "universal", "scale": "\(index + 1)x"])
        }
        try JSONSerialization.data(withJSONObject: ["images": entries, "info": ["version": 1, "author": "xcode"]]).write(to: folder.appendingPathComponent("Contents.json"))
    }
}
