import BuddyGrammarKit
import Testing

@Suite("Bounded live swipe samples")
struct BoundedSwipePathBufferTests {
    @Test("hard cap preserves exact down and latest samples")
    func preservesEndpoints() {
        var buffer = BoundedSwipePathBuffer(capacity: 32)
        for index in 0..<1_000 {
            buffer.append(
                SwipePathSample(
                    x: Double(index) / 100,
                    y: 0,
                    timestampMilliseconds: Double(index)
                )
            )
        }

        #expect(buffer.samples.count == 32)
        #expect(buffer.samples.first?.timestampMilliseconds == 0)
        #expect(buffer.samples.last?.timestampMilliseconds == 999)
    }

    @Test("a dwell retains three timed anchors after thinning")
    func preservesDwellEvidence() {
        var buffer = BoundedSwipePathBuffer(capacity: 16)
        for index in 0..<100 {
            buffer.append(
                SwipePathSample(
                    x: 3,
                    y: 1,
                    timestampMilliseconds: Double(index * 10)
                )
            )
        }

        #expect(buffer.samples.count == 16)
        #expect(buffer.samples.filter { $0.x == 3 && $0.y == 1 }.count >= 3)
        #expect(
            (buffer.samples.last?.timestampMilliseconds ?? 0)
                - (buffer.samples.first?.timestampMilliseconds ?? 0) >= 180
        )
    }
}
