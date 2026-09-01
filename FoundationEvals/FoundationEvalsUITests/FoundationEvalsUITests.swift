import XCTest

final class FoundationEvalsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSuiteEditorShowsPrimaryRunControls() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["Evaluation Suite"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Run"].exists)
        XCTAssertTrue(app.buttons["Add Files"].exists)
        XCTAssertTrue(app.buttons["Add Case"].exists)
        XCTAssertTrue(app.staticTexts["How should each response be checked?"].exists)
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
    }
}
