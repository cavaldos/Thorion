import Testing

@testable import thorion

@MainActor
struct PendingPollTests {
    private let now = ContinuousClock.now

    @Test func theFirstRequestIsScheduled() {
        var poll = PendingPoll()
        let scheduled = poll.request(at: now + .seconds(3))
        #expect(scheduled)
    }

    /// The bug: every request restarted the countdown, so a run of requests (one per adapter
    /// blip after charging changed) pushed the read back by several seconds.
    @Test func aLaterRequestDoesNotPostponeTheReadAlreadyWaiting() {
        var poll = PendingPoll()
        let first = poll.request(at: now + .seconds(3))
        #expect(first)

        for offset in [1, 2, 4, 6] {
            let scheduled = poll.request(at: now + .seconds(3 + offset))
            #expect(!scheduled)
        }
        #expect(poll.deadline == now + .seconds(3))
    }

    @Test func aSoonerRequestReplacesTheReadAlreadyWaiting() {
        var poll = PendingPoll()
        _ = poll.request(at: now + .seconds(3))

        let scheduled = poll.request(at: now + .milliseconds(200))
        #expect(scheduled)
        #expect(poll.deadline == now + .milliseconds(200))
    }

    @Test func aRequestForTheSameTimeIsAlreadyCovered() {
        var poll = PendingPoll()
        _ = poll.request(at: now + .seconds(3))

        let scheduled = poll.request(at: now + .seconds(3))
        #expect(!scheduled)
    }

    @Test func onceTheReadHasStartedTheNextRequestIsScheduled() {
        var poll = PendingPoll()
        _ = poll.request(at: now + .seconds(3))
        poll.clear()
        #expect(poll.deadline == nil)

        let scheduled = poll.request(at: now + .seconds(9))
        #expect(scheduled)
    }
}
