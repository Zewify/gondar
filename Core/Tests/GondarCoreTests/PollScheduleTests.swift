import Foundation
import Testing

@testable import GondarCore

@Test func backsOffAfterFailures() {
    func delay(_ failures: Int) -> Duration {
        PollSchedule(failures: failures).nextDelay(retryAfter: nil)
    }
    #expect(delay(0) == .seconds(120))
    #expect(delay(1) == .seconds(240))
    #expect(delay(3) == .seconds(960))
    #expect(delay(10) == .seconds(1800))
    #expect(delay(70) == .seconds(1800))
}

@Test func honoursRetryAfterButNotBelowMinimum() {
    let schedule = PollSchedule(failures: 0)
    #expect(schedule.nextDelay(retryAfter: .seconds(300)) == .seconds(300))
    #expect(schedule.nextDelay(retryAfter: .seconds(5)) == .seconds(60))
}

@Test func refusesPollWithinAMinute() {
    let now = Date(timeIntervalSince1970: 10_000)
    #expect(!PollSchedule.mayPollNow(lastAttempt: now.addingTimeInterval(-30), now: now))
    #expect(PollSchedule.mayPollNow(lastAttempt: now.addingTimeInterval(-61), now: now))
    #expect(PollSchedule.mayPollNow(lastAttempt: nil, now: now))
}
