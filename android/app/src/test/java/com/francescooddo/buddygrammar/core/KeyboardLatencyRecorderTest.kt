package com.francescooddo.buddygrammar.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class KeyboardLatencyRecorderTest {
    @Test
    fun `recent percentile window is hard bounded`() {
        val clock = TestKeyboardLatencyClock()
        val recorder = KeyboardLatencyRecorder(
            capacityPerMetric = 4,
            clock = clock,
        )

        listOf(10L, 20L, 30L, 40L, 50L).forEach { milliseconds ->
            val token = recorder.begin(KeyboardLatencyMetric.SWIPE_DECODE)
            clock.advanceMilliseconds(milliseconds)
            recorder.finish(token)
        }

        val snapshot = recorder.snapshot()
        assertEquals(5L, snapshot.swipeDecode.count)
        assertEquals(4, snapshot.swipeDecode.windowCount)
        assertEquals(30.0, snapshot.swipeDecode.p50Milliseconds ?: -1.0, 0.0)
        assertEquals(50.0, snapshot.swipeDecode.p95Milliseconds ?: -1.0, 0.0)
        assertEquals(50.0, snapshot.swipeDecode.p99Milliseconds ?: -1.0, 0.0)
        assertEquals(1L, snapshot.droppedSampleCount)
    }

    @Test
    fun `metrics stay separated and use injected monotonic time`() {
        val clock = TestKeyboardLatencyClock()
        val recorder = KeyboardLatencyRecorder(clock = clock)

        val feedback = recorder.begin(KeyboardLatencyMetric.KEY_DOWN_TO_FEEDBACK)
        clock.advanceMilliseconds(4)
        recorder.finish(feedback)

        val commit = recorder.begin(KeyboardLatencyMetric.KEY_DOWN_TO_COMMIT)
        clock.advanceMilliseconds(11)
        recorder.finish(commit)

        val result = recorder.measure(KeyboardLatencyMetric.SWIPE_DECODE) {
            clock.advanceMilliseconds(23)
            "result is never recorded"
        }

        val snapshot = recorder.snapshot()
        assertEquals("result is never recorded", result)
        assertEquals(4.0, snapshot.keyDownToFeedback.p50Milliseconds ?: -1.0, 0.0)
        assertEquals(11.0, snapshot.keyDownToCommit.p50Milliseconds ?: -1.0, 0.0)
        assertEquals(23.0, snapshot.swipeDecode.p50Milliseconds ?: -1.0, 0.0)
    }

    @Test
    fun `cancel duplicate and lost events are counted without leaking pairs`() {
        val clock = TestKeyboardLatencyClock()
        val recorder = KeyboardLatencyRecorder(recentTokenCapacity = 1, clock = clock)

        val cancelled = recorder.begin(KeyboardLatencyMetric.KEY_DOWN_TO_COMMIT)
        recorder.cancel(cancelled)
        recorder.finish(cancelled)

        val first = recorder.begin(KeyboardLatencyMetric.KEY_DOWN_TO_FEEDBACK)
        recorder.finish(first)
        recorder.finish(first)

        val second = recorder.begin(KeyboardLatencyMetric.KEY_DOWN_TO_FEEDBACK)
        recorder.finish(second)
        recorder.finish(first)

        val snapshot = recorder.snapshot()
        assertEquals(0, snapshot.inFlightEventCount)
        assertEquals(1L, snapshot.droppedSampleCount)
        assertEquals(2L, snapshot.duplicateEventCount)
        assertEquals(1L, snapshot.lostEventCount)
    }

    @Test
    fun `requested capacities and in flight pairs cannot exceed hard limits`() {
        val clock = TestKeyboardLatencyClock()
        val recorder = KeyboardLatencyRecorder(
            capacityPerMetric = Int.MAX_VALUE,
            maximumInFlightEvents = 1,
            clock = clock,
        )

        val evicted = recorder.begin(KeyboardLatencyMetric.KEY_DOWN_TO_COMMIT)
        val surviving = recorder.begin(KeyboardLatencyMetric.KEY_DOWN_TO_COMMIT)
        recorder.finish(evicted)
        recorder.finish(surviving)

        repeat(KeyboardLatencyRecorder.HARD_MAXIMUM_CAPACITY_PER_METRIC + 1) {
            val token = recorder.begin(KeyboardLatencyMetric.SWIPE_DECODE)
            clock.advanceMilliseconds(1)
            recorder.finish(token)
        }

        val snapshot = recorder.snapshot()
        assertEquals(
            KeyboardLatencyRecorder.HARD_MAXIMUM_CAPACITY_PER_METRIC,
            snapshot.swipeDecode.windowCount,
        )
        assertEquals(513L, snapshot.swipeDecode.count)
        assertEquals(0, snapshot.inFlightEventCount)
        assertEquals(1L, snapshot.lostEventCount)
        assertEquals(1L, snapshot.duplicateEventCount)
        assertEquals(2L, snapshot.droppedSampleCount)
    }

    @Test
    fun `public snapshot shape is aggregate only`() {
        val snapshot = KeyboardLatencyRecorder(clock = TestKeyboardLatencyClock()).snapshot()
        val snapshotFieldTypes = snapshot.javaClass.declaredFields.map { it.type }
        val summaryFieldTypes = snapshot.swipeDecode.javaClass.declaredFields.map { it.type }

        assertTrue(
            snapshotFieldTypes.all { type ->
                type == KeyboardLatencySummary::class.java ||
                    type == java.lang.Long.TYPE ||
                    type == java.lang.Integer.TYPE
            },
        )
        assertTrue(
            summaryFieldTypes.all { type ->
                type.isPrimitive || Number::class.java.isAssignableFrom(type)
            },
        )
        assertTrue(
            (snapshot.javaClass.declaredFields + snapshot.swipeDecode.javaClass.declaredFields)
                .none { field ->
                    listOf("text", "character", "coordinate", "point", "history", "token")
                        .any { forbidden -> field.name.contains(forbidden, ignoreCase = true) }
                },
        )
    }
}

private class TestKeyboardLatencyClock : KeyboardLatencyClock {
    private var value = 0L

    override fun nowNanoseconds(): Long = value

    fun advanceMilliseconds(milliseconds: Long) {
        value += milliseconds * 1_000_000
    }
}
