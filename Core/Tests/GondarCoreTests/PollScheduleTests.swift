import Foundation
import Testing

@testable import GondarCore

@Test func backsOffAfterFailures() {
    func delay(_ failures: Int) -> Duration {
        PollSchedule(failures: failures).nextDelay(retryAfter: nil)
    }
    #expect(delay(0) == .seconds(300))
    #expect(delay(1) == .seconds(240))
    #expect(delay(2) == .seconds(480))
    #expect(delay(3) == .seconds(960))
    #expect(delay(4) == .seconds(1800))
    #expect(delay(10) == .seconds(1800))
    #expect(delay(70) == .seconds(1800))
}

@Test func honoursRetryAfterButNeverBelowTheBackoff() {
    #expect(PollSchedule(failures: 0).nextDelay(retryAfter: .seconds(900)) == .seconds(900))
    #expect(PollSchedule(failures: 0).nextDelay(retryAfter: .seconds(5)) == .seconds(300))
    #expect(PollSchedule(failures: 2).nextDelay(retryAfter: .seconds(5)) == .seconds(480))
    #expect(PollSchedule(failures: 1).nextDelay(retryAfter: .seconds(600)) == .seconds(600))
    #expect(PollSchedule(failures: 4).nextDelay(retryAfter: .seconds(300)) == .seconds(1800))
}

/// The live endpoint answers 429 with `retry-after: 0`; that must not turn into a poll every minute.
@Test func zeroRetryAfterStillBacksOff() {
    #expect(PollSchedule(failures: 0).nextDelay(retryAfter: .zero) == .seconds(300))
    #expect(PollSchedule(failures: 2).nextDelay(retryAfter: .zero) == .seconds(480))
    #expect(PollSchedule(failures: 10).nextDelay(retryAfter: .zero) == .seconds(1800))
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

@Test func viewerPollsOnlyOutsideBackoff() {
    #expect(PollSchedule(failures: 0).pollsWhenViewed)
    #expect(!PollSchedule(failures: 1).pollsWhenViewed)
}

/// A refused login waits the plain interval and is not counted as a failure: the fix is Claude Code writing a new token.
@Test func unauthorizedDoesNotEscalate() {
    var schedule = PollSchedule(failures: 0)
    let delays = (0..<3).map { _ in schedule.delay(after: .unauthorized, retryAfter: nil) }
    #expect(delays == [.seconds(120), .seconds(120), .seconds(120)])
    #expect(schedule.failures == 0)
}

@Test func otherProblemsCountAsFailures() {
    var schedule = PollSchedule(failures: 0)
    let offline = schedule.delay(after: .offline, retryAfter: nil)
    #expect(offline == .seconds(240) && schedule.failures == 1)
    let limited = schedule.delay(after: .rateLimited, retryAfter: .seconds(900))
    #expect(limited == .seconds(900) && schedule.failures == 2)
    let pending = schedule.delay(after: .accountSwitchPending, retryAfter: nil)
    #expect(pending == .seconds(960) && schedule.failures == 3)
}

/// The timings decoupled from the regular interval (2026-10-20), each with its explicit value.
@Test func decoupledTimingsHaveTheirOwnValues() {
    #expect(PollSchedule.interval == .seconds(300))
    #expect(PollSchedule.backoffBase == .seconds(120))
    #expect(PollSchedule.staleBackstop == .seconds(360))
    #expect(PollSchedule.tokenRecheck == .seconds(120))
    #expect(Display.staleAfter == .seconds(360))
}

/// The backstop must outlast the regular check, or numbers flash stale just before each answer.
@Test func staleBackstopOutlastsTheRegularInterval() {
    #expect(PollSchedule.staleBackstop > PollSchedule.interval)
}
