import BuddyGrammarKit
import XCTest

final class SinglePointerInteractionOwnerTests: XCTestCase {
    func testInterleavedSecondGestureCannotStealOrReleaseOwnership() {
        var owner = SinglePointerInteractionOwner<String>()

        XCTAssertTrue(owner.acquire("first"))
        XCTAssertFalse(owner.acquire("second"))
        XCTAssertTrue(owner.owns("first"))
        XCTAssertFalse(owner.owns("second"))
        XCTAssertFalse(owner.release("second"))
        XCTAssertTrue(owner.owns("first"))
        XCTAssertTrue(owner.release("first"))

        XCTAssertTrue(owner.acquire("second"))
        XCTAssertTrue(owner.owns("second"))
    }

    func testDuplicatePressIsRejectedAndLifecycleResetClearsTheOwner() {
        var owner = SinglePointerInteractionOwner<Int>()

        XCTAssertTrue(owner.acquire(41))
        XCTAssertFalse(owner.acquire(41))

        owner.reset()

        XCTAssertNil(owner.activeToken)
        XCTAssertTrue(owner.acquire(42))
    }
}
