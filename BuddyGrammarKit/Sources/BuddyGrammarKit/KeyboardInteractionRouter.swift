import Foundation

/// Platform-neutral coordinates used by the keyboard interaction state machine.
/// The rendering adapter decides whether a unit represents points or pixels.
public struct InteractionPoint: Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = InteractionPoint(x: 0, y: 0)

    fileprivate func distance(to other: InteractionPoint) -> Double {
        hypot(x - other.x, y - other.y)
    }
}

public enum KeyboardInteractionTarget: Equatable, Sendable {
    case key(String, alternates: [String], allowsSwipe: Bool = true)
    case space
    case delete
}

public enum KeyboardInteractionFeedback: Equatable, Sendable {
    case key
    case selection
}

public struct KeyboardInteractionDeadline: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case longPress
        case cursorActivation
        case deleteRepeat
    }

    public let token: Int
    public let dueTime: TimeInterval
    public let kind: Kind

    public init(token: Int, dueTime: TimeInterval, kind: Kind) {
        self.token = token
        self.dueTime = dueTime
        self.kind = kind
    }
}

public enum KeyboardInteractionInput: Equatable, Sendable {
    case press(
        target: KeyboardInteractionTarget,
        at: InteractionPoint,
        time: TimeInterval
    )
    case move(to: InteractionPoint, time: TimeInterval)
    case release(at: InteractionPoint, time: TimeInterval)
    case deadline(KeyboardInteractionDeadline)
    case cancel
}

public enum KeyboardInteractionEffect: Equatable, Sendable {
    case pressed(KeyboardInteractionTarget?)
    case preview(String?)
    case schedule(KeyboardInteractionDeadline)
    case showAlternates([String], selectedIndex: Int)
    case hideAlternates
    case commitText(String)
    case deleteBackward
    case deleteWord
    case moveCursor(Int)
    case swipeBegan(InteractionPoint)
    case swipeMoved(InteractionPoint)
    case swipeEnded(InteractionPoint)
    case feedback(KeyboardInteractionFeedback)
}

/// Serializes key preview, long-press, swipe, cursor, and delete-repeat rules.
///
/// The router is deliberately pure with respect to the editor and clock. The
/// platform schedules emitted deadlines and feeds them back; stale deadlines
/// are ignored by token. This keeps pointer arbitration identical on iOS and
/// Android without making literal insertion depend on asynchronous work.
public struct KeyboardInteractionRouter: Sendable {
    public struct Configuration: Equatable, Sendable {
        public var longPressDelay: TimeInterval
        public var swipeDistance: Double
        public var alternateStep: Double
        public var cursorActivationDistance: Double
        public var cursorActivationDelay: TimeInterval
        public var cursorStep: Double
        public var deleteRepeatDelay: TimeInterval
        public var deleteRepeatInterval: TimeInterval
        public var minimumDeleteRepeatInterval: TimeInterval
        public var wordDeleteAfterRepeats: Int

        public init(
            longPressDelay: TimeInterval = 0.35,
            swipeDistance: Double = 24,
            alternateStep: Double = 26,
            cursorActivationDistance: Double = 12,
            cursorActivationDelay: TimeInterval = 0.18,
            cursorStep: Double = 14,
            deleteRepeatDelay: TimeInterval = 0.45,
            deleteRepeatInterval: TimeInterval = 0.11,
            minimumDeleteRepeatInterval: TimeInterval = 0.045,
            wordDeleteAfterRepeats: Int = 6
        ) {
            self.longPressDelay = max(0, longPressDelay)
            self.swipeDistance = max(1, swipeDistance)
            self.alternateStep = max(1, alternateStep)
            self.cursorActivationDistance = max(1, cursorActivationDistance)
            self.cursorActivationDelay = max(0, cursorActivationDelay)
            self.cursorStep = max(1, cursorStep)
            self.deleteRepeatDelay = max(0, deleteRepeatDelay)
            self.deleteRepeatInterval = max(0.01, deleteRepeatInterval)
            self.minimumDeleteRepeatInterval = max(0.01, minimumDeleteRepeatInterval)
            self.wordDeleteAfterRepeats = max(1, wordDeleteAfterRepeats)
        }
    }

    private struct KeyState: Sendable {
        let token: Int
        let literal: String
        let alternates: [String]
        let origin: InteractionPoint
        let allowsSwipe: Bool
        var isSwiping = false
        var alternatesVisible = false
        var alternateIndex = 0
    }

    private struct SpaceState: Sendable {
        let token: Int
        let origin: InteractionPoint
        var cursorMode = false
        var emittedCursorSteps = 0
    }

    private struct DeleteState: Sendable {
        let token: Int
        var repeatCount = 0
    }

    private enum ActiveState: Sendable {
        case key(KeyState)
        case space(SpaceState)
        case delete(DeleteState)
    }

    private let configuration: Configuration
    private var nextToken = 0
    private var active: ActiveState?

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    public mutating func handle(
        _ input: KeyboardInteractionInput
    ) -> [KeyboardInteractionEffect] {
        switch input {
        case let .press(target, point, time):
            return begin(target: target, at: point, time: time)
        case let .move(point, _):
            return move(to: point)
        case let .release(point, _):
            return release(at: point)
        case let .deadline(deadline):
            return fire(deadline)
        case .cancel:
            return cancel()
        }
    }

