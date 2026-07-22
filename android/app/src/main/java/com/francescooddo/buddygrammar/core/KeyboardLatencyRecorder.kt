package com.francescooddo.buddygrammar.core

import java.util.EnumMap
import kotlin.math.ceil

/** Content-free latency categories collected by the keyboard process. */
enum class KeyboardLatencyMetric {
    KEY_DOWN_TO_FEEDBACK,
    KEY_DOWN_TO_COMMIT,
    SWIPE_DECODE,
}

/** Injectable monotonic clock for deterministic tests. */
fun interface KeyboardLatencyClock {
    fun nowNanoseconds(): Long
}

object SystemKeyboardLatencyClock : KeyboardLatencyClock {
    override fun nowNanoseconds(): Long = System.nanoTime()
}

/** Opaque in-memory event pairing token; it cannot carry input content. */
class KeyboardLatencyToken internal constructor(
    internal val identifier: Long,
    internal val metric: KeyboardLatencyMetric,
)

data class KeyboardLatencySummary(
    /** Valid samples seen since this process-local recorder was created. */
    val count: Long,
    /** Recent samples represented by the percentile window. */
    val windowCount: Int,
    val p50Milliseconds: Double?,
    val p95Milliseconds: Double?,
    val p99Milliseconds: Double?,
)

/**
 * Aggregate-only diagnostics. There are no raw durations, tokens, ordered
 * events, characters, text, document context, or swipe coordinates here.
 */
data class KeyboardLatencySnapshot(
    val keyDownToFeedback: KeyboardLatencySummary,
    val keyDownToCommit: KeyboardLatencySummary,
    val swipeDecode: KeyboardLatencySummary,
    val droppedSampleCount: Long,
    val duplicateEventCount: Long,
    val lostEventCount: Long,
    val inFlightEventCount: Int,
) {
    fun summary(metric: KeyboardLatencyMetric): KeyboardLatencySummary = when (metric) {
        KeyboardLatencyMetric.KEY_DOWN_TO_FEEDBACK -> keyDownToFeedback
        KeyboardLatencyMetric.KEY_DOWN_TO_COMMIT -> keyDownToCommit
        KeyboardLatencyMetric.SWIPE_DECODE -> swipeDecode
    }
}

/**
 * Bounded, content-free, process-memory-only recorder for keyboard hot paths.
 *
 * Recording never logs, persists, performs network work, or sorts. The small
 * recent-duration windows are sorted only on an explicit snapshot request.
 */
