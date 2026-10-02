import XCTest
import AppKit

final class rupickUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testNativePickersAndRepresentationInspection() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("rupick-ui-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("fixtures/ExactMatching")
        try FileManager.default.copyItem(at: fixture, to: root)
        let app = XCUIApplication()
        app.launch()
        app.buttons["openProject"].click()
        choose(root.path, in: app)
        XCTAssertTrue(app.staticTexts["Search complete"].waitForExistence(timeout: 30))
        app.buttons["chooseImages"].click()
        choose(root.appendingPathComponent("Incoming/renamed.png").path, in: app)
        XCTAssertTrue(app.staticTexts["2 exact matches"].waitForExistence(timeout: 30))
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
        app.buttons["chooseImages"].click()
        choose(config.duplicate, in: app)
        XCTAssertTrue(app.staticTexts["Exact match"].firstMatch.waitForExistence(timeout: 180))
        XCTAssertTrue(app.popUpButtons["representationPicker"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Search complete"].waitForExistence(timeout: 180))
        app.typeKey("i", modifierFlags: .command)
        choose(config.newImage, in: app)
        XCTAssertTrue(app.staticTexts["Search complete"].waitForExistence(timeout: 180))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "No matches")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["0 exact matches"].exists)
    }

    @MainActor
    private func choose(_ path: String, in app: XCUIApplication) {
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
        open.click()
    }
}

private struct AcceptanceConfig: Decodable {
    let root: String
    let duplicate: String
    let newImage: String
}
