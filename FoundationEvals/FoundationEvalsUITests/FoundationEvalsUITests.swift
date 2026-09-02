import XCTest

final class FoundationEvalsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSuiteEditorShowsPrimaryRunControls() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES", "--disable-mcp-autostart"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Suite Editor"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Run"].exists)
        XCTAssertTrue(app.buttons["Add Case"].exists)
        XCTAssertTrue(app.buttons["Add Case"].isHittable)
        XCTAssertTrue(
            app.staticTexts["Ready to run"].exists
                || app.staticTexts["Needs attention"].exists
        )

        let connector = app.descendants(matching: .any)["Open MCP Connector"]
        XCTAssertTrue(connector.waitForExistence(timeout: 2))
        connector.click()
        XCTAssertTrue(app.buttons["Codex install or update"].waitForExistence(timeout: 2))
        app.typeKey("w", modifierFlags: .command)

        app.radioButtons["Instructions"].click()
        XCTAssertTrue(app.buttons["Add Files"].exists)

        app.radioButtons["Model"].click()
        XCTAssertTrue(app.descendants(matching: .any)["On-device model"].exists)
        XCTAssertFalse(app.radioButtons["Private Cloud Compute"].exists)
        XCTAssertTrue(app.staticTexts["Context and references"].exists)

        app.radioButtons["Scoring"].click()
        XCTAssertTrue(app.staticTexts["Scoring and repetitions"].exists)
        XCTAssertTrue(app.radioButtons["AI rubric"].exists)

        app.radioButtons["Collect only"].click()
        var expectedInputs = app.textViews.matching(identifier: "Scoring expected text")
        XCTAssertEqual(expectedInputs.count, 0)

        app.radioButtons["Exact text"].click()
        XCTAssertTrue(app.staticTexts["Expected response (required)"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Prompt"].exists)
        expectedInputs = app.textViews.matching(identifier: "Scoring expected text")
        XCTAssertEqual(expectedInputs.count, 1)

        app.radioButtons["Contains text"].click()
        expectedInputs = app.textViews.matching(identifier: "Scoring expected text")
        XCTAssertEqual(expectedInputs.count, 1)

        app.radioButtons["AI rubric"].click()
        expectedInputs = app.textViews.matching(identifier: "Scoring expected text")
        XCTAssertEqual(expectedInputs.count, 1)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Refined suite editor"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