class KeyboardLatencyRecorder(
    capacityPerMetric: Int = DEFAULT_CAPACITY_PER_METRIC,
    maximumInFlightEvents: Int = DEFAULT_MAXIMUM_IN_FLIGHT_EVENTS,
    recentTokenCapacity: Int = DEFAULT_RECENT_TOKEN_CAPACITY,
    maximumDurationMilliseconds: Double = DEFAULT_MAXIMUM_DURATION_MILLISECONDS,
    private val clock: KeyboardLatencyClock = SystemKeyboardLatencyClock,
) {
    private data class ActiveEvent(
        val metric: KeyboardLatencyMetric,
        val startedAtNanoseconds: Long,
    )

    private class SampleWindow(private val capacity: Int) {
        private val values = LongArray(capacity)
        private var size = 0
        private var nextIndex = 0
        var totalCount: Long = 0
            private set

        /** Returns true when a previous sample was evicted. */
        fun append(value: Long): Boolean {
            totalCount = incremented(totalCount)
            if (size < capacity) {
                values[size] = value
                size += 1
                return false
            }
            values[nextIndex] = value
            nextIndex = (nextIndex + 1) % capacity
            return true
        }

        fun summary(): KeyboardLatencySummary {
            val sorted = values.copyOf(size).apply(LongArray::sort)
            return KeyboardLatencySummary(
                count = totalCount,
                windowCount = size,
                p50Milliseconds = percentile(0.50, sorted),
                p95Milliseconds = percentile(0.95, sorted),
                p99Milliseconds = percentile(0.99, sorted),
            )
        }

        private fun percentile(percentile: Double, sorted: LongArray): Double? {
            if (sorted.isEmpty()) return null
            val rank = ceil(percentile * sorted.size).toInt()
            val index = (rank - 1).coerceIn(0, sorted.lastIndex)
            return sorted[index] / 1_000_000.0
        }
    }

    private val capacityPerMetric = capacityPerMetric.coerceIn(1, HARD_MAXIMUM_CAPACITY_PER_METRIC)
    private val maximumInFlightEvents = maximumInFlightEvents.coerceIn(
        1,
        HARD_MAXIMUM_IN_FLIGHT_EVENTS,
    )
    private val recentTokenCapacity = recentTokenCapacity.coerceIn(
        1,
        HARD_MAXIMUM_RECENT_TOKEN_CAPACITY,
    )
    private val maximumDurationNanoseconds = (maximumDurationMilliseconds
        .takeIf(Double::isFinite) ?: DEFAULT_MAXIMUM_DURATION_MILLISECONDS)
        .coerceIn(
        1.0,
        DEFAULT_MAXIMUM_DURATION_MILLISECONDS,
    ).times(1_000_000.0).toLong()

    private var nextIdentifier = 0L
    private val activeEvents = mutableMapOf<Long, ActiveEvent>()
    private val recentTerminalIdentifiers = ArrayDeque<Long>()
    private val recentTerminalIdentifierSet = mutableSetOf<Long>()
    private val windows = EnumMap<KeyboardLatencyMetric, SampleWindow>(
        KeyboardLatencyMetric::class.java,
    ).apply {
        KeyboardLatencyMetric.entries.forEach { metric ->
            put(metric, SampleWindow(this@KeyboardLatencyRecorder.capacityPerMetric))
        }
    }
    private var droppedSampleCount = 0L
    private var duplicateEventCount = 0L
    private var lostEventCount = 0L

    @Synchronized
    fun begin(metric: KeyboardLatencyMetric): KeyboardLatencyToken {
        if (activeEvents.size >= maximumInFlightEvents) {
            activeEvents.keys.minOrNull()?.let { oldestIdentifier ->
                activeEvents.remove(oldestIdentifier)
                droppedSampleCount = incremented(droppedSampleCount)
                lostEventCount = incremented(lostEventCount)
                rememberTerminal(oldestIdentifier)
            }
        }

        nextIdentifier = if (nextIdentifier == Long.MAX_VALUE) 1L else nextIdentifier + 1L
        val token = KeyboardLatencyToken(nextIdentifier, metric)
        activeEvents[token.identifier] = ActiveEvent(metric, clock.nowNanoseconds())
        return token
    }

    @Synchronized
    fun finish(token: KeyboardLatencyToken) {
        val event = activeEvents.remove(token.identifier)
        if (event == null) {
            recordMissingTerminal(token.identifier)
            return
        }
        if (event.metric != token.metric) {
            lostEventCount = incremented(lostEventCount)
            droppedSampleCount = incremented(droppedSampleCount)
            rememberTerminal(token.identifier)
            return
        }

        val duration = clock.nowNanoseconds() - event.startedAtNanoseconds
        if (duration < 0L || duration > maximumDurationNanoseconds) {
            droppedSampleCount = incremented(droppedSampleCount)
            rememberTerminal(token.identifier)
            return
        }

        if (windows.getValue(event.metric).append(duration)) {
            droppedSampleCount = incremented(droppedSampleCount)
        }
        rememberTerminal(token.identifier)
    }

    /** Cancelling an unfinished event is visible as one dropped sample. */
    @Synchronized
    fun cancel(token: KeyboardLatencyToken) {
        if (activeEvents.remove(token.identifier) == null) {
            recordMissingTerminal(token.identifier)
            return
        }
        droppedSampleCount = incremented(droppedSampleCount)
        rememberTerminal(token.identifier)
    }

    fun <T> measure(metric: KeyboardLatencyMetric, operation: () -> T): T {
        val token = begin(metric)
        return try {
            operation()
        } finally {
            finish(token)
        }
    }

    @Synchronized
    fun snapshot(): KeyboardLatencySnapshot = KeyboardLatencySnapshot(
        keyDownToFeedback = windows.getValue(KeyboardLatencyMetric.KEY_DOWN_TO_FEEDBACK).summary(),
        keyDownToCommit = windows.getValue(KeyboardLatencyMetric.KEY_DOWN_TO_COMMIT).summary(),
        swipeDecode = windows.getValue(KeyboardLatencyMetric.SWIPE_DECODE).summary(),
        droppedSampleCount = droppedSampleCount,
        duplicateEventCount = duplicateEventCount,
        lostEventCount = lostEventCount,
        inFlightEventCount = activeEvents.size,
    )

    private fun recordMissingTerminal(identifier: Long) {
        if (identifier in recentTerminalIdentifierSet) {
            duplicateEventCount = incremented(duplicateEventCount)
        } else {
            lostEventCount = incremented(lostEventCount)
        }
    }

    private fun rememberTerminal(identifier: Long) {
        if (recentTerminalIdentifierSet.add(identifier)) {
            recentTerminalIdentifiers.addLast(identifier)
        }
        while (recentTerminalIdentifiers.size > recentTokenCapacity) {
            recentTerminalIdentifierSet.remove(recentTerminalIdentifiers.removeFirst())
        }
    }

    companion object {
        const val DEFAULT_CAPACITY_PER_METRIC = 256
        const val HARD_MAXIMUM_CAPACITY_PER_METRIC = 512
        const val DEFAULT_MAXIMUM_IN_FLIGHT_EVENTS = 32
        const val HARD_MAXIMUM_IN_FLIGHT_EVENTS = 64
        const val DEFAULT_RECENT_TOKEN_CAPACITY = 64
        const val HARD_MAXIMUM_RECENT_TOKEN_CAPACITY = 128
        const val DEFAULT_MAXIMUM_DURATION_MILLISECONDS = 60_000.0

        /** Shared, process-local recorder used by production keyboard seams. */
        val production = KeyboardLatencyRecorder()

        private fun incremented(value: Long): Long = if (value == Long.MAX_VALUE) value else value + 1
    }
}