    private mutating func begin(
        target: KeyboardInteractionTarget,
        at point: InteractionPoint,
        time: TimeInterval
    ) -> [KeyboardInteractionEffect] {
        nextToken &+= 1
        let token = nextToken

        switch target {
        case let .key(literal, alternates, allowsSwipe):
            active = .key(
                KeyState(
                    token: token,
                    literal: literal,
                    alternates: alternates,
                    origin: point,
                    allowsSwipe: allowsSwipe
                )
            )
            var effects: [KeyboardInteractionEffect] = [
                .pressed(target),
                .preview(literal),
            ]
            if !alternates.isEmpty {
                effects.append(
                    .schedule(
                        KeyboardInteractionDeadline(
                            token: token,
                            dueTime: time + configuration.longPressDelay,
                            kind: .longPress
                        )
                    )
                )
            }
            effects.append(.feedback(.key))
            return effects

        case .space:
            active = .space(SpaceState(token: token, origin: point))
            return [
                .pressed(.space),
                .schedule(
                    KeyboardInteractionDeadline(
                        token: token,
                        dueTime: time + configuration.cursorActivationDelay,
                        kind: .cursorActivation
                    )
                ),
                .feedback(.key),
            ]

        case .delete:
            active = .delete(DeleteState(token: token))
            return [
                .pressed(.delete),
                .deleteBackward,
                .feedback(.key),
                .schedule(
                    KeyboardInteractionDeadline(
                        token: token,
                        dueTime: time + configuration.deleteRepeatDelay,
                        kind: .deleteRepeat
                    )
                ),
            ]
        }
    }

    private mutating func move(to point: InteractionPoint) -> [KeyboardInteractionEffect] {
        switch active {
        case var .key(state):
            if state.alternatesVisible {
                let rawIndex = Int(
                    ((point.x - state.origin.x) / configuration.alternateStep).rounded()
                )
                let index = min(state.alternates.count - 1, max(0, rawIndex))
                guard index != state.alternateIndex else { return [] }
                state.alternateIndex = index
                active = .key(state)
                return [
                    .showAlternates(state.alternates, selectedIndex: index),
                ]
            }

            if state.isSwiping {
                return [.swipeMoved(point)]
            }

            guard state.allowsSwipe,
                  state.origin.distance(to: point) >= configuration.swipeDistance else {
                return []
            }
            state.isSwiping = true
            active = .key(state)
            return [
                .preview(nil),
                .swipeBegan(state.origin),
                .swipeMoved(point),
            ]

        case var .space(state):
            let horizontalDistance = point.x - state.origin.x
            guard state.cursorMode
                    || abs(horizontalDistance) >= configuration.cursorActivationDistance else {
                return []
            }

            var effects: [KeyboardInteractionEffect] = []
            if !state.cursorMode {
                state.cursorMode = true
                effects += [.preview(nil), .feedback(.selection)]
            }

            let totalSteps = Int(horizontalDistance / configuration.cursorStep)
            let delta = totalSteps - state.emittedCursorSteps
            if delta != 0 {
                state.emittedCursorSteps = totalSteps
                effects.append(.moveCursor(delta))
            }
            active = .space(state)
            return effects

        case .delete, nil:
            return []
        }
    }

    private mutating func release(
        at point: InteractionPoint
    ) -> [KeyboardInteractionEffect] {
        let released = active
        active = nil

        switch released {
        case let .key(state):
            if state.isSwiping {
                return [.swipeEnded(point), .pressed(nil)]
            }
            if state.alternatesVisible {
                return [
                    .commitText(state.alternates[state.alternateIndex]),
                    .hideAlternates,
                    .preview(nil),
                    .pressed(nil),
                ]
            }
            return [
                .commitText(state.literal),
                .preview(nil),
                .pressed(nil),
            ]

        case let .space(state):
            if state.cursorMode {
                return [.pressed(nil)]
            }
            return [.commitText(" "), .pressed(nil)]

        case .delete:
            return [.pressed(nil)]

        case nil:
            return []
        }
    }

    private mutating func fire(
        _ deadline: KeyboardInteractionDeadline
    ) -> [KeyboardInteractionEffect] {
        switch (deadline.kind, active) {
        case let (.longPress, .key(state))
            where deadline.token == state.token
                && !state.isSwiping
                && !state.alternatesVisible
                && !state.alternates.isEmpty:
            var updated = state
            updated.alternatesVisible = true
            updated.alternateIndex = 0
            active = .key(updated)
            return [
                .showAlternates(updated.alternates, selectedIndex: 0),
                .feedback(.selection),
            ]

        case let (.cursorActivation, .space(state))
            where deadline.token == state.token && !state.cursorMode:
            var updated = state
            updated.cursorMode = true
            active = .space(updated)
            return [.preview(nil), .feedback(.selection)]

        case let (.deleteRepeat, .delete(state)) where deadline.token == state.token:
            var updated = state
            updated.repeatCount += 1
            active = .delete(updated)

            let acceleration = min(
                configuration.deleteRepeatInterval
                    - configuration.minimumDeleteRepeatInterval,
                Double(updated.repeatCount) * 0.01
            )
            let interval = configuration.deleteRepeatInterval - acceleration
            return [
                .deleteBackward,
                .feedback(.key),
                .schedule(
                    KeyboardInteractionDeadline(
                        token: updated.token,
                        dueTime: deadline.dueTime + interval,
                        kind: .deleteRepeat
                    )
                ),
            ]

        default:
            return []
        }
    }

    private mutating func cancel() -> [KeyboardInteractionEffect] {
        guard let active else { return [] }
        self.active = nil
        switch active {
        case let .key(state) where state.alternatesVisible:
            return [.hideAlternates, .preview(nil), .pressed(nil)]
        case .key:
            return [.preview(nil), .pressed(nil)]
        case .space, .delete:
            return [.pressed(nil)]
        }
    }
}
