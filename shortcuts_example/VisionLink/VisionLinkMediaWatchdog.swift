import Foundation

nonisolated struct VisionLinkMediaWatchdog:
    Equatable,
    Sendable
{
    enum Phase: Equatable, Sendable {
        case idle
        case waitingForOffer(deadline: TimeInterval)
        case waitingForFirstFrame(deadline: TimeInterval)
        case receiving(deadline: TimeInterval)
    }

    enum Timeout: Equatable, Sendable {
        case offer
        case firstFrame
        case stalledFrame
    }

    static let offerTimeout: TimeInterval = 8
    static let firstFrameTimeout: TimeInterval = 5
    static let stalledFrameTimeout: TimeInterval = 5

    private(set) var phase: Phase = .idle

    mutating func waitForOffer(
        at now: TimeInterval,
        timeout: TimeInterval = offerTimeout
    ) {
        phase = .waitingForOffer(
            deadline: now + max(timeout, 0)
        )
    }

    mutating func waitForFirstFrame(
        at now: TimeInterval,
        timeout: TimeInterval = firstFrameTimeout
    ) {
        phase = .waitingForFirstFrame(
            deadline: now + max(timeout, 0)
        )
    }

    @discardableResult
    mutating func receiveFrame(
        at now: TimeInterval,
        stallTimeout: TimeInterval =
            stalledFrameTimeout
    ) -> Bool {
        let isFirstFrame: Bool
        switch phase {
        case .receiving:
            isFirstFrame = false
        case .idle,
             .waitingForOffer,
             .waitingForFirstFrame:
            isFirstFrame = true
        }
        phase = .receiving(
            deadline:
                now + max(stallTimeout, 0)
        )
        return isFirstFrame
    }

    mutating func stop() {
        phase = .idle
    }

    func remainingTime(
        at now: TimeInterval
    ) -> TimeInterval? {
        guard let deadline else {
            return nil
        }
        return max(deadline - now, 0)
    }

    mutating func consumeTimeout(
        at now: TimeInterval
    ) -> Timeout? {
        let timeout: Timeout
        switch phase {
        case .idle:
            return nil
        case .waitingForOffer(let deadline):
            guard now >= deadline else {
                return nil
            }
            timeout = .offer
        case .waitingForFirstFrame(
            let deadline
        ):
            guard now >= deadline else {
                return nil
            }
            timeout = .firstFrame
        case .receiving(let deadline):
            guard now >= deadline else {
                return nil
            }
            timeout = .stalledFrame
        }
        phase = .idle
        return timeout
    }

    private var deadline: TimeInterval? {
        switch phase {
        case .idle:
            return nil
        case .waitingForOffer(let deadline),
             .waitingForFirstFrame(
                let deadline
             ),
             .receiving(let deadline):
            return deadline
        }
    }
}
