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
    func testLiveKeyboardReturnHoldFixesAllTextWhenEnabled() throws {
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

        let returnKey = app.buttons["keyboard.return"]
        XCTAssertTrue(
            activateBuddyKeyboard(in: app, waitingFor: returnKey),
            "The real BuddyGrammar keyboard extension should become active."
        )
        attachScreenshot(named: "BuddyGrammar keyboard active", app: app)

        let original = String(describing: input.value)
        // XCTest reports keyboard-extension element frames in the extension's
        // local coordinate space, which can translate the bottom row below the
        // host app's screen. Use the visible iPhone 15 Return-key position for
        // this physical hold while still requiring the identified key above.
        app.coordinate(
            withNormalizedOffset: CGVector(dx: 0.93, dy: 0.875)
        ).press(forDuration: 0.7)

        let status = app.descendants(matching: .any)["keyboard.status"]
        let undo = app.buttons["keyboard.undo"]
        let correctionStarted = NSPredicate { _, _ in
            status.exists
                || undo.exists
                || String(describing: input.value) != original
        }
        XCTAssertEqual(
            XCTWaiter().wait(
                for: [
                    XCTNSPredicateExpectation(
                        predicate: correctionStarted,
                        object: nil
                    )
                ],
                timeout: 3
            ),
            .completed,
            "Return hold should start or finish a whole-text correction."
        )
        attachScreenshot(named: "BuddyGrammar return hold correction started", app: app)

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

        XCTAssertEqual(
            correctionResult,
            .completed,
            "Return hold did not finish correcting the whole text."
        )

        let value = String(describing: input.value)
        XCTAssertEqual(value.first?.isUppercase, true)

        if undo.exists {
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
        }

        attachScreenshot(named: "BuddyGrammar return hold correction", app: app)
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

        let buddyControl = app.buttons["keyboard.buddy"]
        XCTAssertTrue(
            activateBuddyKeyboard(in: app, waitingFor: buddyControl),
            "The real BuddyGrammar keyboard extension should become active."
        )
        buddyControl.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).press(forDuration: 0.7)

        let status = app.descendants(matching: .any)["keyboard.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 3))
        XCTAssertTrue(
            status.label.localizedCaseInsensitiveContains("system mic"),
            "Buddy hold should point to Apple Dictation without opening a microphone in the extension."
        )
        XCTAssertFalse(
            app.buttons["keyboard.voiceInput"].exists,
            "A Buddy hold should not fall through to the short-tap drawer action."
        )
        XCTAssertFalse(app.buttons["keyboard.mic"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["dictation.keyboardInstructions"].exists)
        attachScreenshot(named: "Buddy hold uses system Dictation", app: app)
    }

    @MainActor
    private func attachScreenshot(named name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func activateBuddyKeyboard(
        in app: XCUIApplication,
        waitingFor buddyControl: XCUIElement
    ) -> Bool {
        let fallbackGlobeCoordinate = app.coordinate(
            withNormalizedOffset: CGVector(dx: 0.12, dy: 0.94)
        )

        for _ in 0..<8 where !buddyControl.exists {
            let nextKeyboard = app.buttons["Next keyboard"]
            if nextKeyboard.waitForExistence(timeout: 0.6) {
                nextKeyboard.tap()
            } else {
                fallbackGlobeCoordinate.tap()
            }
            if buddyControl.waitForExistence(timeout: 2) {
                return true
            }
        }
        return buddyControl.exists
    }
}
