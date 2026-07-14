import CoreGraphics
import Foundation

public struct HandwritingStrokeLayout: Equatable, Sendable {
    public let strokes: [[CGPoint]]
    public let lineWidth: CGFloat
    public let dotDiameter: CGFloat

    public init(strokes: [[CGPoint]], lineWidth: CGFloat, dotDiameter: CGFloat) {
        self.strokes = strokes
        self.lineWidth = lineWidth
        self.dotDiameter = dotDiameter
    }
}

public enum HandwritingStrokeNormalizer {
    public static func normalized(
        strokes: [[CGPoint]],
        targetSize: CGSize,
        padding: CGFloat
    ) -> HandwritingStrokeLayout? {
        let strokes = strokes.filter { !$0.isEmpty }
        let points = strokes.flatMap { $0 }
        guard let first = points.first,
              targetSize.width > 0,
              targetSize.height > 0 else {
            return nil
        }

        let sourceBounds = points.dropFirst().reduce(
            CGRect(origin: first, size: .zero)
        ) { bounds, point in
            bounds.union(CGRect(origin: point, size: .zero))
        }
        let safePadding = max(0, min(padding, min(targetSize.width, targetSize.height) / 3))
        let targetBounds = CGRect(origin: .zero, size: targetSize).insetBy(
            dx: safePadding,
            dy: safePadding
        )
        guard targetBounds.width > 0, targetBounds.height > 0 else { return nil }

        let sourceWidth = max(sourceBounds.width, 1)
        let sourceHeight = max(sourceBounds.height, 1)
        let scale = min(targetBounds.width / sourceWidth, targetBounds.height / sourceHeight)
        let sourceCenter = CGPoint(x: sourceBounds.midX, y: sourceBounds.midY)
        let targetCenter = CGPoint(x: targetBounds.midX, y: targetBounds.midY)

        let transformed = strokes.map { stroke in
            stroke.map { point in
                CGPoint(
                    x: targetCenter.x + (point.x - sourceCenter.x) * scale,
                    y: targetCenter.y + (point.y - sourceCenter.y) * scale
                )
            }
        }
        let lineWidth = max(5, min(9, targetSize.height / 28))

        return HandwritingStrokeLayout(
            strokes: transformed,
            lineWidth: lineWidth,
            dotDiameter: lineWidth * 1.35
        )
    }
}
