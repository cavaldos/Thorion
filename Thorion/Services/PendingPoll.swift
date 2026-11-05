import Foundation

/// Remembers when the next delayed SMC read is due.
///
/// A request for a later time than the one already pending is ignored. Without that, every
/// request restarted the countdown, and requests arrive in runs: the adapter reports itself
/// gone for a moment whenever charging starts or stops, and each blip triggers another
/// evaluation. The read after a change kept slipping by several seconds, so the status lagged.
struct PendingPoll {
    private(set) var deadline: ContinuousClock.Instant?

    /// Returns whether a read has to be scheduled for `newDeadline`. When it returns false,
    /// a read that is due sooner is already waiting.
    mutating func request(at newDeadline: ContinuousClock.Instant) -> Bool {
        if let deadline, deadline <= newDeadline {
            return false
        }
        deadline = newDeadline
        return true
    }

    /// Call when the pending read has started, or was cancelled.
    mutating func clear() {
        deadline = nil
    }
}
