import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest

// MARK: - rupickUITests

final class rupickUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testWelcomeScreenAndOpenProjectAction() {
        for appearance in ["light", "dark"] {
            let app = XCUIApplication()
            app.launchEnvironment["RUPICK_STRESS_APPEARANCE"] = appearance
            app.launchArguments = ["-AppleInterfaceStyle", appearance.capitalized]
            app.launch()
            let button = app.buttons["openProject"]
            XCTAssertTrue(button.waitForExistence(timeout: 10))
            XCTAssertTrue(button.isHittable)
            XCTAssertTrue(app.staticTexts["Find matching images"].exists)
            XCTAssertFalse(app.staticTexts["projectHeading"].exists)
            XCTAssertFalse(app.descendants(matching: .any)["searchFooter"].exists)
            XCTAssertFalse(app.buttons["chooseImages"].exists)
            let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            screenshot.name = "Welcome \(appearance)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            button.click()
            let cancel = app.windows["open-panel"].buttons["CancelButton"]
            XCTAssertTrue(cancel.waitForExistence(timeout: 5))
            cancel.click()
            XCTAssertTrue(button.isHittable)
            app.typeKey("o", modifierFlags: .command)
            XCTAssertTrue(cancel.waitForExistence(timeout: 5))
            cancel.click()
            app.terminate()
        }
    }

    #if DEBUG
        @MainActor
        func testStressFixturesAndPreviewControls() {
            let app = XCUIApplication()
            app.launchEnvironment["RUPICK_STRESS_UI"] = "1"
            app.launchArguments = ["-AppleInterfaceStyle", "Dark"]
            app.launch()
            XCTAssertTrue(app.staticTexts["Search complete"].waitForExistence(timeout: 30))
            let picker = app.popUpButtons["stressDatasetPicker"]
            XCTAssertTrue(picker.exists)
            for name in ["Worst case", "Empty", "One", "1,000 assets", "Demo"] {
                let previousRoot = app.staticTexts["projectHeading"].value as? String ?? ""
                picker.click()
                app.menuItems[name].click()
                let changedRoot = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", previousRoot),
                                                            object: app.staticTexts["projectHeading"])
                XCTAssertEqual(XCTWaiter.wait(for: [changedRoot], timeout: 30), .completed)
                if name == "Empty" || name == "One" {
                    XCTAssertTrue(app.staticTexts["No exact duplicates found"].waitForExistence(timeout: 30))
                } else {
                    XCTAssertTrue(app.staticTexts["Exact duplicate content"].waitForExistence(timeout: 30))
                    if name == "Worst case" {
                        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Incomplete scan: 3")).firstMatch.waitForExistence(timeout: 30))
                        XCTAssertTrue(app.descendants(matching: .any)["Actual Size"].firstMatch.exists)
                        app.descendants(matching: .any)["Actual Size"].firstMatch.click()
                        XCTAssertTrue(app.sliders["Preview zoom"].firstMatch.waitForExistence(timeout: 5))
                    }
                }
                XCTAssertTrue(app.staticTexts["Search complete"].waitForExistence(timeout: name == "1,000 assets" ? 120 : 30))
                if name == "Worst case" {
                    exerciseReview(in: app, duplicateName: "PaymentConfirmationIllustration-Dark-HighContrast-Final.png",
                                   otherName: "王秀英-نور-الهدى-👩🏽‍💻.png")
                    app.descendants(matching: .any).matching(identifier: "duplicateGroup").firstMatch.click()
                }
                if name == "1,000 assets" {
                    app.buttons["Choose asset"].firstMatch.click()
                    let search = app.searchFields.firstMatch
                    XCTAssertTrue(search.waitForExistence(timeout: 5))
                    search.click()
                    search.typeText("Image999")
                    let row = app.sheets.firstMatch.staticTexts["Image999"].firstMatch
                    XCTAssertTrue(row.waitForExistence(timeout: 5))
                    row.click()
                    app.sheets.firstMatch.buttons["Choose"].click()
                    let selectedAsset = XCTNSPredicateExpectation(
                        predicate: NSPredicate(format: "value == %@", "Image999"),
                        object: app.buttons["Choose asset"].firstMatch
                    )
                    XCTAssertEqual(XCTWaiter.wait(for: [selectedAsset], timeout: 5), .completed)
                }
            }
            let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }

    #endif

    #if DEBUG
        @MainActor
        func testReviewLayoutAtMinimumWindowSize() {
            let app = XCUIApplication()
            app.launchEnvironment["RUPICK_STRESS_UI"] = "1"
            app.launchEnvironment["RUPICK_STRESS_APPEARANCE"] = "light"
            app.launch()
            XCTAssertTrue(app.staticTexts["Search complete"].waitForExistence(timeout: 30))
            let window = app.windows.firstMatch
            let corner = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1)).withOffset(CGVector(dx: -2, dy: -2))
            let target = window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 950, dy: 620))
            corner.press(forDuration: 0.2, thenDragTo: target)
            XCTAssertLessThanOrEqual(window.frame.width, 960)
            XCTAssertLessThanOrEqual(window.frame.height, 680)
            app.popUpButtons["stressDatasetPicker"].click()
            app.menuItems["Worst case"].click()
            let row = app.descendants(matching: .any).matching(identifier: "incoming-PaymentConfirmationIllustration-Dark-HighContrast-Final.png").firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 30))
            XCTAssertTrue(app.staticTexts["Search complete"].waitForExistence(timeout: 30))
            row.click()
            app.buttons["keepAsNew"].click()
            let outcome = app.staticTexts["reviewOutcome"]
            XCTAssertTrue((outcome.value as? String ?? outcome.label).contains("Keep as new"))
            XCTAssertTrue(app.buttons["keepAsNew"].isHittable)
            XCTAssertGreaterThanOrEqual(app.buttons["keepAsNew"].frame.minX, window.frame.minX)
            XCTAssertLessThanOrEqual(app.buttons["keepAsNew"].frame.maxX, window.frame.maxX)
            let screenshot = XCTAttachment(screenshot: window.screenshot())
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    #endif

    @MainActor
    func testScrollContentStaysBetweenToolbarAndSearchFooter() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("rupick-scroll-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try copyFixture(to: root)
        for index in 0 ..< 12 {
            let entry = root.appendingPathComponent("App/Primary.xcassets/Copy\(index).imageset")
            try FileManager.default.copyItem(at: root.appendingPathComponent("App/Primary.xcassets/Icon.imageset"), to: entry)
        }
        let app = XCUIApplication()
        app.launch()
        app.buttons["openProject"].click()
        choose(root.path, in: app)
        XCTAssertTrue(app.staticTexts["Search complete"].waitForExistence(timeout: 30))
        let scroll = app.scrollViews["duplicateScrollView"]
        scroll.scroll(byDeltaX: 0, deltaY: -10000)
        let finalMember = try XCTUnwrap(app.staticTexts.matching(identifier: "Packages/Other.xcassets/Icon.imageset").allElementsBoundByIndex.last)
        assertScrollBounds(scroll, heading: app.staticTexts["Exact duplicate content"],
                           lastContent: finalMember, in: app)

        app.buttons["chooseImages"].click()
        choose(root.appendingPathComponent("Incoming/renamed.png").path, in: app)
        selectIncoming("renamed.png", in: app)
        XCTAssertTrue(app.staticTexts["Exact match"].firstMatch.waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["Search complete"].waitForExistence(timeout: 30))
        let comparison = app.scrollViews["comparisonScrollView"]
        comparison.scroll(byDeltaX: 0, deltaY: -10000)
        let finalPreview = try XCTUnwrap(app.staticTexts.matching(identifier: "light.png").allElementsBoundByIndex.last)
        assertScrollBounds(comparison, heading: app.staticTexts["comparisonHeading"],
                           lastContent: finalPreview, in: app)
    }

    @MainActor
    private func assertScrollBounds(_ scroll: XCUIElement, heading: XCUIElement,
                                    lastContent: XCUIElement, in app: XCUIApplication,
                                    file: StaticString = #filePath, line: UInt = #line)
    {
        let window = app.windows.firstMatch
        let toolbar = app.windows.firstMatch.toolbars.firstMatch
        let footer = app.descendants(matching: .any)["searchFooter"].firstMatch
        XCTAssertTrue(toolbar.exists, file: file, line: line)
        XCTAssertTrue(footer.exists, file: file, line: line)
        XCTAssertTrue(scroll.exists, file: file, line: line)
        // Begin at a known size so growth stays within the available display.
        let initialCorner = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1))
            .withOffset(CGVector(dx: -2, dy: -2))
        let initialTarget = window.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: 950, dy: 680))
        initialCorner.press(forDuration: 0.2, thenDragTo: initialTarget)
        for sizeChange in [CGVector.zero, CGVector(dx: 220, dy: 120), CGVector(dx: -220, dy: -120)] {
            if sizeChange != .zero {
                let previousSize = window.frame.size
                let corner = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1))
                    .withOffset(CGVector(dx: -2, dy: -2))
                corner.press(forDuration: 0.2, thenDragTo: corner.withOffset(sizeChange))
                XCTAssertEqual(window.frame.width, previousSize.width + sizeChange.dx, accuracy: 5, file: file, line: line)
                XCTAssertEqual(window.frame.height, previousSize.height + sizeChange.dy, accuracy: 5, file: file, line: line)
            }
            scroll.scroll(byDeltaX: 0, deltaY: 10000)
            XCTAssertGreaterThanOrEqual(scroll.frame.minY, toolbar.frame.maxY, file: file, line: line)
            for element in [heading, app.staticTexts["projectHeading"]] {
                XCTAssertGreaterThanOrEqual(element.frame.minY, toolbar.frame.maxY,
                                            "Content must be fully below the toolbar.", file: file, line: line)
                XCTAssertLessThanOrEqual(element.frame.minY, toolbar.frame.maxY + 24,
                                         "The toolbar inset must not be counted twice.", file: file, line: line)
                XCTAssertTrue(element.isHittable, file: file, line: line)
            }
            XCTAssertLessThanOrEqual(scroll.frame.maxY, footer.frame.minY + 1, file: file, line: line)
            scroll.scroll(byDeltaX: 0, deltaY: -10000)
            XCTAssertTrue(lastContent.isHittable, file: file, line: line)
            XCTAssertLessThanOrEqual(lastContent.frame.maxY, footer.frame.minY,
                                     "The final content must remain above the footer.", file: file, line: line)
        }
        scroll.scroll(byDeltaX: 0, deltaY: 10000)
        let screenshot = XCTAttachment(screenshot: window.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

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
        app.scrollViews["duplicateScrollView"].scroll(byDeltaX: 0, deltaY: -10000)
        XCTAssertTrue(app.staticTexts["Packages/Other.xcassets/Icon.imageset"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["App/Primary.xcassets/Third.imageset"].exists)
        XCTAssertFalse(app.staticTexts["IgnoredDuplicate"].exists)
        XCTAssertFalse(app.staticTexts["Unique"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Incomplete scan: 1")).firstMatch.exists)
        app.scrollViews["duplicateScrollView"].scroll(byDeltaX: 0, deltaY: 10000)
        XCTAssertEqual(app.popUpButtons.matching(identifier: "duplicateMemberPicker").count, 2)
        let picker = app.popUpButtons["duplicateRepresentationPicker"].firstMatch
        picker.click()
        app.menuItems.matching(NSPredicate(format: "title CONTAINS %@", "Alternative")).firstMatch.click()
        XCTAssertTrue(app.staticTexts["Alternative representation"].waitForExistence(timeout: 5))
        let memberPicker = app.popUpButtons["duplicateMemberPicker"].firstMatch
        memberPicker.click()
        let assetChoices = app.menuItems.matching(NSPredicate(format: "title CONTAINS %@", ".imageset"))
        XCTAssertEqual(assetChoices.count, 3, "Each participating asset must appear exactly once")
        XCTAssertEqual(Set(assetChoices.allElementsBoundByIndex.map(\.title)).count, 3)
        app.menuItems.matching(NSPredicate(format: "title CONTAINS %@", "Third.imageset")).firstMatch.click()
        XCTAssertTrue(app.staticTexts["copy.png"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Comparison Details"].click()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value CONTAINS %@", "safe to delete")).firstMatch.exists)
        app.typeKey(.escape, modifierFlags: [])
        app.staticTexts["2 assets with equal content"].click()
        XCTAssertEqual(app.popUpButtons.matching(identifier: "duplicateMemberPicker").count, 0)
        XCTAssertEqual(app.popUpButtons.matching(identifier: "duplicateRepresentationPicker").count, 2)
        XCTAssertFalse(app.buttons["projectDuplicates"].exists)
        XCTAssertFalse(app.staticTexts["Matching representation"].exists)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "Actual Size").count, 1)
        app.descendants(matching: .any)["Actual Size"].click()
        XCTAssertEqual(app.sliders.matching(identifier: "Preview zoom").count, 1)
        app.buttons["chooseImages"].click()
        choose(root.appendingPathComponent("Incoming/renamed.png").path, in: app)
        selectIncoming("renamed.png", in: app)
        XCTAssertTrue(app.staticTexts["Incoming"].firstMatch.waitForExistence(timeout: 30))
        app.staticTexts["2 assets with equal content"].click()
        XCTAssertTrue(app.staticTexts["Exact duplicate content"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testAddingImagesPreservesInspectionAndReopeningSameProjectStartsFresh() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("rupick-lifecycle-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try copyFixture(to: root)
        let app = XCUIApplication()
        app.launch()
        app.buttons["openProject"].click()
        choose(root.path, in: app)
        XCTAssertTrue(app.staticTexts["Search complete"].waitForExistence(timeout: 30))
        let picker = app.popUpButtons["duplicateRepresentationPicker"].firstMatch
        picker.click()
        app.menuItems.matching(NSPredicate(format: "title CONTAINS %@", "Alternative")).firstMatch.click()
        XCTAssertTrue(app.staticTexts["Alternative representation"].waitForExistence(timeout: 5))
        app.buttons["chooseImages"].click()
        choose(root.appendingPathComponent("Incoming/renamed.png").path, in: app)
        XCTAssertTrue(app.descendants(matching: .any)["incoming-renamed.png"].firstMatch.waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["Search complete"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["Exact duplicate content"].exists)
        XCTAssertTrue(app.staticTexts["Alternative representation"].exists)
        // Removing the inspected alternative during a refresh falls back to the exact match.
        let metadata = root.appendingPathComponent("App/Primary.xcassets/Icon.imageset/Contents.json")
        let originalMetadata = try Data(contentsOf: metadata)
        try Data(#"{"images":[{"filename":"light.png","scale":"1x"}]}"#.utf8).write(to: metadata)
        app.buttons["chooseImages"].click()
        choose(root.appendingPathComponent("Incoming/new.png").path, in: app)
        XCTAssertTrue(app.descendants(matching: .any)["incoming-new.png"].firstMatch.waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["Search complete"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["Exact duplicate content"].exists)
        XCTAssertFalse(app.staticTexts["Alternative representation"].exists)
        // Restoring the alternative must not resurrect the discarded selection.
        try originalMetadata.write(to: metadata)
        app.buttons["chooseImages"].click()
        choose(root.appendingPathComponent("Incoming/hidden-colour.png").path, in: app)
        XCTAssertTrue(app.descendants(matching: .any)["incoming-hidden-colour.png"].firstMatch.waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["Search complete"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.staticTexts["Alternative representation"].exists)
        selectIncoming("renamed.png", in: app)
        XCTAssertTrue(app.staticTexts["Incoming"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["openProject"].click()
        choose(root.path, in: app)
        XCTAssertTrue(app.staticTexts["Search complete"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.descendants(matching: .any)["incoming-renamed.png"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Exact duplicate content"].exists)
        XCTAssertFalse(app.staticTexts["Alternative representation"].exists)
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
    func testNativeProjectScanCancellationRetainsProvisionalGroups() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("rupick-cancel-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
                                                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        try memset(XCTUnwrap(bitmap.bitmapData), 255, bitmap.bytesPerRow * bitmap.pixelsHigh)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        for index in 0 ..< 100 {
            let entry = root.appendingPathComponent("Assets.xcassets/Icon\(index).imageset")
            try FileManager.default.createDirectory(at: entry, withIntermediateDirectories: true)
            try data.write(to: entry.appendingPathComponent("image.png"))
            try Data(#"{"images":[{"filename":"image.png","scale":"1x"}]}"#.utf8).write(to: entry.appendingPathComponent("Contents.json"))
        }
        let app = XCUIApplication()
        app.launch()
        app.buttons["openProject"].click()
        choose(root.path, in: app)
        XCTAssertTrue(app.staticTexts["Exact duplicate content"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["Cancel Search"].exists)
        app.buttons["Cancel Search"].click()
        XCTAssertTrue(app.staticTexts["Search cancelled. Results are incomplete."].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Exact duplicate content"].exists)
        XCTAssertFalse(app.staticTexts["No exact duplicates found"].exists)
        XCTAssertTrue(app.popUpButtons["duplicateRepresentationPicker"].firstMatch.exists)
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
        selectIncoming("renamed.png", in: app)
        XCTAssertTrue(app.staticTexts["Incomplete search · 2 matches so far"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["App/Primary.xcassets/Icon.imageset"].exists)
        app.scrollViews["comparisonScrollView"].scroll(byDeltaX: 0, deltaY: -10000)
        XCTAssertTrue(app.staticTexts["Packages/Other.xcassets/Icon.imageset"].exists)
        app.scrollViews["comparisonScrollView"].scroll(byDeltaX: 0, deltaY: 10000)
        XCTAssertTrue(app.staticTexts["Incoming"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Exact match"].firstMatch.exists)
        let picker = app.popUpButtons["representationPicker"].firstMatch
        XCTAssertTrue(picker.exists)
        picker.click()
        app.menuItems.matching(NSPredicate(format: "title CONTAINS %@", "Alternative")).firstMatch.click()
        XCTAssertTrue(app.staticTexts["Alternative representation"].waitForExistence(timeout: 5))
        app.buttons["Comparison Details"].click()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value CONTAINS %@", "Resized copies")).firstMatch.exists)
        app.typeKey(.escape, modifierFlags: [])
    }

    @MainActor
    func testReviewOutcomesAndRepresentationRetention() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("rupick-review-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try copyFixture(to: root)
        let app = XCUIApplication()
        app.launch()
        app.buttons["openProject"].click()
        choose(root.path, in: app)
        XCTAssertTrue(app.staticTexts["Search complete"].waitForExistence(timeout: 30))
        app.buttons["chooseImages"].click()
        choose(root.appendingPathComponent("Incoming").path, in: app, selectAll: true)
        XCTAssertTrue(app.staticTexts["Search complete"].waitForExistence(timeout: 30))
        exerciseReview(in: app, duplicateName: "renamed.png", otherName: "new.png")
    }

    @MainActor
    private func selectIncoming(_ name: String, in app: XCUIApplication) {
        let row = app.descendants(matching: .any).matching(identifier: "incoming-" + name).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        let sidebar = app.outlines["Sidebar"]
        for _ in 0 ..< 5 {
            if row.frame.minY >= sidebar.frame.minY, row.frame.maxY <= sidebar.frame.maxY {
                break
            }
            sidebar.scroll(byDeltaX: 0, deltaY: row.frame.maxY > sidebar.frame.maxY ? -300 : 300)
        }
        XCTAssertGreaterThanOrEqual(row.frame.minY, sidebar.frame.minY)
        XCTAssertLessThanOrEqual(row.frame.maxY, sidebar.frame.maxY)
        row.click()
        app.scrollViews["comparisonScrollView"].scroll(byDeltaX: 0, deltaY: 10000)
    }

    @MainActor
    private func exerciseReview(in app: XCUIApplication, duplicateName: String, otherName: String) {
        selectIncoming(duplicateName, in: app)
        let pickers = app.popUpButtons.matching(identifier: "representationPicker")
        XCTAssertTrue(pickers.firstMatch.waitForExistence(timeout: 10))
        let picker = pickers.firstMatch
        picker.click()
        let alternative = app.menuItems.matching(NSPredicate(format: "title CONTAINS %@", "Alternative")).firstMatch
        if alternative.exists {
            alternative.click()
            XCTAssertFalse(app.buttons.matching(identifier: "reuseAsset").firstMatch.isEnabled)
            let selected = picker.value as? String
            selectIncoming(otherName, in: app)
            selectIncoming(duplicateName, in: app)
            XCTAssertEqual(pickers.firstMatch.value as? String, selected)
            pickers.firstMatch.click()
        }
        app.menuItems.matching(NSPredicate(format: "title CONTAINS %@", "Exact match")).firstMatch.click()
        let selected = pickers.firstMatch.value as? String
        app.scrollViews["comparisonScrollView"].scroll(byDeltaX: 0, deltaY: -400)
        let reuse = app.buttons.matching(identifier: "reuseAsset").firstMatch
        XCTAssertTrue(reuse.isHittable)
        reuse.click()
        app.scrollViews["comparisonScrollView"].scroll(byDeltaX: 0, deltaY: 10000)
        XCTAssertTrue(app.staticTexts["reviewOutcome"].label.contains("Reuse") || (app.staticTexts["reviewOutcome"].value as? String)?.contains("Reuse") == true)
        selectIncoming(otherName, in: app)
        app.buttons["keepAsNew"].click()
        selectIncoming(duplicateName, in: app)
        XCTAssertEqual(pickers.firstMatch.value as? String, selected)
        XCTAssertTrue(app.staticTexts["reviewOutcome"].label.contains("Reuse") || (app.staticTexts["reviewOutcome"].value as? String)?.contains("Reuse") == true)
        app.buttons["keepAsNew"].click()
        XCTAssertTrue(app.staticTexts["Exact match"].firstMatch.exists)
        XCTAssertTrue(pickers.firstMatch.exists)
        selectIncoming(otherName, in: app)
        selectIncoming(duplicateName, in: app)
        XCTAssertTrue(app.staticTexts["reviewOutcome"].label.contains("Keep as new") || (app.staticTexts["reviewOutcome"].value as? String)?.contains("Keep as new") == true)
        let progress = app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "2 of ")).firstMatch
        XCTAssertTrue((progress.value as? String ?? progress.label).hasPrefix("2 of "))
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
        selectIncoming("new.png", in: app)
        XCTAssertTrue(app.staticTexts["No matches found"].firstMatch.waitForExistence(timeout: 30))
        app.buttons["Comparison Details"].click()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value CONTAINS %@", "does not guarantee")).firstMatch.exists)
        app.typeKey(.escape, modifierFlags: [])
        try FileManager.default.removeItem(at: root)
        app.buttons["chooseImages"].click()
        choose(input.path, in: app)
        selectIncoming(input.lastPathComponent, in: app)
        XCTAssertTrue(app.staticTexts["Search failed"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["Search failed. Open the project folder again to retry."].exists)
        XCTAssertFalse(app.staticTexts["No matches found"].exists)
        XCTAssertFalse(app.staticTexts["No exact duplicates found"].exists)
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
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("fixtures/ExactMatching")
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
        let broken = app.descendants(matching: .any).matching(identifier: "incoming-broken.png").firstMatch
        XCTAssertTrue(broken.waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["Search complete"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["3 / 3 assets compared"].exists)
        XCTAssertTrue(app.staticTexts["Incomplete scan: 1 unreadable or unsupported catalog entries or images were skipped."].exists)
        broken.click()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "Could not read this PNG")).firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["No matches found"].exists)
        XCTAssertFalse(app.staticTexts["comparisonStatus"].exists)
        selectIncoming("renamed.png", in: app)
        XCTAssertTrue(app.staticTexts["Exact match"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Incoming"].firstMatch.exists)
        selectIncoming("new.png", in: app)
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
        XCTAssertTrue(app.staticTexts["Search complete"].waitForExistence(timeout: 600))
        if let expectedGroups = config.expectedDuplicateGroups {
            XCTAssertTrue(app.staticTexts[expectedGroups == 1 ? "1 exact duplicate group" : "\(expectedGroups) exact duplicate groups"].exists)
            if expectedGroups > 0 {
                XCTAssertTrue(app.staticTexts["Exact duplicate content"].exists)
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
            XCTAssertTrue(app.staticTexts["Search complete"].waitForExistence(timeout: 600))
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
            selectIncoming(URL(fileURLWithPath: config.duplicate).lastPathComponent, in: app)
            XCTAssertTrue(app.staticTexts["Exact match"].firstMatch.waitForExistence(timeout: 600))
            XCTAssertTrue(app.popUpButtons["representationPicker"].firstMatch.exists)
            XCTAssertTrue(app.staticTexts["Search complete"].waitForExistence(timeout: 600))
            app.typeKey("i", modifierFlags: .command)
            choose(config.newImage, in: app)
            selectIncoming(URL(fileURLWithPath: config.newImage).lastPathComponent, in: app)
            XCTAssertTrue(app.staticTexts["Search complete"].waitForExistence(timeout: 600))
        }
        app.descendants(matching: .any).matching(identifier: "incoming-" + URL(fileURLWithPath: config.newImage).lastPathComponent).firstMatch.click()
        XCTAssertTrue(app.staticTexts["comparisonStatus"].waitForExistence(timeout: 10))
        let status = (app.staticTexts["comparisonStatus"].value as? String) ?? app.staticTexts["comparisonStatus"].label
        XCTAssertTrue(status == "No matches found" || status == "Incomplete search · 0 matches so far")
        exerciseReview(in: app, duplicateName: URL(fileURLWithPath: config.duplicate).lastPathComponent,
                       otherName: URL(fileURLWithPath: config.newImage).lastPathComponent)
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

// MARK: - AcceptanceConfig

private struct AcceptanceConfig: Decodable {
    let root: String
    let duplicate: String
    let newImage: String
    let batchFolder: String?
    let expectedDuplicateGroups: Int?
    let expectedAssets: Int?
    let expectedSkipped: Int?
}
