import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Compile alongside ProjectSession.swift and CatalogComparison.swift; all inputs remain local.
@main
struct ValidateProject {
    @MainActor static func main() async throws {
        let args = CommandLine.arguments
        guard args.count == 4 else {
            print("Usage: validate-project <project-root> <known-duplicate> <known-new-image>")
            throw CocoaError(.fileReadInvalidFileName)
        }
        let root = URL(fileURLWithPath: args[1])
        let duplicate = URL(fileURLWithPath: args[2])
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let reencoded = temporary.appendingPathComponent("reencoded.png")
        guard let source = CGImageSourceCreateWithURL(duplicate as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let destination = CGImageDestinationCreateWithURL(reencoded as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
        properties[kCGImagePropertyPNGDictionary] = [kCGImagePropertyPNGDescription: "Different metadata"]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        let corrupt = temporary.appendingPathComponent("corrupt.png")
        try Data("not an image".utf8).write(to: corrupt)
        let inputs = [duplicate, URL(fileURLWithPath: args[3]), reencoded, corrupt]
        let session = ProjectSession()
        let started = ContinuousClock.now
        let work = session.start(root: root, incoming: inputs)
        var heartbeats = 0
        let heartbeat = Task { @MainActor in
            while session.isRunning {
                heartbeats += 1
                if heartbeats % 10 == 0 {
                    print("Progress: \(session.compared)/\(session.discovered) assets, \(session.skipped) skipped")
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        await work.value
        heartbeat.cancel()
        guard session.error == nil, session.results.prefix(3).allSatisfy({ $0.error == nil }),
              session.results[3].error != nil,
              session.results[0].candidates.map(\.id) == session.results[2].candidates.map(\.id),
              !session.results[0].candidates.isEmpty, session.results[1].candidates.isEmpty else {
            print("Acceptance failed: scan error, unreadable input, missed duplicate, or false exact match.")
            throw CocoaError(.fileReadCorruptFile)
        }
        print("Acceptance passed: \(session.discovered) assets; \(session.skipped) skipped; \(session.results[0].candidates.count) grouped duplicate matches; metadata/re-encoding and corrupt-input checks passed; new image has zero matches; \(heartbeats) main-actor heartbeats; elapsed \(started.duration(to: .now)).")
    }
}
