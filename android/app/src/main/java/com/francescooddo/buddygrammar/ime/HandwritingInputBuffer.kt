package com.francescooddo.buddygrammar.ime

import java.util.ArrayDeque

internal data class HandwritingInputPoint(
    val x: Float,
    val y: Float,
    val timeMillis: Long,
)

/**
 * Streaming handwriting storage with hard stroke and point limits.
 *
 * Appends are O(1): once a stroke reaches its cap, a deterministic rotating
 * reservoir keeps the first point, recent interior points, and the exact
 * newest endpoint. Snapshots are sorted back into input order.
 */
internal class HandwritingInputBuffer(
    private val maximumPointsPerStroke: Int = DEFAULT_MAXIMUM_POINTS_PER_STROKE,
    private val maximumStrokeCount: Int = DEFAULT_MAXIMUM_STROKE_COUNT,
    private val maximumTotalPointCount: Int = DEFAULT_MAXIMUM_TOTAL_POINT_COUNT,
) {
    private data class SequencedPoint(
        val point: HandwritingInputPoint,
        val sequence: Long,
    )

    private class BoundedStroke(private val capacity: Int) {
        private val slots = ArrayList<SequencedPoint>(capacity)
        private var replacementOffset = 0

        val size: Int
            get() = slots.size

        fun append(point: SequencedPoint) {
            if (slots.size < capacity) {
                slots.add(point)
                return
            }

            if (capacity == 2) {
                slots[1] = point
                return
            }

            val previousEndpoint = slots[slots.lastIndex]
            val replacementIndex = 1 + replacementOffset
            slots[replacementIndex] = previousEndpoint
            slots[slots.lastIndex] = point
            replacementOffset = (replacementOffset + 1) % (capacity - 2)
        }

        fun snapshot(): List<HandwritingInputPoint> = slots
            .sortedBy(SequencedPoint::sequence)
            .map(SequencedPoint::point)
    }

    private val finished = ArrayDeque<List<HandwritingInputPoint>>()
    private var finishedPointCount = 0
    private var active: BoundedStroke? = null
    private var nextSequence = 0L

    init {
        require(maximumPointsPerStroke >= 2) {
            "A stroke needs room for its first and last points."
        }
        require(maximumStrokeCount >= 1) { "At least one stroke must be allowed." }
        require(maximumTotalPointCount >= maximumPointsPerStroke) {
            "The total point cap must fit one maximum-size stroke."
        }
    }

    val activeStroke: List<HandwritingInputPoint>
        get() = active?.snapshot().orEmpty()

    val finishedStrokes: List<List<HandwritingInputPoint>>
        get() = finished.toList()

    val totalPointCount: Int
        get() = finishedPointCount + (active?.size ?: 0)

    val hasFinishedStrokes: Boolean
        get() = finished.isNotEmpty()

    fun start(point: HandwritingInputPoint) {
        active = null
        while (finished.size >= maximumStrokeCount) removeOldestStroke()
        makeRoomForAdditionalPoint()
        active = BoundedStroke(maximumPointsPerStroke).also { stroke ->
            stroke.append(point.sequenced())
        }
    }

    /** Returns `false` when there is no active stroke. */
    fun append(point: HandwritingInputPoint): Boolean {
        val stroke = active ?: return false
        if (stroke.size < maximumPointsPerStroke) makeRoomForAdditionalPoint()
        stroke.append(point.sequenced())
        return true
    }

    /** Returns `true` when a non-empty stroke was finished. */
    fun end(): Boolean {
        val stroke = active ?: return false
        active = null
        val snapshot = stroke.snapshot()
        if (snapshot.isEmpty()) return false

        while (finished.size >= maximumStrokeCount) removeOldestStroke()
        while (
            finished.isNotEmpty() &&
            finishedPointCount + snapshot.size > maximumTotalPointCount
        ) {
            removeOldestStroke()
        }
        finished.addLast(snapshot)
        finishedPointCount += snapshot.size
        return true
    }

    fun clear() {
        finished.clear()
        finishedPointCount = 0
        active = null
        nextSequence = 0L
    }

    private fun makeRoomForAdditionalPoint() {
        while (finished.isNotEmpty() && totalPointCount >= maximumTotalPointCount) {
            removeOldestStroke()
        }
    }

    private fun removeOldestStroke() {
        val removed = finished.removeFirst()
        finishedPointCount -= removed.size
    }

    private fun HandwritingInputPoint.sequenced(): SequencedPoint =
        SequencedPoint(this, nextSequence++)

    private companion object {
        const val DEFAULT_MAXIMUM_POINTS_PER_STROKE = 256
        const val DEFAULT_MAXIMUM_STROKE_COUNT = 32
        const val DEFAULT_MAXIMUM_TOTAL_POINT_COUNT = 2_048
    }
}
