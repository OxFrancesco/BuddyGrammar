import CoreGraphics
import XCTest
@testable import BuddyGrammarKit

final class HandwritingStrokeNormalizerTests: XCTestCase {
    func testSmallOffCenterWritingIsScaledAndCentered() throws {
        let layout = try XCTUnwrap(
            HandwritingStrokeNormalizer.normalized(
                strokes: [[
                    CGPoint(x: 4, y: 6),
                    CGPoint(x: 9, y: 14),
                    CGPoint(x: 15, y: 8),
                ]],
                targetSize: CGSize(width: 320, height: 160),
                padding: 20
            )
        )

        let points = layout.strokes.flatMap { $0 }
        let bounds = try XCTUnwrap(CGRect.bounding(points: points))

        XCTAssertEqual(bounds.midX, 160, accuracy: 0.5)
        XCTAssertEqual(bounds.midY, 80, accuracy: 0.5)
        XCTAssertGreaterThan(bounds.height, 100)
        XCTAssertGreaterThan(layout.lineWidth, 3)
    }

    func testSinglePointStrokeSurvivesNormalizationAsVisibleDot() throws {
        let layout = try XCTUnwrap(
            HandwritingStrokeNormalizer.normalized(
                strokes: [[CGPoint(x: 12, y: 30)]],
                targetSize: CGSize(width: 320, height: 160),
                padding: 20
            )
        )

        XCTAssertEqual(layout.strokes.count, 1)
        XCTAssertEqual(layout.strokes[0].count, 1)
        XCTAssertGreaterThanOrEqual(layout.dotDiameter, layout.lineWidth)
        XCTAssertGreaterThan(layout.dotDiameter, 0)
    }
}

private extension CGRect {
    static func bounding(points: [CGPoint]) -> CGRect? {
        guard let first = points.first else { return nil }
        return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { bounds, point in
            bounds.union(CGRect(origin: point, size: .zero))
        }
    }
}
