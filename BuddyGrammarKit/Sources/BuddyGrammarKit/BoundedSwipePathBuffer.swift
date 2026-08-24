import Foundation

/// Deterministically bounds a live swipe before recognition resamples it.
/// The exact down/latest samples and high-curvature path points are retained;
/// a qualifying dwell run also protects its start, midpoint, and end.
public struct BoundedSwipePathBuffer: Equatable, Sendable {
    public let capacity: Int
    public private(set) var samples: [SwipePathSample] = []

    private let dwellConfiguration: SwipeDwellConfiguration

    public init(
        capacity: Int = 256,
        dwellConfiguration: SwipeDwellConfiguration = .contractV1
    ) {
        self.capacity = max(2, capacity)
        self.dwellConfiguration = dwellConfiguration
    }

    public mutating func append(_ sample: SwipePathSample) {
        samples.append(sample)
        guard samples.count > capacity else { return }
        samples.remove(at: leastInformativeInteriorIndex())
    }

    public mutating func removeAll(keepingCapacity: Bool = true) {
        samples.removeAll(keepingCapacity: keepingCapacity)
    }

    private func leastInformativeInteriorIndex() -> Int {
        let protected = protectedDwellAnchors()
        let candidates = samples.indices.dropFirst().dropLast().filter {
            !protected.contains($0)
        }
        let fallback = samples.indices.dropFirst().dropLast()
        return (candidates.isEmpty ? Array(fallback) : candidates).min {
            redundancyCost(at: $0) < redundancyCost(at: $1)
        } ?? 1
    }

    private func redundancyCost(at index: Int) -> Double {
        let previous = samples[index - 1]
        let current = samples[index]
        let next = samples[index + 1]
        let direct = distance(previous, next)
        let path = distance(previous, current) + distance(current, next)
        let curvature = max(0, path - direct)
        let localDensity = min(
            distance(previous, current),
            distance(current, next)
        )
        return curvature * 1_000 + localDensity
    }

    private func protectedDwellAnchors() -> Set<Int> {
        var protected: Set<Int> = [samples.startIndex, samples.index(before: samples.endIndex)]
        var runStart = samples.startIndex

        while runStart < samples.endIndex {
            guard let key = nearestKey(to: samples[runStart]) else {
                runStart += 1
                continue
            }
            var runEnd = runStart + 1
            while runEnd < samples.endIndex,
                  nearestKey(to: samples[runEnd]) == key {
                runEnd += 1
            }
            let run = runStart..<runEnd
            if run.count >= dwellConfiguration.minimumSamples,
               let first = run.first,
               let last = run.last,
               samples[last].timestampMilliseconds
                    - samples[first].timestampMilliseconds
                    >= dwellConfiguration.minimumMilliseconds,
               run.allSatisfy({ distance(samples[first], samples[$0])
                    <= dwellConfiguration.maximumDriftKeyUnits }) {
                let midpointTime = (
                    samples[first].timestampMilliseconds
                        + samples[last].timestampMilliseconds
                ) / 2
                let midpoint = run.min {
                    abs(samples[$0].timestampMilliseconds - midpointTime)
                        < abs(samples[$1].timestampMilliseconds - midpointTime)
                } ?? first
                protected.formUnion([first, midpoint, last])
            }
            runStart = runEnd
        }
        return protected
    }

    private func nearestKey(to sample: SwipePathSample) -> Character? {
        QwertyKeyLayout.nearestKey(
            to: CGPoint(x: sample.x, y: sample.y)
        )
    }

    private func distance(_ lhs: SwipePathSample, _ rhs: SwipePathSample) -> Double {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }
}
