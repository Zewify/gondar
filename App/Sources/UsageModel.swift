import AppKit
import CryptoKit
import GondarCore
import Observation
import os

/// Everything the menu bar and panel show: Claude Code's usage, for whichever account it is signed in to.
///
/// Polls run one at a time. A poll asked for while one runs is dropped, except after an account change,
/// which cancels the running poll and bumps `generation`, so that anything the old poll learns late,
/// success or failure, is thrown away rather than shown under the new account.
@MainActor
@Observable
final class UsageModel {
    private(set) var state = UsageState()
    /// Ticks every 30 seconds, so countdowns move between polls.
    private(set) var now = Date()
    /// Mirrors `PollSchedule.mayPollNow`: false within a minute of the last poll.
    private(set) var canRefresh = true

    var sessionLimit: UsageLimit? { state.display.sessionLimit }
    var menuBarText: String { state.display.menuBarText }
    var menuBarTone: MenuBarTone { state.display.menuBarTone }
    var menuBarAccessibilityLabel: String { state.display.menuBarAccessibilityLabel }

    @ObservationIgnored private let client = AnthropicClient()
    @ObservationIgnored private var schedule = PollSchedule()
    /// Saved as a timestamp (never anything secret), so a relaunch keeps the one-minute floor.
    @ObservationIgnored private var lastAttempt: Date? = PollSchedule.restoredLastAttempt(
        UserDefaults.standard.object(forKey: UsageModel.lastAttemptKey) as? Date, now: Date()
    ) {
        didSet { UserDefaults.standard.set(lastAttempt, forKey: Self.lastAttemptKey) }
    }
    private static let lastAttemptKey = "lastPollAttempt"
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var nextPoll: Task<Void, Never>?
    @ObservationIgnored private var refreshGate: Task<Void, Never>?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var watcher: AccountFileWatcher?
    @ObservationIgnored private var workspaceTokens: [NSObjectProtocol] = []
    @ObservationIgnored private var isAsleep = false
    @ObservationIgnored private var viewers = 0
    /// A SHA-256 of the last token checked against the profile endpoint, held in memory only.
    @ObservationIgnored private var tokenFingerprint: SHA256.Digest?
    @ObservationIgnored private var profile: Profile?
    /// The last account `~/.claude.json` named; nil only until the file has been read successfully.
    @ObservationIgnored private var localAccount: LocalAccount?

    private static let logger = Logger(subsystem: "com.zewify.gondar", category: "usage")

