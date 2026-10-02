import Foundation
import Darwin

/// Apply project-local .gitignore files without requiring Git or leaving the sandbox.
final class ProjectIgnoreRules {
    private struct Rule {
        let directory: URL
        let pattern: String
        let directoryOnly: Bool
        let negated: Bool
        let anchored: Bool

        init?(_ line: String, directory: URL) {
            var pattern = line
            while pattern.last == " " {
                let preceding = pattern.dropLast().reversed().prefix { $0 == "\\" }.count
                if preceding % 2 == 1 { break }
                pattern.removeLast()
            }
            guard !pattern.isEmpty, !pattern.hasPrefix("#") else { return nil }
            negated = pattern.hasPrefix("!")
            if negated { pattern.removeFirst() }
            anchored = pattern.hasPrefix("/")
            if anchored { pattern.removeFirst() }
            directoryOnly = pattern.hasSuffix("/")
            if directoryOnly { pattern.removeLast() }
            guard !pattern.isEmpty else { return nil }
            self.directory = directory
            self.pattern = pattern
        }

        func matches(_ url: URL, isDirectory: Bool) -> Bool {
            guard !directoryOnly || isDirectory else { return false }
            let relative = String(url.path.dropFirst(directory.path.hasSuffix("/") ? directory.path.count : directory.path.count + 1))
            if !anchored && !pattern.contains("/") {
                return Self.componentMatches(pattern, url.lastPathComponent)
            }
            return Self.pathMatches(pattern.split(separator: "/").map(String.init),
                                    relative.split(separator: "/").map(String.init))
        }

        private static func componentMatches(_ pattern: String, _ name: String) -> Bool {
            pattern.withCString { pattern in
                name.withCString { name in fnmatch(pattern, name, FNM_PATHNAME) == 0 }
            }
        }

        private static func pathMatches(_ pattern: [String], _ path: [String]) -> Bool {
            // Globstar matches whole directory components, including zero intermediate directories.
            var visited = Set<[Int]>()
            func match(_ ruleIndex: Int, _ pathIndex: Int) -> Bool {
                guard visited.insert([ruleIndex, pathIndex]).inserted else { return false }
                if ruleIndex == pattern.count { return pathIndex == path.count }
                if pattern[ruleIndex] == "**" {
                    if ruleIndex == pattern.count - 1 { return pathIndex < path.count }
                    return match(ruleIndex + 1, pathIndex) ||
                        (pathIndex < path.count && match(ruleIndex, pathIndex + 1))
                }
                return pathIndex < path.count && componentMatches(pattern[ruleIndex], path[pathIndex]) &&
                    match(ruleIndex + 1, pathIndex + 1)
            }
            return match(0, 0)
        }
    }

    private let root: URL
    private var cache: [URL: [Rule]] = [:]

    init(root: URL) { self.root = root }

    func ignores(_ url: URL, isDirectory: Bool) throws -> Bool {
        var ignored = false
        for rule in try rules(in: url.deletingLastPathComponent()) where rule.matches(url, isDirectory: isDirectory) {
            ignored = !rule.negated
        }
        return ignored
    }

    private func rules(in directory: URL) throws -> [Rule] {
        if let cached = cache[directory] { return cached }
        var rules = directory == root ? [] : try self.rules(in: directory.deletingLastPathComponent())
        let file = directory.appendingPathComponent(".gitignore")
        // Git does not follow symbolic links when reading .gitignore files.
        if FileManager.default.fileExists(atPath: file.path),
           try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true {
            let text = try String(contentsOf: file, encoding: .utf8)
            rules += text.components(separatedBy: .newlines).compactMap { Rule($0, directory: directory) }
        }
        cache[directory] = rules
        return rules
    }
}
