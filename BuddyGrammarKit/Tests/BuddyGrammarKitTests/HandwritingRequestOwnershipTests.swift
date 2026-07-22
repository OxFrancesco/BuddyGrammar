import XCTest
@testable import BuddyGrammarKit

final class HandwritingRequestOwnershipTests: XCTestCase {
    func testStrokeMutationAndFieldChangeInvalidateOldWork() {
        var ownership = HandwritingRequestOwnership(fieldEpoch: 4)
        let first = ownership.beginRequest()
        XCTAssertTrue(ownership.owns(first))

        ownership.inputChanged()
        XCTAssertFalse(ownership.owns(first))
        let second = ownership.beginRequest()
        XCTAssertTrue(ownership.owns(second))

        ownership.changeField(to: 5)
        XCTAssertFalse(ownership.owns(second))
        let third = ownership.beginRequest()
        XCTAssertEqual(third.fieldEpoch, 5)
        XCTAssertTrue(ownership.finish(third))
        XCTAssertFalse(ownership.owns(third))
    }
}
