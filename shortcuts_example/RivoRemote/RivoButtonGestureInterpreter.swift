import Combine
import Foundation

nonisolated struct RivoButtonGestureConfiguration:
    Equatable,
    Sendable
{
    var pressDelay: TimeInterval = 0.010
    var releaseDelay: TimeInterval = 0.050
    var longPressDelay: TimeInterval = 0.500
    var doubleTapInterval: TimeInterval = 0.300
    var missingReleaseTimeout: TimeInterval = 3.000

    static let androidCompatible =
        RivoButtonGestureConfiguration()
}

nonisolated struct RivoButtonGestureRecognizer:
    Sendable
{
    private struct ButtonState: Sendable {
        var isPressed = false
        var pressDispatched = false
        var longPressDispatched = false
        var doubleTapActive = false
        var waitingForSecondTap = false
        var supportsDoubleTap = false
        var rawKey: UInt8 = 0
        var lastReleasedAt: TimeInterval?
        var pressDeadline: TimeInterval?
        var releaseDeadline: TimeInterval?
        var longPressDeadline: TimeInterval?
        var singleTapDeadline: TimeInterval?
        var autoReleaseDeadline: TimeInterval?
    }

    private enum DeadlineKind: Int, Sendable {
        case press
        case longPress
        case singleTap
        case release
        case autoRelease
    }

    private struct Deadline: Sendable {
        let time: TimeInterval
        let button: RivoButton
        let kind: DeadlineKind
    }

    private let configuration:
        RivoButtonGestureConfiguration
    private let doubleTapButtons: Set<RivoButton>
    private var states: [RivoButton: ButtonState] = [:]

    init(
        configuration: RivoButtonGestureConfiguration =
            .androidCompatible,
        doubleTapButtons: Set<RivoButton> = [
            .l1, .l2, .l3, .l4, .r1, .r4
        ]
    ) {
        self.configuration = configuration
        self.doubleTapButtons = doubleTapButtons
    }

    var nextDeadline: TimeInterval? {
        allDeadlines().map(\.time).min()
    }

    mutating func receive(
        _ input: RivoRemoteInput,
        at time: TimeInterval
    ) -> [RivoRemoteInput] {
        var output = advance(to: time)

        guard case .button(
            let button,
            let action,
            let rawKey
        ) = input else {
            output.append(input)
            return output
        }

        switch action {
        case .pressed:
            output.append(
                contentsOf: press(
                    button,
                    rawKey: rawKey,
                    at: time
                )
            )
        case .released:
            output.append(
                contentsOf: release(
                    button,
                    rawKey: rawKey,
                    at: time
                )
            )
        case .longPressed,
             .longPressEnded,
             .doubleTapped,
             .doubleTapEnded:
            output.append(input)
        }
        return output
    }

    mutating func advance(
        to time: TimeInterval
    ) -> [RivoRemoteInput] {
        var output: [RivoRemoteInput] = []

        while let deadline = nextDueDeadline(at: time) {
            output.append(
                contentsOf: process(deadline)
            )
        }
        return output
    }

    mutating func releaseAll(
        at time: TimeInterval
    ) -> [RivoRemoteInput] {
        var output = advance(to: time)
        for button in RivoButton.allCases {
            guard let state = states[button] else {
                continue
            }
            output.append(
                contentsOf: finish(
                    button,
                    state: state
                )
            )
            states.removeValue(forKey: button)
        }
        return output
    }

    private mutating func press(
        _ button: RivoButton,
        rawKey: UInt8,
        at time: TimeInterval
    ) -> [RivoRemoteInput] {
        var output: [RivoRemoteInput] = []
        var state = states[button] ?? ButtonState()
        let supportsDoubleTap =
            doubleTapButtons.contains(button)

        if supportsDoubleTap,
           state.waitingForSecondTap,
           let lastReleasedAt = state.lastReleasedAt,
           time - lastReleasedAt
                <= configuration.doubleTapInterval {
            state.singleTapDeadline = nil
            state.waitingForSecondTap = false
            state.isPressed = true
            state.doubleTapActive = true
            state.supportsDoubleTap = true
            state.rawKey = rawKey
            state.autoReleaseDeadline =
                time + configuration.missingReleaseTimeout
            states[button] = state
            return [
                event(
                    button,
                    action: .doubleTapped,
                    rawKey: rawKey
                )
            ]
        }

        if state.waitingForSecondTap
            || state.releaseDeadline != nil
            || state.isPressed {
            output.append(
                contentsOf: finish(
                    button,
                    state: state
                )
            )
        }

        state = ButtonState()
        state.isPressed = true
        state.supportsDoubleTap = supportsDoubleTap
        state.rawKey = rawKey
        state.longPressDeadline =
            time + configuration.longPressDelay
        state.autoReleaseDeadline =
            time + configuration.missingReleaseTimeout
        if !supportsDoubleTap {
            state.pressDeadline =
                time + configuration.pressDelay
        }
        states[button] = state
        return output
    }

    private mutating func release(
        _ button: RivoButton,
        rawKey: UInt8,
        at time: TimeInterval
    ) -> [RivoRemoteInput] {
        guard var state = states[button],
              state.isPressed
                || state.doubleTapActive else {
            return []
        }

        state.isPressed = false
        state.lastReleasedAt = time
        state.rawKey = rawKey
        state.longPressDeadline = nil
        state.autoReleaseDeadline = nil

        if state.doubleTapActive {
            states.removeValue(forKey: button)
            return [
                event(
                    button,
                    action: .doubleTapEnded,
                    rawKey: rawKey
                )
            ]
        }
        if state.longPressDispatched {
            states.removeValue(forKey: button)
            return [
                event(
                    button,
                    action: .longPressEnded,
                    rawKey: rawKey
                )
            ]
        }
        if state.supportsDoubleTap {
            state.waitingForSecondTap = true
            state.singleTapDeadline =
                time + configuration.doubleTapInterval
        } else {
            state.releaseDeadline =
                time + configuration.releaseDelay
        }
        states[button] = state
        return []
    }

    private mutating func process(
        _ deadline: Deadline
    ) -> [RivoRemoteInput] {
        guard var state = states[deadline.button] else {
            return []
        }

        switch deadline.kind {
        case .press:
            state.pressDeadline = nil
            let output = dispatchPressIfNeeded(
                deadline.button,
                state: &state
            )
            states[deadline.button] = state
            return output

        case .longPress:
            state.longPressDeadline = nil
            guard state.isPressed,
                  !state.doubleTapActive else {
                states[deadline.button] = state
                return []
            }
            var output = dispatchPressIfNeeded(
                deadline.button,
                state: &state
            )
            state.longPressDispatched = true
            output.append(
                event(
                    deadline.button,
                    action: .longPressed,
                    rawKey: state.rawKey
                )
            )
            states[deadline.button] = state
            return output

        case .singleTap:
            guard state.waitingForSecondTap else {
                state.singleTapDeadline = nil
                states[deadline.button] = state
                return []
            }
            states.removeValue(forKey: deadline.button)
            return finish(
                deadline.button,
                state: state
            )

        case .release:
            states.removeValue(forKey: deadline.button)
            return finish(
                deadline.button,
                state: state
            )

        case .autoRelease:
            state.autoReleaseDeadline = nil
            states[deadline.button] = state
            return release(
                deadline.button,
                rawKey: state.rawKey,
                at: deadline.time
            )
        }
    }

    private func finish(
        _ button: RivoButton,
        state originalState: ButtonState
    ) -> [RivoRemoteInput] {
        var state = originalState
        if state.doubleTapActive {
            return [
                event(
                    button,
                    action: .doubleTapEnded,
                    rawKey: state.rawKey
                )
            ]
        }
        if state.longPressDispatched {
            return [
                event(
                    button,
                    action: .longPressEnded,
                    rawKey: state.rawKey
                )
            ]
        }
        var output = dispatchPressIfNeeded(
            button,
            state: &state
        )
        output.append(
            event(
                button,
                action: .released,
                rawKey: state.rawKey
            )
        )
        return output
    }

    private func dispatchPressIfNeeded(
        _ button: RivoButton,
        state: inout ButtonState
    ) -> [RivoRemoteInput] {
        guard !state.pressDispatched else {
            return []
        }
        state.pressDispatched = true
        return [
            event(
                button,
                action: .pressed,
                rawKey: state.rawKey
            )
        ]
    }

    private func nextDueDeadline(
        at time: TimeInterval
    ) -> Deadline? {
        allDeadlines()
            .filter { $0.time <= time }
            .min {
                if $0.time == $1.time {
                    if $0.button == $1.button {
                        return $0.kind.rawValue
                            < $1.kind.rawValue
                    }
                    return $0.button.rawValue
                        < $1.button.rawValue
                }
                return $0.time < $1.time
            }
    }

    private func allDeadlines() -> [Deadline] {
        states.flatMap { button, state in
            [
                state.pressDeadline.map {
                    Deadline(
                        time: $0,
                        button: button,
                        kind: .press
                    )
                },
                state.longPressDeadline.map {
                    Deadline(
                        time: $0,
                        button: button,
                        kind: .longPress
                    )
                },
                state.singleTapDeadline.map {
                    Deadline(
                        time: $0,
                        button: button,
                        kind: .singleTap
                    )
                },
                state.releaseDeadline.map {
                    Deadline(
                        time: $0,
                        button: button,
                        kind: .release
                    )
                },
                state.autoReleaseDeadline.map {
                    Deadline(
                        time: $0,
                        button: button,
                        kind: .autoRelease
                    )
                }
            ].compactMap { $0 }
        }
    }

    private func event(
        _ button: RivoButton,
        action: RivoButtonAction,
        rawKey: UInt8
    ) -> RivoRemoteInput {
        .button(
            button: button,
            action: action,
            rawKey: rawKey
        )
    }
}

