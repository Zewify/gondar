import AppKit
import CryptoKit
import GondarCore
import Observation
import os

/// Everything the menu bar and panel show: Claude Code's usage, for whichever account it is signed in to.
///
/// The numbers come from two places, merged by `SnapshotMerge` whenever either changes: the usage API, and
/// Claude Code's status line feed (`statusline.json`, written by `gondar-feed`). While the feed is fresh the numbers are live,
/// and the API is asked only every 15 minutes, for the limits the feed lacks and for the account check.
/// The feed names no account, so it counts only when it arrived after the last account change; launch counts as one,
/// since Gondar cannot know what changed while it was not running. The last numbers shown are saved to `last.json`
/// and shown at the next launch, marked as restored, until the first live or API result.
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

    /// What the menu bar and the header show: the state, with numbers that stopped updating shown as stale.
    var display: Display { state.display.presented(now: now) }
    var menuBarText: String { display.menuBarText }
    var menuBarTone: MenuBarTone { display.menuBarTone }
    var menuBarAccessibilityLabel: String { display.menuBarAccessibilityLabel }

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
    @ObservationIgnored private var feedWatcher: FeedWatcher?
    @ObservationIgnored private var workspaceTokens: [NSObjectProtocol] = []
    @ObservationIgnored private var isAsleep = false
    /// A SHA-256 of the last token checked against the profile endpoint, held in memory only.
    @ObservationIgnored private var tokenFingerprint: SHA256.Digest?
    /// A SHA-256 of a token Anthropic refused (401). The API is not asked again until Claude Code writes another one.
    @ObservationIgnored private var refusedToken: SHA256.Digest?
    @ObservationIgnored private var profile: Profile?
    /// The last account `~/.claude.json` named; nil only until the file has been read successfully.
    /// The one place the app tracks it: the watcher reports reads and this decides what is a switch.
    @ObservationIgnored private var localAccount: LocalAccount?
    @ObservationIgnored private var mismatch = AccountMismatch()
    /// The plan worked out when `profile` was fetched, with the Keychain's tier as a fallback.
    @ObservationIgnored private var profilePlan: String?
    /// The header fields `~/.claude.json` gives, shown until the profile endpoint confirms them.
    @ObservationIgnored private var localProfile: Profile?
    /// The API's last result and failure, the feed, and the account they belong to (see `UsageSources`).
    @ObservationIgnored private var sources = UsageSources(now: Date())
    /// Whether the numbers shown include fresh feed entries.
    @ObservationIgnored private var isLive = false
    /// `slowedByFeed` as of the last publish, so the next poll moves only when it changes.
    @ObservationIgnored private var wasSlowed = false
    @ObservationIgnored private var liveExpiry: Task<Void, Never>?
    /// The numbers `last.json` holds and when they were written: rewritten when the limits change, otherwise at most once a minute.
    @ObservationIgnored private var lastSaved: (account: AccountKey, report: UsageReport, at: Date)?

    private static let logger = Logger(subsystem: "com.zewify.gondar", category: "usage")

    func start() {
        guard ticker == nil else { return }
        #if DEBUG
        // A Debug-only demo: fixed numbers, never a poll (`poll` refuses too), so the countdowns stand still.
        if DemoMode.isEnabled {
            if let demo = DemoMode.state(now: now) { state = demo }
            return
        }
        #endif
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

        let center = NSWorkspace.shared.notificationCenter
        workspaceTokens.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.willSleep() }
        })
        workspaceTokens.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.didWake() }
        })

        Task { [weak self] in
            let file = await AccountFileWatcher.read()
            guard let self else { return }
            if let file {
                self.localAccount = file.account
                self.localProfile = file.profile
                self.setAccount(file.account.key)
                self.restoreLastSnapshot()
            }
            // Started after the first read, so that read is the baseline and only later writes can be a switch.
            let watcher = AccountFileWatcher { [weak self] file in self?.accountFileChanged(file) }
            watcher.start()
            self.watcher = watcher
            // Read before watching, with the modification date taken first, so the watcher reports any write after it.
            let baseline = FeedWatcher.modificationDate()
            self.sources.feed = await FeedWatcher.read()
            let feedWatcher = FeedWatcher { [weak self] feed in self?.feedChanged(feed) }
            feedWatcher.start(baseline: baseline)
            self.feedWatcher = feedWatcher
            self.publish()
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
    /// Not while the feed keeps the numbers live either: then the API is asked every 15 minutes at most.
    func viewerAppeared() {
        guard schedule.pollsWhenViewed, !slowedByFeed else { return }
        poll()
    }

    // MARK: Polling

    /// Starts a poll unless one is running or the last attempt was under a minute ago.
    /// `afterAccountChange` is the one bypass of both: a switch must show within seconds.
    private func poll(afterAccountChange: Bool = false) {
        guard !isAsleep else { return }
        #if DEBUG
        guard !DemoMode.isEnabled else { return }
        #endif
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
            setAccount(nil)
            publish()
            return PollSchedule.interval
        case .failed:
            // Not the same as signed out: keep the account and its numbers, marked stale.
            Self.logger.error("Couldn't read Claude Code's login from the Keychain")
            apiFailed(.keychainUnreadable)
            return PollSchedule.interval
        }

        guard let credentials = try? ClaudeCodeCredentials.parse(keychainValue: keychainValue) else {
            Self.logger.error("Claude Code's login is not in the expected shape")
            apiFailed(.keychainUnreadable)
            return PollSchedule.interval
        }
        if credentials.isExpired(at: Date()) {
            // Not counted as a failure: Claude Code refreshes the token when it next runs, and the next poll reads it again.
            apiFailed(.tokenExpired)
            return PollSchedule.interval
        }

        let fingerprint = SHA256.hash(data: Data(credentials.accessToken.utf8))
        if fingerprint == refusedToken {
            // Refused before: only a new token from Claude Code can fix that, so read the Keychain each interval and ask nothing.
            apiFailed(.unauthorized)
            return PollSchedule.interval
        }
        refusedToken = nil
        if fingerprint != tokenFingerprint || profile == nil {
            switch await client.profile(token: credentials.accessToken) {
            case .success(let fetched):
                guard isCurrent() else { return nil }
                if let local = localAccount, local.key != fetched.accountKey {
                    // The watcher may not have caught up; read the file once before deciding.
                    let fresh = await AccountFileWatcher.read()
                    guard isCurrent() else { return nil }
                    if let fresh {
                        // A switch the watcher has not reported yet is still a switch: the old account's numbers go,
                        // and feed data from before it is ignored, so it never shows under the wrong header.
                        let switched = fresh.account != localAccount
                        localAccount = fresh.account
                        localProfile = fresh.profile
                        if switched {
                            setAccount(fresh.account.key)
                            publish()
                        }
                    }
                    if let fresh, fresh.account.key != fetched.accountKey {
                        // A switch half done: the token and the file name different accounts. Keep what is shown and look again,
                        // twice; a third disagreement in a row is reported and backs off, so it never looks current or polls every minute.
                        Self.logger.info("The token and the account file disagree; waiting")
                        guard mismatch.disagreed() else { return PollSchedule.minimumGap }
                        apiFailed(.accountSwitchPending)
                        return schedule.delay(after: .accountSwitchPending, retryAfter: nil)
                    }
                }
                mismatch.agreed()
                tokenFingerprint = fingerprint
                profile = fetched
                profilePlan = PlanText.label(
                    organizationType: fetched.organizationType, rateLimitTier: fetched.rateLimitTier ?? credentials.rateLimitTier
                )
                setAccount(fetched.accountKey)
            case .failure(let error):
                guard isCurrent() else { return nil }
                return record(error, token: fingerprint)
            }
        }
        guard let profileForThisPoll = profile else { return PollSchedule.interval }

        let result = await client.usage(token: credentials.accessToken)
        guard isCurrent() else { return nil }
        switch result {
        case .success(let report):
            sources.apiAnswered(Snapshot(profile: profileForThisPoll, plan: profilePlan, report: report, fetchedAt: Date(), source: .claudeCode))
            schedule.failures = 0
            publish()
            return cadence
        case .failure(let error):
            return record(error, token: fingerprint)
        }
    }

    /// A refused token is remembered (as its fingerprint) and not counted as a failure; anything else backs off.
    private func record(_ error: FetchError, token fingerprint: SHA256.Digest) -> Duration {
        Self.logger.notice("A request failed: \(String(describing: error.problem), privacy: .public)")
        apiFailed(error.problem)
        if error.problem == .unauthorized { refusedToken = fingerprint }
        return schedule.delay(after: error.problem, retryAfter: error.retryAfter)
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

    /// The wait after a successful poll: 15 minutes while the feed keeps the numbers live, the usual schedule otherwise.
    private var cadence: Duration {
        slowedByFeed ? PollSchedule.feedInterval : schedule.nextDelay(retryAfter: nil)
    }

    /// The feed is live and the API has answered for this account, so it is asked only for what the feed lacks.
    private var slowedByFeed: Bool { isLive && sources.api != nil }

    /// When the feed starts or stops slowing the API, the scheduled poll moves to the new cadence, counted from the last attempt:
    /// a feed gone quiet brings the usual schedule back at once rather than after the rest of 15 minutes.
    /// Only a plain scheduled poll moves; a running poll or a backoff after a failure is left alone.
    private func cadenceChanged() {
        guard pollTask == nil, nextPoll != nil, schedule.failures == 0, !isAsleep, let lastAttempt else { return }
        let elapsed = Date().timeIntervalSince(lastAttempt)
        let wait = max(0, Double(cadence.components.seconds) - elapsed)
        schedulePoll(after: .milliseconds(Int64(wait * 1000)))
    }

    // MARK: Showing the numbers

    /// Recomputes what is shown from the API's last result and the feed, then saves it for the next launch.
    /// A failure the API reported marks the numbers stale only while they are not live: live numbers are current whatever the API says.
    private func publish() {
        let current = Date()
        now = current
        let confirmed = profile.map { (profile: $0, plan: profilePlan) }
        let shown = sources.snapshot(confirmed: confirmed, local: localProfile, now: current)
        if let shown {
            state.received(shown)
            if !shown.live, let problem = sources.apiProblem { state.failed(problem) }
            save(shown, at: current)
        } else if let problem = sources.apiProblem {
            state.failed(problem)
        }

        let live = shown?.live ?? false
        liveExpiry?.cancel()
        liveExpiry = nil
        if let expiry = sources.nextExpiry(now: current) {
            // Shown again as a feed entry turns quiet, so the source line, the staleness and the cadence follow at once.
            let left = expiry.timeIntervalSince(current) + 1
            liveExpiry = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(Int64(max(left, 1) * 1000)))
                guard !Task.isCancelled, let self else { return }
                self.liveExpiry = nil
                self.publish()
            }
        }
        isLive = live
        // Only a change in whether the feed slows the API moves the next poll: numbers that turn live before the API has
        // answered once must not push back the first poll.
        if slowedByFeed != wasSlowed {
            wasSlowed = slowedByFeed
            cadenceChanged()
        }
    }

    private func apiFailed(_ problem: Problem) {
        sources.apiFailed(problem)
        publish()
    }

    private func feedChanged(_ feed: FeedSnapshot?) {
        sources.feed = feed
        publish()
    }

    /// Shows the numbers the last launch saved, marked as restored, when they belong to the account `~/.claude.json` names.
    /// The header is `~/.claude.json`'s for that account; no profile has been fetched yet at launch.
    private func restoreLastSnapshot() {
        guard let account = state.account, let localProfile, localProfile.accountKey == account,
            let data = try? Data(contentsOf: GondarFolder.lastURL),
            let saved = SavedSnapshot.restore(saved: data, currentAccount: account)
        else { return }
        lastSaved = (account, saved.report, Date())
        state.restore(Snapshot(
            profile: localProfile,
            plan: PlanText.label(organizationType: localProfile.organizationType, rateLimitTier: localProfile.rateLimitTier),
            report: saved.report, fetchedAt: saved.fetchedAt, source: .claudeCode
        ))
    }

    /// Writes `last.json` (IDs, limits and a time; owner-only) when the limits changed, otherwise at most once a minute,
    /// since live numbers republish on every status line refresh.
    private func save(_ shown: Snapshot, at time: Date) {
        guard let account = state.account else { return }
        if let lastSaved, lastSaved.account == account, lastSaved.report == shown.report, time.timeIntervalSince(lastSaved.at) < 60 { return }
        GondarFolder.create()
        if GondarFolder.writeAtomically(SavedSnapshot.encode(snapshot: shown, accountKey: account), to: GondarFolder.lastURL) {
            lastSaved = (account, shown.report, time)
        } else {
            Self.logger.error("Couldn't save the last numbers")
        }
    }

    // MARK: Account changes, sleep and wake

    /// Follows a different account (or none): `UsageSources` drops the previous account's API result and failure and ignores
    /// feed data from before now. The same account again changes nothing.
    private func setAccount(_ key: AccountKey?) {
        sources.follow(key, at: Date())
        state.accountChanged(to: key)
    }

    /// Only a real pair that differs from the last real pair is a switch; a file briefly missing or
    /// half-written (nil) is not, and must not bypass the one-minute floor.
    private func accountFileChanged(_ file: AccountFile?) {
        guard let file else { return }
        guard file.account != localAccount else {
            // Claude Code rewrites the file all the time; the header fields may still have changed.
            localProfile = file.profile
            publish()
            return
        }
        tokenFingerprint = nil
        localAccount = file.account
        localProfile = file.profile
        // Drop the previous account's numbers at once; the poll fills in the new one's.
        setAccount(file.account.key)
        publish()
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
        publish()
        pollOrWait()
    }
}
