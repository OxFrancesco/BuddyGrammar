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
    func testKeyboardSettingsExposeLocalCorrectionAndUndoDuration() {
        let app = launchApp()
        app.tabBars.buttons["Settings"].tap()

        let automaticModel = app.descendants(matching: .any)[
            "settings.automaticModelUpdates"
        ]
        XCTAssertTrue(automaticModel.waitForExistence(timeout: 5))
        XCTAssertEqual(automaticModel.value as? String, "1")

        let localCorrection = app.descendants(matching: .any)[
            "settings.automaticallyCorrectWords"
        ]
        for _ in 0..<3 where !localCorrection.exists {
            app.swipeUp()
        }

        XCTAssertTrue(localCorrection.waitForExistence(timeout: 5))
        let undoDuration = app.descendants(matching: .any)[
            "settings.correctionUndoDuration"
        ]
        for _ in 0..<3 where !undoDuration.exists {
            app.swipeUp()
        }

        XCTAssertTrue(undoDuration.waitForExistence(timeout: 5))
        attachScreenshot(named: "Keyboard correction settings", app: app)
    }

    @MainActor
    func testUnsupportedKeyboardDictationReadinessIsAbsent() {
        let app = launchApp()

        XCTAssertFalse(app.descendants(matching: .any)["home.quickDictation"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["companion.bar"].exists)

        app.tabBars.buttons["Settings"].tap()

        XCTAssertFalse(app.descendants(matching: .any)["settings.quickDictation"].exists)
        XCTAssertFalse(
            app.descendants(matching: .any)["settings.quickDictationDuration"].exists
        )
        XCTAssertFalse(app.descendants(matching: .any)["companion.enterPip"].exists)
        XCTAssertFalse(app.staticTexts["Picture in picture"].exists)
        attachScreenshot(named: "Supported dictation settings", app: app)
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
        let star = app.buttons["keyboard.star"]
        for _ in 0..<8 where !star.exists {
            globeCoordinate.tap()
            if star.waitForExistence(timeout: 2) {
                break
            }
        }

        XCTAssertTrue(
            star.exists,
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

        let undo = app.buttons["keyboard.undo"]
        XCTAssertTrue(
            undo.waitForExistence(timeout: 2),
            "Undo should appear after the star correction finishes."
        )
        undo.tap()

        let restored = NSPredicate { _, _ in
            String(describing: input.value) == original
        }
        XCTAssertEqual(
            XCTWaiter().wait(
                for: [XCTNSPredicateExpectation(predicate: restored, object: nil)],
                timeout: 3
            ),
            .completed,
            "Undo should restore the exact pre-correction text."
        )

        attachScreenshot(named: "BuddyGrammar star correction", app: app)
    }

    @MainActor
    func testLiveKeyboardDoesNotDuplicateSystemDictationWhenEnabled() throws {
        #if !KEYBOARD_E2E
        throw XCTSkip(
            "Run with the KEYBOARD_E2E compilation condition after enabling the signed keyboard, Full Access, and device UI Automation."
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
        var buddyControl = app.buttons["keyboard.star"]
        for _ in 0..<8 where !buddyControl.exists {
            globeCoordinate.tap()
            if buddyControl.waitForExistence(timeout: 2) {
                break
            }
        }

        XCTAssertTrue(
            buddyControl.exists,
            "The real BuddyGrammar keyboard extension should become active."
        )
        XCTAssertFalse(app.buttons["keyboard.mic"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["dictation.keyboardInstructions"].exists)
        attachScreenshot(named: "Keyboard uses system Dictation", app: app)
    }

    @MainActor
    private func attachScreenshot(named name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
