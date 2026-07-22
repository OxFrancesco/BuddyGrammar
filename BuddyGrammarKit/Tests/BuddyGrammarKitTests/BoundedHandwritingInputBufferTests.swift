import CoreGraphics
import XCTest
@testable import BuddyGrammarKit

final class BoundedHandwritingInputBufferTests: XCTestCase {
    func testPathologicalStrokeStaysBoundedAndPreservesEndpoints() {
        var buffer = BoundedHandwritingInputBuffer(
            maximumPointsPerStroke: 8,
            maximumStrokeCount: 4,
            maximumTotalPointCount: 24
        )
        buffer.start(at: point(0))
        for index in 1...10_000 { buffer.append(point(index)) }

        XCTAssertEqual(buffer.activeStroke.count, 8)
        XCTAssertEqual(buffer.activeStroke.first, point(0))
        XCTAssertEqual(buffer.activeStroke.last, point(10_000))
        XCTAssertEqual(buffer.totalPointCount, 8)
    }

    func testStrokeAndTotalLimitsEvictOldestInkDeterministically() {
        func capture() -> [[CGPoint]] {
            var buffer = BoundedHandwritingInputBuffer(
                maximumPointsPerStroke: 4,
                maximumStrokeCount: 3,
                maximumTotalPointCount: 8
            )
            for strokeIndex in 0..<8 {
                let base = strokeIndex * 100
                buffer.start(at: point(base))
                for offset in 1...3 { buffer.append(point(base + offset)) }
                buffer.endStroke()
            }
            XCTAssertLessThanOrEqual(buffer.totalPointCount, 8)
            return buffer.finishedStrokes
        }

        let first = capture()
        let second = capture()
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.map { Int($0[0].x) }, [600, 700])
        XCTAssertEqual(first.map { Int($0.last!.x) }, [603, 703])
    }

    private func point(_ value: Int) -> CGPoint {
        CGPoint(x: value, y: value % 17)
    }
}
