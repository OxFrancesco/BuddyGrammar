import XCTest
@testable import BuddyGrammarKit

final class KeyboardLatencyRecorderTests: XCTestCase {
    func testRecentWindowQuantilesAreBounded() {
        let clock = TestKeyboardLatencyClock()
        let recorder = KeyboardLatencyRecorder(
            capacityPerMetric: 4,
            clock: clock
        )

        for milliseconds in [10, 20, 30, 40, 50] {
            let token = recorder.begin(.swipeDecode)
            clock.advance(milliseconds: milliseconds)
            recorder.finish(token)
        }

        let snapshot = recorder.snapshot()
        let swipe = snapshot.swipeDecode
        XCTAssertEqual(swipe.count, 5)
        XCTAssertEqual(swipe.windowCount, 4)
        XCTAssertEqual(swipe.p50Milliseconds, 30)
        XCTAssertEqual(swipe.p95Milliseconds, 50)
        XCTAssertEqual(swipe.p99Milliseconds, 50)
        XCTAssertEqual(snapshot.droppedSampleCount, 1)
    }

    func testMetricsRemainSeparatedAndUseTheInjectedMonotonicClock() {
        let clock = TestKeyboardLatencyClock()
        let recorder = KeyboardLatencyRecorder(clock: clock)

        let feedback = recorder.begin(.keyDownToFeedback)
        clock.advance(milliseconds: 4)
        recorder.finish(feedback)

        let commit = recorder.begin(.keyDownToCommit)
        clock.advance(milliseconds: 11)
        recorder.finish(commit)

        let swipeResult = recorder.measure(.swipeDecode) {
            clock.advance(milliseconds: 23)
            return "result is never recorded"
        }

        XCTAssertEqual(swipeResult, "result is never recorded")
        XCTAssertEqual(recorder.snapshot().keyDownToFeedback.p50Milliseconds, 4)
        XCTAssertEqual(recorder.snapshot().keyDownToCommit.p50Milliseconds, 11)
        XCTAssertEqual(recorder.snapshot().swipeDecode.p50Milliseconds, 23)
    }

    func testCancellationDuplicatesAndLostEventsAreCountedWithoutLeakingPairs() {
        let clock = TestKeyboardLatencyClock()
        let recorder = KeyboardLatencyRecorder(recentTokenCapacity: 1, clock: clock)

        let cancelled = recorder.begin(.keyDownToCommit)
        recorder.cancel(cancelled)
        recorder.finish(cancelled)

        let first = recorder.begin(.keyDownToFeedback)
        recorder.finish(first)
        recorder.finish(first)

        let second = recorder.begin(.keyDownToFeedback)
        recorder.finish(second)
        recorder.finish(first)

        let snapshot = recorder.snapshot()
        XCTAssertEqual(snapshot.inFlightEventCount, 0)
        XCTAssertEqual(snapshot.droppedSampleCount, 1)
        XCTAssertEqual(snapshot.duplicateEventCount, 2)
        XCTAssertEqual(snapshot.lostEventCount, 1)
    }

    func testInFlightEventsAndRequestedCapacityCannotExceedHardLimits() {
        let clock = TestKeyboardLatencyClock()
        let recorder = KeyboardLatencyRecorder(
            capacityPerMetric: .max,
            maximumInFlightEvents: 1,
            clock: clock
        )

        let evicted = recorder.begin(.keyDownToCommit)
        let surviving = recorder.begin(.keyDownToCommit)
        recorder.finish(evicted)
        recorder.finish(surviving)

        for _ in 0...KeyboardLatencyRecorder.hardMaximumCapacityPerMetric {
            let token = recorder.begin(.swipeDecode)
            clock.advance(milliseconds: 1)
            recorder.finish(token)
        }

        let snapshot = recorder.snapshot()
        XCTAssertEqual(
            snapshot.swipeDecode.windowCount,
            KeyboardLatencyRecorder.hardMaximumCapacityPerMetric
        )
        XCTAssertEqual(snapshot.swipeDecode.count, 513)
        XCTAssertEqual(snapshot.inFlightEventCount, 0)
        XCTAssertEqual(snapshot.lostEventCount, 1)
        XCTAssertEqual(snapshot.duplicateEventCount, 1)
        XCTAssertEqual(snapshot.droppedSampleCount, 2)
    }

    func testSnapshotShapeContainsOnlyAggregateNumbers() {
        let snapshot = KeyboardLatencyRecorder(clock: TestKeyboardLatencyClock()).snapshot()
        assertAggregateOnly(snapshot)
    }

    private func assertAggregateOnly(
        _ value: Any,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch value {
        case is Int, is UInt64, is Double:
            return
        default:
            break
        }

        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional, mirror.children.isEmpty {
            return
        }
        guard value is KeyboardLatencySnapshot
                || value is KeyboardLatencySummary
                || mirror.displayStyle == .optional else {
            XCTFail("Unexpected non-aggregate diagnostics value: \(type(of: value))", file: file, line: line)
            return
        }
        for child in mirror.children {
            assertAggregateOnly(child.value, file: file, line: line)
        }
    }
}

private final class TestKeyboardLatencyClock: KeyboardLatencyClock, @unchecked Sendable {
    private var value: UInt64 = 0

    func nowNanoseconds() -> UInt64 { value }

    func advance(milliseconds: Int) {
        value += UInt64(milliseconds) * 1_000_000
    }
}
