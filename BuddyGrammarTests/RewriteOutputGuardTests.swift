@testable import BuddyGrammar
import XCTest

final class RewriteOutputGuardTests: XCTestCase {
    func testSanitizeTrimsSafeOutput() throws {
        XCTAssertEqual(try RewriteOutputGuard.sanitize("  This is better. \n"), "This is better.")
    }

    func testSanitizeRejectsExplainerPrefix() {
        XCTAssertThrowsError(try RewriteOutputGuard.sanitize("Here is the corrected text: This is better.")) { error in
            XCTAssertEqual(error as? RewriteFailure, .invalidOutput)
        }
    }

    func testSanitizeRejectsEmptyOutput() {
        XCTAssertThrowsError(try RewriteOutputGuard.sanitize(" \n ")) { error in
            XCTAssertEqual(error as? RewriteFailure, .invalidOutput)
        }
    }
}
