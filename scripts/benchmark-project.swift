import CryptoKit
import Foundation

/// Compile alongside the project session sources. Accepts a project URL at runtime.
/// Each iteration starts a new session with empty comparison caches, then measures a refresh.
/// Filesystem and OS caches are intentionally left intact for both versions.
@main struct BenchmarkProject {
    private enum Failure: Error {
        case scanFailed
        case changedResults
    }

    @MainActor static func main() async {
        do { try await measure() }
        catch {
            print("Benchmark failed: \(error)")
            exit(1)
        }
    }

    @MainActor private static func measure() async throws {
        guard CommandLine.arguments.count == 2 else {
            print("Usage: benchmark-project <project-root>")
            exit(1)
        }

        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        for iteration in 1 ... 3 {
            let session = ProjectSession()
            var heartbeats = 0
            let heartbeat = Task { @MainActor in
                while Task.isCancelled == false {
                    heartbeats += 1
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
            let start = ContinuousClock.now
            await session.open(root: root).value
            let cold = seconds(start.duration(to: .now))
            heartbeat.cancel()
            guard session.state == .complete, session.error == nil, session.observationError == nil, session.skipped == 0, session.discovered == session.compared else {
                throw Failure.scanFailed
            }

            let signature = signature(session)
            let decodes = session.imageDecodes
            let warmStart = ContinuousClock.now
            await session.refresh(incoming: []).value
            let warm = seconds(warmStart.duration(to: .now))
            guard session.state == .complete, signature == self.signature(session) else {
                throw Failure.changedResults
            }

            let record: [String: Any] = ["iteration": iteration, "coldSeconds": cold, "warmSeconds": warm, "warmDecodes": session.imageDecodes, "skipped": session.skipped, "assets": session.discovered, "groups": session.duplicateGroups.count, "decodes": decodes, "signature": signature, "heartbeats": heartbeats]
            try print(String(data: JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]), encoding: .utf8)!)
            await session.close().value
        }
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    @MainActor private static func signature(_ session: ProjectSession) -> String {
        let rows = session.duplicateGroups
            .lazy
            .map { group in
                group.id + ":" + group.members
                    .lazy
                    .map { member in
                        member.id + ":" + member.representations.lazy.map { $0.id + ":" + $0.label + ":" + String($0.matches) }.joined(separator: ",")
                    }
                    .joined(separator: ";")
            }
            .joined(separator: "\n")
        return SHA256.hash(data: Data(rows.utf8)).description
    }
}
