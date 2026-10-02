import XCTest
import AppKit
import ImageIO
import UniformTypeIdentifiers

final class rupickUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testProjectDuplicateGroupsWithoutIncomingImages() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("rupick-duplicates-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try copyFixture(to: root)
        let third = root.appendingPathComponent("App/Primary.xcassets/Third.imageset")
        try FileManager.default.createDirectory(at: third, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: root.appendingPathComponent("Incoming/renamed.png"), to: third.appendingPathComponent("copy.png"))
        try Data(#"{"images":[{"filename":"copy.png","scale":"3x"}]}"#.utf8).write(to: third.appendingPathComponent("Contents.json"))
        let unique = root.appendingPathComponent("App/Primary.xcassets/Unique.imageset")
        try FileManager.default.createDirectory(at: unique, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: root.appendingPathComponent("Incoming/new.png"), to: unique.appendingPathComponent("unique.png"))
        try Data(#"{"images":[{"filename":"unique.png"}]}"#.utf8).write(to: unique.appendingPathComponent("Contents.json"))
        let app = XCUIApplication()
        app.launch()
        app.buttons["openProject"].click()
        choose(root.path, in: app)
        XCTAssertTrue(app.staticTexts["Search complete"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["3 assets with equal content"].exists)
        XCTAssertTrue(app.staticTexts["2 assets with equal content"].exists)
        XCTAssertTrue(app.staticTexts["Exact duplicate content"].exists)
        XCTAssertTrue(app.staticTexts["App/Primary.xcassets/Icon.imageset"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Packages/Other.xcassets/Icon.imageset"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["App/Primary.xcassets/Third.imageset"].exists)
        XCTAssertFalse(app.staticTexts["IgnoredDuplicate"].exists)
        XCTAssertFalse(app.staticTexts["Unique"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Incomplete scan: 1")).firstMatch.exists)
        XCTAssertEqual(app.popUpButtons.matching(identifier: "duplicateMemberPicker").count, 2)
        let picker = app.popUpButtons["duplicateRepresentationPicker"].firstMatch
        picker.click()
        app.menuItems.matching(NSPredicate(format: "title CONTAINS %@", "Alternative")).firstMatch.click()
        XCTAssertTrue(app.staticTexts["Alternative representation"].waitForExistence(timeout: 5))
        let memberPicker = app.popUpButtons["duplicateMemberPicker"].firstMatch
        memberPicker.click()
        app.menuItems.matching(NSPredicate(format: "title CONTAINS %@", "Third.imageset")).firstMatch.click()
        XCTAssertTrue(app.staticTexts["copy.png"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value CONTAINS %@", "safe to delete")).firstMatch.exists)
    }

    @MainActor
    func testCompletedProjectScanHasDistinctEmptyState() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("rupick-empty-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let app = XCUIApplication()
        app.launch()
        app.buttons["openProject"].click()
        choose(root.path, in: app)
        XCTAssertTrue(app.staticTexts["Search complete"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["No exact duplicates found"].exists)
    }

    @MainActor
    func testNativePickersAndRepresentationInspection() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("rupick-ui-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try copyFixture(to: root)
        try addJPEG(to: root)
        let app = XCUIApplication()
        app.launch()
        app.buttons["openProject"].click()
        choose(root.path, in: app)
        XCTAssertTrue(app.staticTexts["Search complete"].waitForExistence(timeout: 30))
        app.buttons["chooseImages"].click()
        choose(root.appendingPathComponent("Incoming/renamed.png").path, in: app)
        XCTAssertTrue(app.staticTexts["Incomplete search · 2 matches so far"].waitForExistence(timeout: 30))
        XCTAssertEqual(app.staticTexts.matching(identifier: "Icon").count, 2)
        XCTAssertTrue(app.staticTexts["App/Primary.xcassets/Icon.imageset"].exists)
        XCTAssertTrue(app.staticTexts["Packages/Other.xcassets/Icon.imageset"].exists)
        XCTAssertTrue(app.staticTexts["Incoming"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Exact match"].firstMatch.exists)
        let picker = app.popUpButtons["representationPicker"].firstMatch
        XCTAssertTrue(picker.exists)
        picker.click()
        app.menuItems.matching(NSPredicate(format: "title CONTAINS %@", "Alternative")).firstMatch.click()
        XCTAssertTrue(app.staticTexts["Alternative representation"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value CONTAINS %@", "Resized copies")).firstMatch.exists)
    }

    @MainActor
    func testMixedBatchPickerAndListNavigation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("rupick-batch-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try copyFixture(to: root)
        try addJPEG(to: root)
        let app = XCUIApplication()
        app.launch()
        app.buttons["openProject"].click()
        choose(root.path, in: app)
        XCTAssertTrue(app.staticTexts["Search complete"].waitForExistence(timeout: 30))
        app.buttons["chooseImages"].click()
        choose(root.appendingPathComponent("Incoming").path, in: app, selectAll: true)
        assertMixedBatch(in: app)
    }

    @MainActor
    func testCompletedNoMatchesAndScanFailureAreDistinct() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("rupick-clean-\(UUID().uuidString)")
        let input = FileManager.default.temporaryDirectory.appendingPathComponent("rupick-new-\(UUID().uuidString).png")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: input)
        }
        try copyFixture(to: root)
        try FileManager.default.removeItem(at: root.appendingPathComponent("App/Primary.xcassets/Broken.imageset"))
        try FileManager.default.copyItem(at: root.appendingPathComponent("Incoming/new.png"), to: input)
        let app = XCUIApplication()
        app.launch()
        app.buttons["openProject"].click()
        choose(root.path, in: app)
        XCTAssertTrue(app.staticTexts["Search complete"].waitForExistence(timeout: 30))
        app.buttons["chooseImages"].click()
        choose(root.appendingPathComponent("Incoming/new.png").path, in: app)
        XCTAssertTrue(app.staticTexts["No matches found"].firstMatch.waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value CONTAINS %@", "does not guarantee")).firstMatch.exists)
        try FileManager.default.removeItem(at: root)
        app.buttons["chooseImages"].click()
        choose(input.path, in: app)
        XCTAssertTrue(app.staticTexts["Search failed"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["Search failed. Open the project folder again to retry."].exists)
        XCTAssertFalse(app.staticTexts["No matches found"].exists)
    }

    @MainActor
    func testFinderBatchDrop() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("rupick-drop-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try copyFixture(to: root)
        try addJPEG(to: root)
        let app = XCUIApplication()
        app.launch()
        app.buttons["openProject"].click()
        choose(root.path, in: app)
        XCTAssertTrue(app.staticTexts["Search complete"].waitForExistence(timeout: 30))
        NSWorkspace.shared.open(root.appendingPathComponent("Incoming"))
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        finder.activate()
        let window = finder.windows["Incoming"]
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        finder.typeKey("2", modifierFlags: .command)
        finder.typeKey("a", modifierFlags: .command)
        let file = window.descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR value == %@", "renamed.png", "renamed.png")).firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 10))
        let source = file.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let target = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.7))
        source.press(forDuration: 1, thenDragTo: target)
        app.activate()
        assertMixedBatch(in: app)
        finder.activate()
        finder.typeKey("w", modifierFlags: .command)
    }

    private func copyFixture(to root: URL) throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("fixtures/ExactMatching")
        try FileManager.default.copyItem(at: fixture, to: root)
        try Data().write(to: root.appendingPathComponent(".DS_Store"))
        let ignoredCatalog = root.appendingPathComponent("Dependencies/Ignored.xcassets")
        try FileManager.default.createDirectory(at: ignoredCatalog, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: root.appendingPathComponent("App/Primary.xcassets/Icon.imageset"),
                                         to: ignoredCatalog.appendingPathComponent("IgnoredDuplicate.imageset"))
        let broken = ignoredCatalog.appendingPathComponent("Broken.imageset")
        try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
        try Data("invalid".utf8).write(to: broken.appendingPathComponent("Contents.json"))
        try Data("Dependencies/\n.DS_Store\n".utf8).write(to: root.appendingPathComponent(".gitignore"))
    }

    private func addJPEG(to root: URL) throws {
        let input = root.appendingPathComponent("Incoming/new.png")
        let output = root.appendingPathComponent("Incoming/new.jpg")
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(input as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(output as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        try FileManager.default.copyItem(at: output, to: root.appendingPathComponent("Incoming/new.jpe"))
    }

    @MainActor
    private func assertMixedBatch(in app: XCUIApplication) {
        for name in ["broken.png", "renamed.png", "new.png", "new.jpg", "new.jpe"] {
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "incoming-" + name).firstMatch.waitForExistence(timeout: 30))
        }
        let broken = app.staticTexts["broken.png"].firstMatch
        XCTAssertTrue(broken.waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["Search complete"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["3 / 3 assets compared"].exists)
        XCTAssertTrue(app.staticTexts["Incomplete scan: 1 unreadable or unsupported catalog entries or images were skipped."].exists)
        broken.click()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Could not read this PNG")).firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["No matches found"].exists)
        XCTAssertFalse(app.staticTexts["comparisonStatus"].exists)
        app.staticTexts["renamed.png"].firstMatch.click()
        XCTAssertTrue(app.staticTexts["Exact match"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Incoming"].firstMatch.exists)
        app.staticTexts["new.png"].firstMatch.click()
        XCTAssertTrue(app.staticTexts["Incomplete search · 0 matches so far"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["No matches found"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Incomplete scan:")).firstMatch.exists)
    }

    @MainActor
    func testRealProjectWhenAcceptanceConfigIsProvided() throws {
        // Optional local-only config. No project-specific paths or assets are stored in the repository.
        let configURL = URL(fileURLWithPath: "/tmp/rupick-acceptance.json")
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            throw XCTSkip("Provide the documented local acceptance config to run against another project.")
        }
        let config = try JSONDecoder().decode(AcceptanceConfig.self, from: Data(contentsOf: configURL))
        let app = XCUIApplication()
        app.launch()
        app.buttons["openProject"].click()
        choose(config.root, in: app)
        if app.buttons["Cancel Search"].exists {
            app.buttons["chooseImages"].click()
            let panel = app.windows["open-panel"]
            XCTAssertTrue(panel.waitForExistence(timeout: 5))
            panel.buttons["CancelButton"].click()
        }
        XCTAssertTrue(app.staticTexts["Search complete"].waitForExistence(timeout: 180))
        if let expectedGroups = config.expectedDuplicateGroups {
            XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "value ENDSWITH %@", "assets with equal content")).count, expectedGroups)
            if expectedGroups > 0 {
                XCTAssertTrue(app.staticTexts["Exact duplicate content"].exists)
                XCTAssertEqual(app.popUpButtons.matching(identifier: "duplicateMemberPicker").count, 2)
                XCTAssertEqual(app.popUpButtons.matching(identifier: "duplicateRepresentationPicker").count, 2)
            }
        }
        if let expectedAssets = config.expectedAssets {
            XCTAssertTrue(app.staticTexts["\(expectedAssets) / \(expectedAssets) assets compared"].exists)
        }
        if config.expectedSkipped == 0 {
            XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Incomplete scan:")).firstMatch.exists)
        }
        if let batchFolder = config.batchFolder {
            app.buttons["chooseImages"].click()
            choose(batchFolder, in: app, selectAll: true)
            let newRow = app.staticTexts[URL(fileURLWithPath: config.newImage).lastPathComponent].firstMatch
            XCTAssertTrue(newRow.waitForExistence(timeout: 10))
            newRow.click()
            if app.buttons["Cancel Search"].exists {
                XCTAssertFalse(app.staticTexts["No matches found"].exists)
                app.buttons["chooseImages"].click()
                let panel = app.windows["open-panel"]
                XCTAssertTrue(panel.waitForExistence(timeout: 5))
                panel.buttons["CancelButton"].click()
            }
            XCTAssertTrue(app.staticTexts["Search complete"].waitForExistence(timeout: 180))
            app.staticTexts[URL(fileURLWithPath: config.duplicate).lastPathComponent].firstMatch.click()
            XCTAssertTrue(app.staticTexts["Exact match"].firstMatch.waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["Incoming"].firstMatch.exists)
            app.staticTexts["broken.png"].firstMatch.click()
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Could not read this PNG")).firstMatch.waitForExistence(timeout: 10))
            XCTAssertFalse(app.staticTexts["comparisonStatus"].exists)
            app.staticTexts[URL(fileURLWithPath: config.newImage).lastPathComponent].firstMatch.click()
        } else {
            app.buttons["chooseImages"].click()
            choose(config.duplicate, in: app)
            XCTAssertTrue(app.staticTexts["Exact match"].firstMatch.waitForExistence(timeout: 180))
            XCTAssertTrue(app.popUpButtons["representationPicker"].firstMatch.exists)
            XCTAssertTrue(app.staticTexts["Search complete"].waitForExistence(timeout: 180))
            app.typeKey("i", modifierFlags: .command)
            choose(config.newImage, in: app)
            XCTAssertTrue(app.staticTexts["Search complete"].waitForExistence(timeout: 180))
        }
        XCTAssertTrue(app.staticTexts["comparisonStatus"].waitForExistence(timeout: 10))
        let status = (app.staticTexts["comparisonStatus"].value as? String) ?? app.staticTexts["comparisonStatus"].label
        XCTAssertTrue(status == "No matches found" || status == "Incomplete search · 0 matches so far")
    }

    @MainActor
    private func choose(_ path: String, in app: XCUIApplication, selectAll: Bool = false) {
        XCTAssertTrue(app.windows["open-panel"].buttons["OKButton"].waitForExistence(timeout: 15))
        app.typeKey("g", modifierFlags: [.command, .shift])
        let field = app.textFields["PathTextField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        app.typeKey("a", modifierFlags: .command)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        app.typeKey("v", modifierFlags: .command)
        let pathEntered = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", path), object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [pathEntered], timeout: 5), .completed)
        app.typeKey(.return, modifierFlags: [])
        let navigated = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [navigated], timeout: 5), .completed)
        let open = app.windows["open-panel"].buttons["OKButton"]
        if selectAll {
            app.typeKey("a", modifierFlags: .command)
        }
        open.click()
    }
}

private struct AcceptanceConfig: Decodable {
    let root: String
    let duplicate: String
    let newImage: String
    let batchFolder: String?
    let expectedDuplicateGroups: Int?
    let expectedAssets: Int?
    let expectedSkipped: Int?
}
