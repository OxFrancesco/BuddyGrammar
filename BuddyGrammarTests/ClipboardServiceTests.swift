@testable import BuddyGrammar
import XCTest

final class ClipboardServiceTests: XCTestCase {
    func testSnapshotAndRestoreRoundTrip() {
        let pasteboard = MockPasteboardController()
        pasteboard.writeString("Original")
        let service = ClipboardService(pasteboard: pasteboard)

        let snapshot = service.snapshot()
        service.writeString("Changed")
        service.restore(snapshot)

        XCTAssertEqual(service.readString(), "Original")
    }
}
