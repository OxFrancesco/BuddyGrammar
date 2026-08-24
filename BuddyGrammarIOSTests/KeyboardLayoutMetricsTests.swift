import CoreGraphics
import XCTest

final class KeyboardLayoutMetricsTests: XCTestCase {
    func testKeyboardFitsInsideIPhone15Container() {
        let containerSize = CGSize(width: 393, height: 302)
        let metrics = KeyboardMetrics(size: containerSize)

        XCTAssertLessThanOrEqual(
            2 * metrics.outerPadding + metrics.width,
            containerSize.width,
            "The keyboard must stay inside the extension container."
        )
        XCTAssertEqual(metrics.outerPadding, 4)
        XCTAssertEqual(metrics.width, 385)
    }

    func testKeyboardRemainsCenteredAtItsMaximumIPadWidth() {
        let containerSize = CGSize(width: 834, height: 320)
        let metrics = KeyboardMetrics(size: containerSize)

        XCTAssertEqual(metrics.width, 720)
        XCTAssertEqual(metrics.outerPadding, 57)
        XCTAssertEqual(2 * metrics.outerPadding + metrics.width, containerSize.width)
    }
}