    func start() {
        guard ticker == nil else { return }
        // A restored attempt under a minute old keeps Refresh disabled until the minute is up.
        updateCanRefresh()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self else { return }
                self.now = Date()
                self.updateCanRefresh()
            }
        }

        let watcher = AccountFileWatcher { [weak self] account in self?.accountFileChanged(account) }
        watcher.start()
        self.watcher = watcher

        let center = NSWorkspace.shared.notificationCenter
        workspaceTokens.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.willSleep() }
        })
        workspaceTokens.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.didWake() }
        })

        Task { [weak self] in
            let account = await AccountFileWatcher.read()
            guard let self else { return }
            if let account { self.localAccount = account }
            // A relaunch within a minute of the last poll waits out the rest of it.
            self.pollOrWait()
        }
    }

    /// A refresh the person asks for; dropped within a minute of the last poll.
    func refresh() {
        poll()
    }

    /// The panel or the floating window opened: poll once, unless the last poll was under a minute ago.
    /// Not while backing off after a failure: the scheduled retry handles that, and an extra request would prolong a rate limit.
    func viewerAppeared() {
        viewers += 1
        guard schedule.pollsWhenViewed else { return }
        poll()
    }

    /// Kept for symmetry with the window controller; polling does not depend on it.
    func viewerDisappeared() {
        viewers = max(0, viewers - 1)
    }

    // MARK: Polling

    /// Starts a poll unless one is running or the last attempt was under a minute ago.
    /// `afterAccountChange` is the one bypass of both: a switch must show within seconds.
    private func poll(afterAccountChange: Bool = false) {
        guard !isAsleep else { return }
        if afterAccountChange {
            pollTask?.cancel()
            pollTask = nil
        } else {
            guard pollTask == nil, PollSchedule.mayPollNow(lastAttempt: lastAttempt, now: Date()) else { return }
        }
        nextPoll?.cancel()
        nextPoll = nil
        generation += 1
        let pollGeneration = generation
        pollTask = Task { [weak self] in
            guard let self else { return }
            let delay = await self.cycle(generation: pollGeneration)
            // A superseded poll leaves the task, the timer and the state to the poll that replaced it.
            guard pollGeneration == self.generation, let delay else { return }
            self.pollTask = nil
            self.schedulePoll(after: delay)
        }
    }

    /// One poll. Returns how long to wait before the next, or nil when a newer poll superseded this one.
    /// Every await is followed by a generation check before anything is written.
    private func cycle(generation pollGeneration: Int) async -> Duration? {
        func isCurrent() -> Bool { pollGeneration == generation && !Task.isCancelled }

        lastAttempt = Date()
        updateCanRefresh()
        Self.logger.notice("Polling usage")

        let keychainValue: String
        let read = await CredentialReader.read()
        guard isCurrent() else { return nil }
        switch read {
        case .item(let value):
            keychainValue = value
        case .noItem:
            tokenFingerprint = nil
            profile = nil
            state.accountChanged(to: nil)
            return PollSchedule.interval
        case .failed:
            // Not the same as signed out: keep the account and its numbers, marked stale.
            Self.logger.error("Couldn't read Claude Code's login from the Keychain")
            state.failed(.keychainUnreadable)
            return PollSchedule.interval
        }

        guard let credentials = try? ClaudeCodeCredentials.parse(keychainValue: keychainValue) else {
            Self.logger.error("Claude Code's login is not in the expected shape")
            state.failed(.keychainUnreadable)
            return PollSchedule.interval
        }
        if credentials.isExpired(at: Date()) {
            // Not counted as a failure: Claude Code refreshes the token when it next runs, and the next poll reads it again.
            state.failed(.tokenExpired)
            return PollSchedule.interval
        }

        let fingerprint = SHA256.hash(data: Data(credentials.accessToken.utf8))
        if fingerprint != tokenFingerprint || profile == nil {
            switch await client.profile(token: credentials.accessToken) {
            case .success(let fetched):
                guard isCurrent() else { return nil }
                if let local = localAccount, local.key != fetched.accountKey {
                    // The watcher may not have caught up; read the file once before deciding.
                    let fresh = await AccountFileWatcher.read()
                    guard isCurrent() else { return nil }
                    if let fresh { localAccount = fresh }
                    if let fresh, fresh.key != fetched.accountKey {
                        // A switch half done: the token and the file name different accounts. Keep what is shown and look again.
                        Self.logger.info("The token and the account file disagree; waiting")
                        return PollSchedule.minimumGap
                    }
                }
                tokenFingerprint = fingerprint
                profile = fetched
                state.accountChanged(to: fetched.accountKey)
            case .failure(let error):
                guard isCurrent() else { return nil }
                return record(error)
            }
        }
        guard let profileForThisPoll = profile else { return PollSchedule.interval }

        let result = await client.usage(token: credentials.accessToken)
        guard isCurrent() else { return nil }
        switch result {
        case .success(let report):
            let fetchedAt = Date()
            now = fetchedAt
            state.received(Snapshot(
                profile: profileForThisPoll,
                plan: PlanText.label(
                    organizationType: profileForThisPoll.organizationType,
                    rateLimitTier: profileForThisPoll.rateLimitTier ?? credentials.rateLimitTier
                ),
                report: report,
                fetchedAt: fetchedAt,
                source: .claudeCode
            ))
            schedule.failures = 0
            return schedule.nextDelay(retryAfter: nil)
        case .failure(let error):
            return record(error)
        }
    }

    private func record(_ error: FetchError) -> Duration {
        Self.logger.notice("A request failed: \(String(describing: error.problem), privacy: .public)")
        state.failed(error.problem)
        schedule.failures += 1
        return schedule.nextDelay(retryAfter: error.retryAfter)
    }

    private func schedulePoll(after delay: Duration) {
        nextPoll?.cancel()
        nextPoll = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.nextPoll = nil
            self.pollOrWait()
        }
    }

    /// Polls now if the minute since the last attempt has passed, otherwise when it does.
    private func pollOrWait() {
        let wait = PollSchedule.wait(lastAttempt: lastAttempt, now: Date())
        if wait > .zero {
            schedulePoll(after: max(wait, .seconds(1)))
        } else {
            poll()
        }
    }

    private func updateCanRefresh() {
        canRefresh = PollSchedule.mayPollNow(lastAttempt: lastAttempt, now: Date())
        refreshGate?.cancel()
        refreshGate = nil
        guard !canRefresh else { return }
        let remaining = PollSchedule.wait(lastAttempt: lastAttempt, now: Date())
        refreshGate = Task { [weak self] in
            try? await Task.sleep(for: remaining)
            guard !Task.isCancelled, let self else { return }
            self.refreshGate = nil
            self.canRefresh = PollSchedule.mayPollNow(lastAttempt: self.lastAttempt, now: Date())
        }
    }

    // MARK: Account changes, sleep and wake

    /// Only a real pair that differs from the last real pair is a switch; a file briefly missing or
    /// half-written (nil) is not, and must not bypass the one-minute floor.
    private func accountFileChanged(_ account: LocalAccount?) {
        guard let account, account != localAccount else { return }
        tokenFingerprint = nil
        localAccount = account
        // Drop the previous account's numbers at once; the poll fills in the new one's.
        state.accountChanged(to: account.key)
        poll(afterAccountChange: true)
    }

    private func willSleep() {
        isAsleep = true
        generation += 1
        pollTask?.cancel()
        pollTask = nil
        nextPoll?.cancel()
        nextPoll = nil
    }

    private func didWake() {
        isAsleep = false
        now = Date()
        pollOrWait()
    }
}
