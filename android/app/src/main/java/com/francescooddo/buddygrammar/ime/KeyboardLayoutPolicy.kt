package com.francescooddo.buddygrammar.ime

/**
 * Size decisions shared by every keyboard layer.
 *
 * The 600 dp boundary is Android's compact/medium window boundary. Medium and
 * expanded windows use a split key grid so keys stay thumb-reachable instead
 * of stretching across a tablet or unfolded device.
 */
internal data class KeyboardLayoutSpec(
    val sidePaddingDp: Int,
    val keyHeightDp: Int,
    val centerGapDp: Int,
    val emojiPanelHeightDp: Int,
    val handwritingCanvasHeightDp: Int,
    val voicePanelHeightDp: Int,
    val iconControlKeyWidthDp: Int,
    val wideControlKeyWidthDp: Int,
    val minimumNavigationBarHeightDp: Int = 24,
    val navigationBarSafetyGapDp: Int = 20,
) {
    val usesSplitKeyGrid: Boolean
        get() = centerGapDp > 0
}

internal object KeyboardLayoutPolicy {
    private const val MEDIUM_WIDTH_DP = 600
    private const val EXPANDED_WIDTH_DP = 840

    fun resolve(screenWidthDp: Int, screenHeightDp: Int): KeyboardLayoutSpec {
        val isShortWindow = screenHeightDp < 480
        val isMediumWindow = screenWidthDp >= MEDIUM_WIDTH_DP
        val isExpandedWindow = screenWidthDp >= EXPANDED_WIDTH_DP

        val centerGap = if (isMediumWindow) {
            (screenWidthDp * 14 / 100).coerceIn(72, 140)
        } else {
            0
        }

        return KeyboardLayoutSpec(
            sidePaddingDp = when {
                isExpandedWindow -> 20
                isMediumWindow -> 12
                else -> 6
            },
            keyHeightDp = when {
                isShortWindow -> 42
                isMediumWindow -> 48
                screenHeightDp >= 900 -> 52
                else -> 48
            },
            centerGapDp = centerGap,
            emojiPanelHeightDp = when {
                isShortWindow -> 150
                isMediumWindow -> 220
                else -> 200
            },
            handwritingCanvasHeightDp = when {
                isShortWindow -> 112
                isMediumWindow -> 168
                else -> 150
            },
            voicePanelHeightDp = when {
                isShortWindow -> 168
                isMediumWindow -> 220
                else -> 205
            },
            iconControlKeyWidthDp = when {
                isExpandedWindow -> 72
                isMediumWindow -> 64
                else -> 48
            },
            wideControlKeyWidthDp = when {
                isExpandedWindow -> 112
                isMediumWindow -> 96
                else -> 62
            },
        )
    }
}
