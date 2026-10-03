import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - ValidationFailure

/// Compile alongside the project lifecycle and comparison implementation; all inputs remain local.
private enum ValidationFailure: Error {
    case automaticScanFailed
    case invalidGroups
    case inconsistentMembership
    case incomingComparisonFailed
    case reviewFailed
    case projectChanged
}

// MARK: - ValidateProject

@main
struct ValidateProject {
    @MainActor static func main() async {
        do { try await validate() }
        catch {
            print("Validation failed: \(error)")
            exit(1)
        }
    }

    @MainActor private static func validate() async throws {
        let args = CommandLine.arguments
        guard args.count == 4 else {
            print("Usage: validate-project <project-root> <known-duplicate> <known-new-image>")
            throw CocoaError(.fileReadInvalidFileName)
        }

        let root = URL(fileURLWithPath: args[1])
        let before = try catalogContents(root)
        let duplicate = URL(fileURLWithPath: args[2])
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let reencoded = temporary.appendingPathComponent("reencoded.png")
        guard let source = CGImageSourceCreateWithURL(duplicate as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let destination = CGImageDestinationCreateWithURL(reencoded as CFURL, UTType.png.identifier as CFString, 1, nil)
        else {
            throw CocoaError(.fileReadCorruptFile)
        }

        var properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
        properties[kCGImagePropertyPNGDictionary] = [kCGImagePropertyPNGDescription: "Different metadata"]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let corrupt = temporary.appendingPathComponent("corrupt.png")
        try Data("not an image".utf8).write(to: corrupt)
        let inputs = [duplicate, URL(fileURLWithPath: args[3]), reencoded, corrupt]
        let session = ProjectSession()
        let started = ContinuousClock.now
        let automaticWork = session.open(root: root, incoming: [])
        var automaticHeartbeats = 0
        let automaticHeartbeat = Task { @MainActor in
            while session.isRunning, Task.isCancelled == false {
                automaticHeartbeats += 1
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        await automaticWork.value
        automaticHeartbeat.cancel()
        guard session.state == .complete else {
            throw ValidationFailure.automaticScanFailed
        }

        let groups = session.duplicateGroups
        guard groups.allSatisfy({ group in
            group.members.count >= 2 && Set(group.members.map(\.id)).count == group.members.count &&
                group.members.allSatisfy { $0.representations.contains(where: \.matches) }
        }), Set(groups.map(\.id)).count == groups.count else {
            throw ValidationFailure.invalidGroups
        }

        if let group = groups.first,
           let reference = group.members.first?.representations.first(where: \.matches)?.url
        {
            await session.refresh(incoming: [reference]).value
            guard Set(session.results[0].candidates.map(\.id)) == Set(group.members.map(\.id)) else {
                throw ValidationFailure.inconsistentMembership
            }
        }
        print("Automatic project scan: \(session.discovered) assets; \(groups.count) duplicate groups; \(session.skipped) skipped; \(automaticHeartbeats) main-actor heartbeats. Group membership agrees with incoming comparison.")
        let work = session.refresh(incoming: inputs)
        var heartbeats = 0
        let heartbeat = Task { @MainActor in
            while session.isRunning, Task.isCancelled == false {
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
              session.results[0].candidates.isEmpty == false, session.results[1].candidates.isEmpty
        else {
            print("Acceptance failed: scan error, unreadable input, missed duplicate, or false exact match.")
            throw ValidationFailure.incomingComparisonFailed
        }

        let candidate = session.results[0].candidates[0]
        guard let representation = candidate.representations.first(where: \.matches),
              session.reuseAsset(for: inputs[0], candidateID: candidate.id, representationID: representation.id),
              session.review(for: inputs[0]).outcome == .reuse(candidate: candidate, representation: representation)
        else {
            throw ValidationFailure.reviewFailed
        }

        session.keepAsNew(inputs[1])
        session.keepAsNew(inputs[2])
        guard session.reviewedCount == 3,
              session.results[2].candidates.isEmpty == false,
              session.review(for: inputs[2]).outcome == .keepAsNew
        else {
            throw ValidationFailure.reviewFailed
        }

        await session.refresh(incoming: inputs).value
        guard session.reviewedCount == 3,
              session.review(for: inputs[0]).outcome == .reuse(candidate: candidate, representation: representation),
              session.review(for: inputs[0]).representationIDs[candidate.id] == representation.id,
              session.review(for: inputs[1]).outcome == .keepAsNew
        else {
            throw ValidationFailure.reviewFailed
        }

        let after = try catalogContents(root)
        guard before == after else {
            throw ValidationFailure.projectChanged
        }

        print("Review acceptance passed: both outcomes retained after rescan, matching identity and representation retained, candidates preserved, catalog contents unchanged.")

        print("Acceptance passed: \(session.discovered) assets; \(session.skipped) skipped; \(session.results[0].candidates.count) grouped duplicate matches; metadata/re-encoding and corrupt-input checks passed; new image has zero matches; \(heartbeats) main-actor heartbeats; elapsed \(started.duration(to: .now)).")
    }

    private static func catalogContents(_ root: URL) throws -> [String: String] {
        let boundary = root.standardizedFileURL
        let rules = ProjectIgnoreRules(root: boundary)
        guard let files = FileManager.default.enumerator(at: boundary, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]) else {
            throw CocoaError(.fileReadUnknown)
        }

        var contents = [String: String]()
        for case let url as URL in files {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey])
            if try values.isSymbolicLink == true || url.lastPathComponent == ".git" ||
                (rules.ignores(url, isDirectory: values.isDirectory == true))
            {
                files.skipDescendants()
                continue
            }
            guard url.pathComponents.contains(where: { $0.hasSuffix(".xcassets") }), values.isRegularFile == true else {
                continue
            }

            contents[url.path] = try SHA256.hash(data: Data(contentsOf: url)).description
        }
        return contents
    }
}
