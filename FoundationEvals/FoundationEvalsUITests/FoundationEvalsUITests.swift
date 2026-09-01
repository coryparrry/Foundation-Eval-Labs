import XCTest

final class FoundationEvalsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSuiteEditorShowsPrimaryRunControls() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Suite Editor"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Run"].exists)
        XCTAssertTrue(app.buttons["Add Files"].exists)
        XCTAssertTrue(app.buttons["Add Case"].exists)
        XCTAssertTrue(app.staticTexts["Scoring and repetitions"].exists)
        XCTAssertTrue(app.staticTexts["Model controls"].exists)
        XCTAssertTrue(app.radioButtons["On device"].exists)
        XCTAssertTrue(app.radioButtons["Private Cloud Compute"].exists)
        XCTAssertTrue(app.staticTexts["Context and references"].exists)
        XCTAssertTrue(
            app.staticTexts["Ready to run"].exists
                || app.staticTexts["Needs attention"].exists
        )
        XCTAssertTrue(app.radioButtons["AI rubric"].exists)

        let expectedInputs = app.textViews.matching(identifier: "Scoring expected text")
        app.radioButtons["Collect only"].click()
        XCTAssertEqual(expectedInputs.count, 0)

        app.radioButtons["Exact text"].click()
        XCTAssertTrue(app.staticTexts["Expected response (required)"].waitForExistence(timeout: 2))
        XCTAssertEqual(expectedInputs.count, 1)

        app.radioButtons["Contains text"].click()
        XCTAssertEqual(expectedInputs.count, 1)

        app.radioButtons["AI rubric"].click()
        XCTAssertEqual(expectedInputs.count, 1)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Refined suite editor"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
