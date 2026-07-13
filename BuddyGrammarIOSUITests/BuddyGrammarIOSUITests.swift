import XCTest

final class BuddyGrammarIOSUITests: XCTestCase {
    @MainActor
    private func launchApp() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments.append("--uitesting")
        app.launch()
        return app
    }

    @MainActor
    func testUITestingLaunchShowsHomeWithAnAccessibleKeyboardLabAction() {
        let app = launchApp()
        XCTAssertTrue(
            app.windows.firstMatch.waitForExistence(timeout: 8),
            "BuddyGrammar should present its main window after launch."
        )

        let home = app.descendants(matching: .any)["home.screen"]
        XCTAssertTrue(home.waitForExistence(timeout: 8))

        let openKeyboardLab = app.buttons["home.openKeyboardLab"]
        XCTAssertTrue(
            openKeyboardLab.waitForExistence(timeout: 8),
            "The keyboard lab action should be exposed as an accessible button."
        )
        XCTAssertFalse(
            openKeyboardLab.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            "The keyboard lab action should have an accessibility label."
        )
    }

    @MainActor
    func testKeyboardLabAcceptsTextForExtensionTesting() {
        let app = launchApp()
        let openKeyboardLab = app.buttons["home.openKeyboardLab"]
        XCTAssertTrue(openKeyboardLab.waitForExistence(timeout: 8))
        openKeyboardLab.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["keyboardLab.screen"].waitForExistence(timeout: 5)
        )

        let input = app.descendants(matching: .any)["keyboardLab.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertTrue(input.isEnabled)

        input.tap()
        input.typeText("this sentence need correction")
        XCTAssertTrue(String(describing: input.value).contains("this sentence need correction"))
    }

    @MainActor
    func testPrivacyPolicyIsAccessibleFromSettings() {
        let app = launchApp()
        app.tabBars.buttons["Settings"].tap()

        let privacyPolicy = app.descendants(matching: .any)["settings.privacyPolicy"]
        for _ in 0..<4 where !privacyPolicy.exists {
            app.swipeUp()
        }
        XCTAssertTrue(privacyPolicy.waitForExistence(timeout: 5))
        privacyPolicy.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["privacyPolicy.screen"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts["What stays on your device"].exists)
    }

    @MainActor
    func testLiveKeyboardStarCorrectionWhenEnabled() throws {
        #if !KEYBOARD_E2E
        throw XCTSkip(
            "Run with the KEYBOARD_E2E compilation condition after enabling the signed keyboard and Full Access."
        )
        #endif

        let app = launchApp()
        let openKeyboardLab = app.buttons["home.openKeyboardLab"]
        XCTAssertTrue(openKeyboardLab.waitForExistence(timeout: 8))
        openKeyboardLab.tap()

        let input = app.descendants(matching: .any)["keyboardLab.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeKey(.downArrow, modifierFlags: .command)

        let globeCoordinate = app.coordinate(
            withNormalizedOffset: CGVector(dx: 0.12, dy: 0.94)
        )
        globeCoordinate.press(forDuration: 1.5)

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let appChoice = app.staticTexts["BuddyGrammar"].firstMatch
        let springboardChoice = springboard.staticTexts["BuddyGrammar"].firstMatch

        if appChoice.waitForExistence(timeout: 3) {
            appChoice.tap()
        } else {
            XCTAssertTrue(
                springboardChoice.waitForExistence(timeout: 3),
                "The keyboard input-mode list should include BuddyGrammar."
            )
            springboardChoice.tap()
        }

        let star = app.buttons["keyboard.star"]
        XCTAssertTrue(
            star.waitForExistence(timeout: 8),
            "The real BuddyGrammar keyboard extension should become active."
        )
        attachScreenshot(named: "BuddyGrammar keyboard active", app: app)

        let original = String(describing: input.value)
        star.tap()

        let status = app.descendants(matching: .any)["keyboard.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 3))
        attachScreenshot(named: "BuddyGrammar star correction started", app: app)

        let corrected = NSPredicate { _, _ in
            let value = String(describing: input.value)
            return value != original
        }
        let correctionExpectation = XCTNSPredicateExpectation(
            predicate: corrected,
            object: nil
        )
        let correctionResult = XCTWaiter().wait(
            for: [correctionExpectation],
            timeout: 35
        )

        attachScreenshot(named: "BuddyGrammar star correction finished", app: app)
        XCTAssertEqual(
            correctionResult,
            .completed,
            "Correction did not finish. Keyboard status: \(String(describing: status.label))"
        )

        let value = String(describing: input.value)
        XCTAssertEqual(value.first?.isUppercase, true)

        attachScreenshot(named: "BuddyGrammar star correction", app: app)
    }

    @MainActor
    private func attachScreenshot(named name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
