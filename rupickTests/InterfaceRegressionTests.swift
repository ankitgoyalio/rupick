#if DEBUG
    import Foundation
    import ImageIO
    @testable import rupick
    import Testing
    import UniformTypeIdentifiers

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
            await session.open(root: root, incoming: []).value
            #expect(session.duplicateGroups.count == 1)
            let previous = session.duplicateGroups
            // Starting the new scan must not blank out the currently inspected group.
            let refresh = session.refresh(incoming: [])
            #expect(session.duplicateGroups == previous)
            await refresh.value
            #expect(session.duplicateGroups == previous)
            try FileManager.default.removeItem(at: root.appendingPathComponent("Packages"))
            await session.refresh(incoming: []).value
            try await eventually { session.duplicateGroups.isEmpty && session.state == .complete }
        }

        @Test func aliasedProjectRootSharesDiscoveryAndObservationBoundary() async throws {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let source = try StressDataset.demo.makeProject()
            defer { try? FileManager.default.removeItem(at: source) }
            try FileManager.default.copyItem(at: source.appendingPathComponent("Packages"), to: root.appendingPathComponent("Packages"))
            let alias = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root)
            defer { try? FileManager.default.removeItem(at: alias) }
            let session = ProjectSession()
            await session.open(root: alias).value
            #expect(session.state == .complete)
            #expect(session.duplicateGroups.count == 1)
            try FileManager.default.removeItem(at: root.appendingPathComponent("Packages"))
            try await eventually { session.state == .complete && session.duplicateGroups.isEmpty }
            await session.close().value
        }

        @Test func observationAcceptsRootWithoutDirectoryHint() async throws {
            let root = try StressDataset.demo.makeProject()
            defer { try? FileManager.default.removeItem(at: root) }
            let session = ProjectSession()
            let selected = URL(fileURLWithPath: root.path, isDirectory: false)
            await session.open(root: selected).value
            #expect(session.state == .complete)
            #expect(session.duplicateGroups.count == 1)
            await session.close().value
        }

        @Test func metadataRefreshReusesUnchangedComparisonsBeyondPixelCacheCapacity() async throws {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let fixture = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("fixtures/ExactMatching/Incoming/new.png")
            let bytes = try Data(contentsOf: fixture)
            for index in 0 ..< 150 {
                let entry = root.appendingPathComponent("Assets.xcassets/Image\(index).imageset")
                try FileManager.default.createDirectory(at: entry, withIntermediateDirectories: true)
                var image = bytes
                image.append(contentsOf: Array("variant \(index)".utf8))
                try image.write(to: entry.appendingPathComponent("image.png"))
                try Data(#"{"images":[{"filename":"image.png","scale":"1x"}]}"#.utf8).write(to: entry.appendingPathComponent("Contents.json"))
            }
            let session = ProjectSession()
            await session.open(root: root).value
            #expect(session.duplicateGroups.first?.members.count == 150)
            let decoded = session.imageDecodes
            #expect(decoded >= 150)
            let metadata = root.appendingPathComponent("Assets.xcassets/Image149.imageset/Contents.json")
            try Data(#"{"images":[{"filename":"image.png","scale":"3x"}]}"#.utf8).write(to: metadata)
            await session.refresh(incoming: []).value
            #expect(session.duplicateGroups.first?.members.count == 150)
            try await eventually { session.state == .complete && session.duplicateGroups.first?.members.contains(where: { $0.name == "Image149" && $0.representations.first?.label.contains("3x") == true }) == true }
            #expect(session.imageDecodes == 0)
            await session.close().value
        }

        @Test func catalogDeletionAutomaticallyReconcilesResults() async throws {
            let root = try StressDataset.demo.makeProject()
            defer { try? FileManager.default.removeItem(at: root) }
            let session = ProjectSession()
            await session.open(root: root).value
            #expect(session.duplicateGroups.count == 1)
            try FileManager.default.removeItem(at: root.appendingPathComponent("Packages"))
            let deadline = ContinuousClock.now.advanced(by: .seconds(8))
            while session.duplicateGroups.isEmpty == false, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            #expect(session.duplicateGroups.isEmpty)
            #expect(session.state == .complete)
            await session.close().value
        }

        @Test func catalogEditsReconcileFinalContentMetadataAndCompleteness() async throws {
            let root = try StressDataset.demo.makeProject()
            defer { try? FileManager.default.removeItem(at: root) }
            let session = ProjectSession()
            await session.open(root: root).value
            let catalog = root.appendingPathComponent("Added.xcassets")
            let entry = catalog.appendingPathComponent("Added.imageset")
            let source = try #require(session.duplicateGroups.first?.members.first?.representations.first(where: \.matches)?.url)
            let incoming = root.appendingPathComponent("incoming.png")
            try FileManager.default.copyItem(at: source, to: incoming)
            await session.refresh(incoming: [incoming]).value
            let initialCount = session.discovered
            let initialMatches = session.results[0].candidates.count
            try FileManager.default.createDirectory(at: entry, withIntermediateDirectories: true)
            let image = entry.appendingPathComponent("image.png")
            try FileManager.default.copyItem(at: source, to: image)
            let metadata = entry.appendingPathComponent("Contents.json")
            try Data(#"{"images":[{"filename":"image.png","scale":"2x"}]}"#.utf8).write(to: metadata)
            try await eventually { session.state == .complete && session.discovered == initialCount + 1 }
            #expect(session.results[0].candidates.count == initialMatches + 1)
            let candidate = try #require(session.results[0].candidates.first { $0.id == entry.path })
            #expect(candidate.representations[0].label.contains("2x"))
            #expect(session.reuseAsset(for: incoming, candidateID: candidate.id, representationID: candidate.representations[0].id))
            let oldPreview = session.thumbnails.id
            try Data(#"{"images":[{"filename":"image.png","scale":"3x"}]}"#.utf8).write(to: metadata, options: .atomic)
            try await eventually { session.state == .complete && session.results[0].candidates.first(where: { $0.id == entry.path })?.representations[0].label.contains("3x") == true }
            #expect(session.thumbnails.id != oldPreview)
            // Burst corruption followed by a final corrupt file must remain isolated.
            for _ in 0 ..< 8 {
                try Data("broken".utf8).write(to: image, options: .atomic)
            }
            try await eventually { session.state == .complete && session.skipped > 0 }
            #expect(session.results[0].status == .incomplete)
            #expect(session.results[0].candidates.count == initialMatches)
            #expect(session.review(for: incoming).outcome == nil)
            try FileManager.default.copyItem(at: source, to: entry.appendingPathComponent("restored.png"))
            try Data(#"{"images":[{"filename":"restored.png","scale":"1x"}]}"#.utf8).write(to: metadata)
            try await eventually { session.state == .complete && session.skipped == 0 && session.results[0].candidates.count == initialMatches + 1 }
            #expect(session.results[0].status == .complete)
            try Data("Added.xcassets/\n".utf8).write(to: root.appendingPathComponent(".gitignore"))
            try await eventually { session.state == .complete && session.discovered == initialCount }
            try FileManager.default.removeItem(at: root.appendingPathComponent(".gitignore"))
            try await eventually { session.state == .complete && session.discovered == initialCount + 1 }
            try FileManager.default.removeItem(at: catalog)
            try await eventually { session.state == .complete && session.discovered == initialCount }
            #expect(session.results[0].candidates.count == initialMatches)
            await session.close().value
        }

        private func eventually(_ condition: () -> Bool) async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(10))
            while condition() == false, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            try #require(condition())
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
            await session.open(root: root, incoming: [first]).value
            let candidates = try #require(session.results.first).candidates
            #expect(candidates.isEmpty == false)
            let refresh = session.refresh(incoming: [first, second])
            #expect(session.results.first?.candidates == candidates)
            #expect(session.results.first?.status == .comparing)
            await refresh.value
            #expect(session.results.count == 2)
            #expect(session.results.allSatisfy { $0.candidates.count == candidates.count && $0.status == .complete })
        }

        @Test(arguments: [StressDataset.empty, .one, .worst, .thousand])
        func reviewStressDatasets(dataset: StressDataset) async throws {
            let root = try dataset.makeProject()
            defer { try? FileManager.default.removeItem(at: root) }
            let incoming = try dataset.makeIncomingImages(in: root)
            let session = ProjectSession()
            await session.open(root: root, incoming: incoming).value
            guard let first = incoming.first, let candidate = session.results.first?.candidates.last,
                  let representation = candidate.representations.first(where: \.matches)
            else {
                #expect(dataset == .empty && session.reviewedCount == 0)
                return
            }

            #expect(session.reuseAsset(for: first, candidateID: candidate.id, representationID: representation.id))
            for url in incoming.dropFirst() {
                session.keepAsNew(url)
            }
            #expect(session.reviewedCount == incoming.count)
            await session.refresh(incoming: incoming).value
            #expect(session.reviewedCount == incoming.count)
            #expect(session.review(for: first).outcome == .reuse(candidate: candidate, representation: representation))
            #expect(session.results.first?.candidates.count == (dataset == .thousand ? 1000 : dataset == .worst ? 16 : 1))
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
            await session.open(root: root, incoming: []).value
            #expect(session.state == .complete)
            switch dataset {
            case .empty:
                #expect(session.discovered == 0 && session.duplicateGroups.isEmpty)

            case .one:
                #expect(session.discovered == 1 && session.duplicateGroups.isEmpty)

            case .worst:
                #expect(session.duplicateGroups.contains { $0.members.count == 16 })
                #expect(session.skipped == 3)

            case .thousand:
                #expect(session.duplicateGroups.first?.members.count == 1000)

            case .demo:
                break
            }
        }
    }

#endif
