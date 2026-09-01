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
        XCTAssertTrue(app.buttons["Add Case"].exists)
        XCTAssertTrue(
            app.staticTexts["Ready to run"].exists
                || app.staticTexts["Needs attention"].exists
        )

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
        app.radioButtons["Cases"].click()
        var expectedInputs = app.textViews.matching(identifier: "Scoring expected text")
        XCTAssertEqual(expectedInputs.count, 0)

        app.radioButtons["Scoring"].click()
        app.radioButtons["Exact text"].click()
        app.radioButtons["Cases"].click()
        XCTAssertTrue(app.staticTexts["Expected response (required)"].waitForExistence(timeout: 2))
        expectedInputs = app.textViews.matching(identifier: "Scoring expected text")
        XCTAssertEqual(expectedInputs.count, 1)

        app.radioButtons["Scoring"].click()
        app.radioButtons["Contains text"].click()
        app.radioButtons["Cases"].click()
        expectedInputs = app.textViews.matching(identifier: "Scoring expected text")
        XCTAssertEqual(expectedInputs.count, 1)

        app.radioButtons["Scoring"].click()
        app.radioButtons["AI rubric"].click()
        app.radioButtons["Cases"].click()
        expectedInputs = app.textViews.matching(identifier: "Scoring expected text")
        XCTAssertEqual(expectedInputs.count, 1)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Refined suite editor"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
