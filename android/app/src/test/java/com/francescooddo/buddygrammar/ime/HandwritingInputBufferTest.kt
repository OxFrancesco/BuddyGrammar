package com.francescooddo.buddygrammar.ime

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HandwritingInputBufferTest {
    @Test
    fun `pathological stroke stays capped and preserves exact endpoints`() {
        val buffer = HandwritingInputBuffer(
            maximumPointsPerStroke = 8,
            maximumStrokeCount = 4,
            maximumTotalPointCount = 24,
        )
        buffer.start(point(0))
        repeat(10_000) { index -> buffer.append(point(index + 1)) }

        val active = buffer.activeStroke
        assertEquals(8, active.size)
        assertEquals(point(0), active.first())
        assertEquals(point(10_000), active.last())
        assertTrue(active.zipWithNext().all { (left, right) -> left.timeMillis < right.timeMillis })
        assertEquals(8, buffer.totalPointCount)
    }

    @Test
    fun `stroke and total limits evict oldest ink while retaining newest strokes`() {
        val buffer = HandwritingInputBuffer(
            maximumPointsPerStroke = 4,
            maximumStrokeCount = 3,
            maximumTotalPointCount = 8,
        )

        repeat(8) { strokeIndex ->
            val base = strokeIndex * 100
            buffer.start(point(base))
            repeat(3) { offset -> buffer.append(point(base + offset + 1)) }
            assertTrue(buffer.end())
            assertTrue(buffer.finishedStrokes.size <= 3)
            assertTrue(buffer.totalPointCount <= 8)
        }

        val retained = buffer.finishedStrokes
        assertEquals(listOf(600, 700), retained.map { it.first().x.toInt() })
        assertEquals(listOf(603, 703), retained.map { it.last().x.toInt() })
        assertEquals(8, buffer.totalPointCount)
    }

    @Test
    fun `bounded fallback is deterministic for identical interleaved input`() {
        fun capture(): List<List<HandwritingInputPoint>> {
            val buffer = HandwritingInputBuffer(
                maximumPointsPerStroke = 5,
                maximumStrokeCount = 2,
                maximumTotalPointCount = 9,
            )
            repeat(5) { strokeIndex ->
                val base = strokeIndex * 1_000
                buffer.start(point(base))
                repeat(100) { offset -> buffer.append(point(base + offset + 1)) }
                buffer.end()
            }
            return buffer.finishedStrokes
        }

        assertEquals(capture(), capture())
    }

    @Test
    fun `starting a new stroke keeps the active total under the hard cap`() {
        val buffer = HandwritingInputBuffer(
            maximumPointsPerStroke = 6,
            maximumStrokeCount = 4,
            maximumTotalPointCount = 8,
        )
        repeat(2) { strokeIndex ->
            buffer.start(point(strokeIndex * 10))
            repeat(3) { offset -> buffer.append(point(strokeIndex * 10 + offset + 1)) }
            buffer.end()
        }

        buffer.start(point(100))
        repeat(20_000) { offset ->
            buffer.append(point(101 + offset))
            assertTrue(buffer.totalPointCount <= 8)
        }

        assertEquals(point(100), buffer.activeStroke.first())
        assertEquals(point(20_100), buffer.activeStroke.last())
    }

    private fun point(value: Int): HandwritingInputPoint = HandwritingInputPoint(
        x = value.toFloat(),
        y = (value % 17).toFloat(),
        timeMillis = value.toLong(),
    )
}
