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

@Test func waitsOutTheRestOfTheMinute() {
    let now = Date(timeIntervalSince1970: 10_000)
    #expect(PollSchedule.wait(lastAttempt: nil, now: now) == .zero)
    #expect(PollSchedule.wait(lastAttempt: now.addingTimeInterval(-61), now: now) == .zero)
    #expect(PollSchedule.wait(lastAttempt: now.addingTimeInterval(-60), now: now) == .zero)
    #expect(PollSchedule.wait(lastAttempt: now.addingTimeInterval(-20), now: now) == .seconds(40))
    #expect(PollSchedule.wait(lastAttempt: now, now: now) == .seconds(60))
}

@Test func restoredAttemptIsNeverInTheFuture() {
    let now = Date(timeIntervalSince1970: 10_000)
    #expect(PollSchedule.restoredLastAttempt(nil, now: now) == nil)
    #expect(PollSchedule.restoredLastAttempt(now.addingTimeInterval(-30), now: now) == now.addingTimeInterval(-30))
    // The clock moved back after the last launch: wait one minute from now, not until the clock catches up.
    #expect(PollSchedule.restoredLastAttempt(now.addingTimeInterval(3600), now: now) == now)
}
