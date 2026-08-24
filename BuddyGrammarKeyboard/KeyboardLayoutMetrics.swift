import CoreGraphics

struct KeyboardMetrics: Equatable {
    let width: CGFloat
    let bodyHeight: CGFloat
    let outerPadding: CGFloat

    var keySpacing: CGFloat { width > 600 ? 7 : 5 }
    var rowSpacing: CGFloat { width > 600 ? 8 : 7 }
    var horizontalPadding: CGFloat { 4 }
    var suggestionBarHeight: CGFloat { 44 }
    var keyHeight: CGFloat {
        min(58, max(30, (bodyHeight - 3 * rowSpacing) / 4))
    }
    var letterKeyWidth: CGFloat {
        max(20, (width - 2 * horizontalPadding - 9 * keySpacing) / 10)
    }
    var wideFunctionKeyWidth: CGFloat { min(64, letterKeyWidth * 1.35) }

    init(size: CGSize) {
        let minimumOuterPadding: CGFloat = 4
        let availableWidth = max(0, size.width - 2 * minimumOuterPadding)
        let maximumThumbReachWidth: CGFloat = size.width >= 760 ? 720 : availableWidth

        width = min(availableWidth, maximumThumbReachWidth)
        outerPadding = max(minimumOuterPadding, (size.width - width) / 2)
        bodyHeight = max(120, size.height - 44 - 14)
    }

    init(width: CGFloat, bodyHeight: CGFloat) {
        self.width = width
        self.bodyHeight = bodyHeight
        outerPadding = 4
    }
}
