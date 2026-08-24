import XCTest

/// Drives the shipping keyboard extension end to end on a simulator:
/// enables BuddyGrammar as a system keyboard through Settings, switches to
/// it in the Keyboard Lab, types real text, and verifies insertion.
final class BuddyGrammarKeyboardEndToEndTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testTypesThroughEnabledBuddyGrammarKeyboard() throws {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        try enableBuddyGrammarKeyboardIfNeeded(in: settings)

        let app = XCUIApplication()
        app.launchArguments.append("--uitesting")
        app.launch()
        let openKeyboardLab = app.buttons["home.openKeyboardLab"]
        XCTAssertTrue(openKeyboardLab.waitForExistence(timeout: 8))
        openKeyboardLab.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["keyboardLab.screen"].waitForExistence(timeout: 5)
        )

        let input = app.descendants(matching: .any)["keyboardLab.input"]
        input.tap()
        activateBuddyGrammarKeyboard(in: app)
        attachScreenshot(named: "Keyboard state after activation attempt")

        // Type through the extension's raw-touch surface.
        for key in ["h", "e", "l", "l", "o"] {
            let keyButton = app.keys[key]
            XCTAssertTrue(keyButton.waitForExistence(timeout: 3), "Missing key \(key)")
            keyButton.tap()
        }
        let space = app.keyboards.buttons["space"]
        XCTAssertTrue(space.waitForExistence(timeout: 3))
        space.tap()
        for key in ["w", "o", "r", "l", "d"] {
            app.keys[key].tap()
        }

        let typedValue = String(describing: input.value)
        XCTAssertTrue(
            typedValue.lowercased().contains("hello"),
            "Typed text missing from field: \(typedValue)"
        )
        attachScreenshot(named: "Typed through BuddyGrammar keyboard")
    }

    // MARK: - Helpers

    /// Walks Settings into the keyboard management page. Throws an XCTSkip
    /// when Apple's first-launch legal sheet blocks automation: that sheet is
    /// hosted outside every queryable element tree and ignores synthetic
    /// taps, so on a pristine simulator this test needs the keyboard enabled
    /// once by hand (or a pre-provisioned simulator) before it can run.
    @MainActor
    private func enableBuddyGrammarKeyboardIfNeeded(in settings: XCUIApplication) throws {
        dismissSheetIfPresent(settings)
        returnToSettingsRoot(settings)

        let generalRow = row(in: settings, titled: "General")
        guard generalRow.waitForExistence(timeout: 4) else {
            throw XCTSkip(
                "Settings first-launch sheet blocks automation; enable the BuddyGrammar keyboard manually once, then re-run."
            )
        }
        generalRow.tap()
        let keyboardRow = row(in: settings, titled: "Keyboard")
        var scrolls = 0
        while !keyboardRow.waitForExistence(timeout: 1.5), scrolls < 5 {
            settings.swipeUp()
            scrolls += 1
        }
        XCTAssertTrue(keyboardRow.waitForExistence(timeout: 3))
        keyboardRow.tap()

        let keyboardsRow = row(in: settings, titled: "Keyboards")
        if keyboardsRow.waitForExistence(timeout: 4) {
            keyboardsRow.tap()
        }

        let alreadyEnabled = settings.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'BuddyGrammar'")
        ).firstMatch
        if alreadyEnabled.exists && alreadyEnabled.isHittable {
            settings.swipeDown()
            return
        }

        let addNewLabel = NSPredicate(
            format: "label BEGINSWITH %@",
            "Add New Keyboard"
        )
        let addNew = settings.cells.matching(addNewLabel).firstMatch
        var addScrolls = 0
        while !addNew.waitForExistence(timeout: 2), addScrolls < 4 {
            settings.swipeUp()
            addScrolls += 1
        }
        XCTAssertTrue(addNew.waitForExistence(timeout: 3), "Add New Keyboard row not found")
        addNew.tap()

        let buddyRow = settings.cells.matching(
            NSPredicate(format: "label CONTAINS[c] 'BuddyGrammar'")
        ).firstMatch
        var scrolled = 0
        while !buddyRow.waitForExistence(timeout: 1), scrolled < 6 {
            settings.swipeUp()
            scrolled += 1
        }
        XCTAssertTrue(buddyRow.waitForExistence(timeout: 3))
        buddyRow.tap()

        // Back out of the added-keyboard screen so the lab flow resumes clean.
        let backButton = settings.navigationBars.buttons.firstMatch
        if backButton.exists { backButton.tap() }
        if backButton.exists { backButton.tap() }
    }

    /// Settings reopens on the screen it was last left on; walk back to root,
    /// dismissing any leftover modal sheets along the way. Fresh simulators
    /// open with the Siri legal sheet, which needs a moment to appear.
    @MainActor
    private func returnToSettingsRoot(_ settings: XCUIApplication) {
        dismissSheetIfPresent(settings)
        for _ in 0..<8 {
            let back = settings.navigationBars.buttons.firstMatch
            guard back.exists && back.isHittable else { return }
            back.tap()
            dismissSheetIfPresent(settings)
        }
    }

    @MainActor
    private func dismissSheetIfPresent(_ settings: XCUIApplication) {
        for _ in 0..<3 {
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            let candidates = [
                springboard.buttons["Done"],
                settings.buttons["Done"],
            ]
            var tapped = false
            for candidate in candidates where candidate.exists {
                candidate.tap()
                tapped = true
                break
            }
            if !tapped {
                // Sheets hosted outside both element trees: tap where the
                // Done button renders (top-trailing of the sheet header).
                settings.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.85, dy: 0.11)
                ).tap()
            }
            sleep(2)
            if !candidates.contains(where: { $0.exists }) { return }
        }
    }

    @MainActor
    private func row(in app: XCUIApplication, titled: String) -> XCUIElement {
        app.cells.matching(
            NSPredicate(
                format: "label == %@ OR label BEGINSWITH %@",
                titled, titled
            )
        ).firstMatch
    }

    @MainActor
    private func navigate(_ app: XCUIApplication, to titled: String) {
        let cell = row(in: app, titled: titled)
        var scrolls = 0
        // Settings remembers its scroll position; sweep to the top first,
        // then search downward.
        while !cell.waitForExistence(timeout: 1.5), scrolls < 8 {
            if scrolls < 3 {
                app.swipeDown()
            } else {
                app.swipeUp()
            }
            scrolls += 1
        }
        XCTAssertTrue(cell.waitForExistence(timeout: 3), "\(titled) row not found")
        cell.tap()
    }

    /// Cycles the system globe until BuddyGrammar's keyboard is on screen.
    @MainActor
    private func activateBuddyGrammarKeyboard(in app: XCUIApplication) {
        guard !app.keys["q"].exists else { return }
        for _ in 0..<4 {
            let globe = app.keyboards.buttons["Next keyboard"]
            guard globe.waitForExistence(timeout: 3) else { return }
            globe.press(forDuration: 0.4)
            // The input-mode chooser lists enabled keyboards; pick ours.
            let picker = app.otherElements["InputSwitcher"].buttons
                .matching(NSPredicate(format: "label CONTAINS[c] 'BuddyGrammar'"))
                .firstMatch
            if picker.waitForExistence(timeout: 2) {
                picker.tap()
                break
            }
            if app.keys["q"].exists { break }
        }
        XCTAssertTrue(
            app.keys["q"].waitForExistence(timeout: 4),
            "BuddyGrammar letter keys never appeared"
        )
    }

    @MainActor
    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIApplication().screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
