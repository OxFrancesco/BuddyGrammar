import XCTest
@testable import BuddyGrammarKit

final class CorrectionOutputGuardTests: XCTestCase {
    func testTrimsValidOutput() throws {
        XCTAssertEqual(
            try CorrectionOutputGuard.sanitize("  This is correct.\n", relativeTo: "this are correct"),
            "This is correct."
        )
    }

    func testRejectsExplanatoryPrefix() {
        XCTAssertThrowsError(
            try CorrectionOutputGuard.sanitize(
                "Here is the corrected text: This is correct.",
                relativeTo: "this are correct"
            )
        )
    }

    func testRejectsUnreasonablyLargeOutput() {
        XCTAssertThrowsError(
            try CorrectionOutputGuard.sanitize(
                String(repeating: "x", count: 501),
                relativeTo: "tiny"
            )
        )
    }
}
