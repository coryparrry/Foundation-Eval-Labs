import XCTest

final class FoundationEvalsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSuiteEditorShowsPrimaryRunControls() throws {
        let app = XCUIApplication()
        let storage = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: storage) }
        app.launchArguments += [
            "--disable-mcp-autostart",
            "--evaluation-storage", storage.path
        ]
        app.launch()
        defer { app.terminate() }

        // XCTest launches with LSLaunchDoNotBringFrontmost and can create only the menu bar.
        // Exercise the user-facing editor command; normal launch is checked separately in the app.
        app.activate()
        app.menuBars.menuBarItems["Evaluation"].click()
        app.menuItems["Show Suite Editor"].click()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5), "The editor command must present the main window")
        XCTAssertTrue(app.buttons["Run"].waitForExistence(timeout: 5))

        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(app.windows.firstMatch.waitForNonExistence(timeout: 2))
        app.menuBars.menuBarItems["Evaluation"].click()
        app.menuItems["Show Suite Editor"].click()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5), "The editor command must recover a closed main window")
        XCTAssertTrue(app.buttons["Run"].waitForExistence(timeout: 5))
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
        XCTAssertFalse(app.textFields["Port"].exists)
        XCTAssertFalse(app.buttons["Start Server"].exists)
        app.typeKey("w", modifierFlags: .command)

        app.radioButtons["Instructions"].click()
        XCTAssertTrue(app.buttons["Add Files"].exists)

        app.radioButtons["Model"].click()
        XCTAssertTrue(app.popUpButtons["Model provider"].exists)
        XCTAssertTrue(app.popUpButtons["Sampling"].exists)
        XCTAssertFalse(app.popUpButtons["System model use case"].exists)
        app.disclosureTriangles["Advanced model options"].click()
        XCTAssertTrue(app.popUpButtons["System model use case"].exists)
        XCTAssertTrue(app.popUpButtons["System model guardrails"].exists)

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

    @MainActor
    func testCaseSelectionIsSharedBetweenCasesAndScoring() throws {
        let app = XCUIApplication()
        let storage = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: storage) }
        app.launchArguments += ["--disable-mcp-autostart", "--evaluation-storage", storage.path]
        app.launch()
        defer { app.terminate() }
        app.activate()
        app.menuBars.menuBarItems["Evaluation"].click()
        app.menuItems["Show Suite Editor"].click()
        XCTAssertTrue(app.buttons["Add Case"].waitForExistence(timeout: 5))

        app.buttons["Add Case"].click()
        let caseName = app.textFields["Case name"]
        XCTAssertTrue(caseName.waitForExistence(timeout: 2))
        caseName.click()
        app.typeKey("a", modifierFlags: .command)
        caseName.typeText("Selection regression case")

        app.radioButtons["Scoring"].click()
        let scoringCase = app.popUpButtons["Scoring case selector"]
        XCTAssertTrue(scoringCase.waitForExistence(timeout: 2))
        XCTAssertEqual(scoringCase.value as? String, "Selection regression case")

        // Selecting a different scoring target must also change the prompt editor's case.
        scoringCase.click()
        app.menuItems["Example"].click()
        app.radioButtons["Cases"].click()
        XCTAssertTrue(caseName.waitForExistence(timeout: 2))
        XCTAssertEqual(caseName.value as? String, "Example")

        // Returning to Scoring must preserve that explicit choice as well.
        app.radioButtons["Scoring"].click()
        XCTAssertTrue(scoringCase.waitForExistence(timeout: 2))
        XCTAssertEqual(scoringCase.value as? String, "Example")
    }

}