@MainActor
final class RivoButtonGestureInterpreter:
    ObservableObject
{
    @Published private(set) var latestBatch:
        [RivoRemoteInput] = []
    @Published private(set) var eventSequence = 0

    private var recognizer =
        RivoButtonGestureRecognizer()
    private var deadlineTask: Task<Void, Never>?

    deinit {
        deadlineTask?.cancel()
    }

    func receive(_ input: RivoRemoteInput) {
        receive([input])
    }

    func receive(_ inputs: [RivoRemoteInput]) {
        guard !inputs.isEmpty else {
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        var interpreted: [RivoRemoteInput] = []
        for input in inputs {
            interpreted.append(
                contentsOf: recognizer.receive(
                    input,
                    at: now
                )
            )
        }
        publish(
            interpreted
        )
        scheduleNextDeadline()
    }

    func releaseAll() {
        deadlineTask?.cancel()
        deadlineTask = nil
        publish(
            recognizer.releaseAll(
                at: ProcessInfo.processInfo.systemUptime
            )
        )
    }

    private func scheduleNextDeadline() {
        deadlineTask?.cancel()
        guard let deadline = recognizer.nextDeadline else {
            deadlineTask = nil
            return
        }
        let delay = max(
            deadline
                - ProcessInfo.processInfo.systemUptime,
            0
        )
        deadlineTask = Task { [weak self] in
            try? await Task.sleep(
                nanoseconds: UInt64(
                    delay * 1_000_000_000
                )
            )
            guard !Task.isCancelled,
                  let self else {
                return
            }
            self.publish(
                self.recognizer.advance(
                    to: ProcessInfo.processInfo.systemUptime
                )
            )
            self.scheduleNextDeadline()
        }
    }

    private func publish(
        _ inputs: [RivoRemoteInput]
    ) {
        guard !inputs.isEmpty else {
            return
        }
        latestBatch = inputs
        eventSequence &+= 1
    }
}
