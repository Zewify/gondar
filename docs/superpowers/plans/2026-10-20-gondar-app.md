# Gondar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Mac menu bar app with an always-on-top floating window that shows the signed-in Claude account's usage limits and when each resets.

**Architecture:** A `GondarCore` Swift package holds every rule as pure, tested code: parsing Claude Code's credentials and account file, parsing the usage and profile responses, the display state across account switches and failures, the poll schedule, and all text formatting.
`App/` is a thin SwiftUI shell copied in shape from PortGlimpse: it runs `/usr/bin/security`, makes the HTTP calls, watches `~/.claude.json`, and draws the menu bar label, the panel and the floating window.
The claude.ai sign-in (source 2) comes last, after its endpoint has been measured with a real sign-in.

**Tech Stack:** Swift 6, SwiftUI, AppKit where SwiftUI can't (floating window, status item), XcodeGen, Swift Testing, macOS 14+.

**Spec:** `docs/superpowers/specs/2026-10-20-gondar-design.md` (read it first; its fixtures are in `docs/superpowers/specs/fixtures/`).

**Reference project:** the PortGlimpse repo (read-only).
Several tasks say "copy X from PortGlimpse": copy the file, rename `PortGlimpse` to `Gondar` and `portglimpse` to `gondar`, and drop what the task says to drop.

**Out of this plan:** the real name, the public repo, the release workflow, `scripts/install.sh`, and the zewify.com pages.
They wait for the real name; a later plan covers them by copying PortGlimpse's.

## Global Constraints

- macOS 14.0 deployment target, `SWIFT_VERSION` 6.0, bundle ID `com.zewify.gondar`, `LSUIElement` true (no Dock icon), not sandboxed, hardened runtime on, ad hoc signed (`CODE_SIGN_IDENTITY = -`).
- `GondarCore` imports Foundation only — never AppKit, SwiftUI, Security or WebKit.
- The app name and every visible string must not contain "Claude" as part of the product's name; "Claude Code" and "claude.ai" may be named as sources.
- Nothing in the app, repo, commits or docs may identify the person who builds it; commits use the repo's configured author `Zewify <dev@zewify.com>` and carry no co-author or session trailers.
- Access tokens, refresh tokens and cookies are never logged, written to disk or `UserDefaults`, or sent anywhere but `api.anthropic.com` and `claude.ai`.
- The app never refreshes Claude Code's token and never writes to the Keychain or `~/.claude.json`.
- Colours exactly as PortGlimpse's `Theme.swift`: page `#16130F`, panel `#201B17`, raised `#2A241F`, footer `#1B1714`, text `#F6EDE3`, soft text `#D8CBBD`, muted `#A8998A`, lines `#342C25` / `#4A3F35`, amber `#F48E48`, amber face `#FFB067 → #EE8237`, on amber `#1B1815`, amber tint `#2C211A` / `#4D3424`, cap `#2E2721`. Dark appearance only.
- Fonts as PortGlimpse: Bricolage Grotesque (titles), Figtree (body), IBM Plex Mono (numbers), with their OFL licence files.
- Request headers for both Anthropic endpoints: `Authorization: Bearer <token>`, `anthropic-beta: oauth-2025-04-20`, `User-Agent: Gondar/<version>`.
- Poll every 120 seconds; never more often than once per 60 seconds, including refreshes the person asks for.
- `./scripts/test.sh` exit code is the verdict before every commit.

## Review Focus

1. **An account switch while a request is in flight.** A response for the old account that lands after the switch must be dropped, never shown under the new account's name. Pinned in Task 4 (`dropsSnapshotForPreviousAccount`).
2. **Claude Code missing, signed out, or its token expired.** No Keychain item, no `~/.claude.json`, or an expired token must each give a specific, calm message and keep any last numbers marked stale — not a crash or an empty panel. Pinned in Tasks 2 and 4.
3. **A reset time that has already passed.** After a session resets but before the next poll, the row must not count down into negatives; it reads "Resetting now". Pinned in Task 3 (`pastResetReadsResettingNow`).
4. **A response that changes shape.** An unknown `kind` or `severity`, a missing `scope`, a `percent` over 100, or a malformed entry must still give a readable row or skip that one entry, never fail the whole response. Pinned in Task 2.
5. **Hours offline or asleep.** Numbers must say how old they are and polling must back off, not spin. Pinned in Task 4 (`backsOffAfterFailures`, `staleKeepsLastSnapshot`).

---

## File Structure

```
gondar/
  CLAUDE.md                      — repo rules (Task 1)
  project.yml                    — XcodeGen spec (Task 1)
  .gitignore                     — copied from PortGlimpse (Task 1)
  scripts/test.sh, build.sh, install-local.sh, make-icon.swift
  Core/Package.swift
  Core/Sources/GondarCore/
    Credentials.swift            — ClaudeCodeCredentials, LocalAccount (Task 2)
    Usage.swift                  — UsageLimit, UsageReport, ExtraUsage, Money, OAuthUsageParser (Task 2)
    Profile.swift                — Profile + parser (Task 2)
    Text.swift                   — every user-facing formatter (Task 3)
    UsageState.swift             — display state machine (Task 4)
    PollSchedule.swift           — delays and backoff (Task 4)
    AppVersion.swift             — copied from PortGlimpse (Task 9)
  Core/Tests/GondarCoreTests/   — one test file per source file; Fixtures/ holds copies of the spec's fixtures
  App/Info.plist, App/Signing.xcconfig
  App/Sources/
    GondarApp.swift            — @main, AppDelegate, pop-out (Tasks 1, 6, 7)
    Theme.swift                  — copied from PortGlimpse (Task 1)
    CredentialReader.swift       — runs /usr/bin/security (Task 5)
    AnthropicClient.swift        — usage + profile HTTP (Task 5)
    AccountFileWatcher.swift     — watches ~/.claude.json (Task 5)
    UsageModel.swift             — @Observable orchestrator (Task 5)
    MenuBarLabel.swift           — icon + session % (Task 6)
    PanelView.swift, LimitRow.swift, PanelHeader.swift, PanelFooter.swift (Task 6)
    PanelWindowObserver.swift    — copied from PortGlimpse (Task 6)
    FloatingWindow.swift, WindowView.swift (Task 7)
    LoginItem.swift, UpdateChecker.swift (Task 9)
    WebSession.swift, SignInWindow.swift (Tasks 10–11)
  App/Resources/Assets.xcassets, App/Resources/Fonts/
```

---

### Task 1: Scaffold a building, empty menu bar app

**Files:**
- Create: `project.yml`, `.gitignore`, `CLAUDE.md`, `Core/Package.swift`, `Core/Sources/GondarCore/Gondar.swift` (placeholder, deleted in Task 2), `Core/Tests/GondarCoreTests/SmokeTests.swift`, `App/Info.plist`, `App/Signing.xcconfig`, `App/Sources/GondarApp.swift`, `App/Sources/Theme.swift`, `App/Resources/Assets.xcassets/` (empty `AppIcon.appiconset` with `Contents.json`), `App/Resources/Fonts/*` (copied), `scripts/test.sh`, `scripts/build.sh`, `scripts/install-local.sh`

**Interfaces:**
- Produces: the `GondarCore` library target and the `GondarCoreTests` test target with `resources: [.copy("Fixtures")]`; `Theme` with PortGlimpse's members and `PanelButtonStyle`.

- [ ] **Step 1:** Copy `project.yml`, `.gitignore`, `App/Signing.xcconfig`, `App/Info.plist`, `Core/Package.swift`, `scripts/test.sh` (without the `test-install.sh` line), `scripts/build.sh`, `scripts/install-local.sh`, `App/Sources/Theme.swift` and `App/Resources/Fonts/` from PortGlimpse with the renames. In `project.yml` set `MARKETING_VERSION` "0.1.0", `CURRENT_PROJECT_VERSION` "1", `LSApplicationCategoryType` `public.app-category.utilities`.
- [ ] **Step 2:** Write `SmokeTests.swift` with `@Test func packageLoads() { #expect(Bool(true)) }` and `GondarApp.swift` as a `MenuBarExtra` (`.window` style) whose label is `Text("–")` and whose content is a 320-point-wide `Text("Gondar")` on `Theme.panel`.
- [ ] **Step 3:** Write `CLAUDE.md` in PortGlimpse's shape: one-line description, spec and plan paths, Layout, Commands, and the rules from this plan's Global Constraints that are not obvious (Core imports Foundation only; never refresh or write Claude Code's token; tokens never logged; Zewify identity rule; author `Zewify`, no trailers).
- [ ] **Step 4:** Run `./scripts/test.sh`. Expected: exit 0, the test passes and the build prints nothing on error.
- [ ] **Step 5:** Run `./scripts/install-local.sh`. Expected: "Installed /Applications/Gondar.app" and a "–" in the menu bar; clicking it shows the panel.
- [ ] **Step 6:** Commit: `git add -A && git commit -m "Scaffold Gondar: XcodeGen app and GondarCore package"`.

---

### Task 2: Parse credentials, account file, usage and profile

**Files:**
- Create: `Core/Sources/GondarCore/Credentials.swift`, `Usage.swift`, `Profile.swift`
- Delete: `Core/Sources/GondarCore/Gondar.swift`, `SmokeTests.swift`
- Test: `Core/Tests/GondarCoreTests/CredentialsTests.swift`, `UsageTests.swift`, `ProfileTests.swift`; copy both spec fixtures into `Core/Tests/GondarCoreTests/Fixtures/`

**Interfaces:**
- Produces (all `public`, `Sendable`, `Equatable`):
  - `struct ClaudeCodeCredentials { accessToken: String; expiresAt: Date; subscriptionType: String?; rateLimitTier: String? }` with `static func parse(keychainValue: String) throws -> ClaudeCodeCredentials` and `func isExpired(at now: Date) -> Bool` (true within 60 s of `expiresAt`). The keychain value is JSON `{"claudeAiOauth": {accessToken, expiresAt (ms), subscriptionType, rateLimitTier, …}}`.
  - `struct LocalAccount { accountUUID: String; organizationUUID: String }` with `static func parse(claudeJSON: Data) -> LocalAccount?` (reads `oauthAccount.accountUuid` / `organizationUuid`; nil when absent).
  - `enum LimitKind { case session, weeklyAll, weeklyScoped, other(String) }` from `"session"`, `"weekly_all"`, `"weekly_scoped"`.
  - `enum Severity { case normal, other(String) }`.
  - `struct UsageLimit { id: String; kind: LimitKind; scopeName: String?; percent: Int; severity: Severity; resetsAt: Date?; isActive: Bool; shareOfWeekly: Int? }`; `id` is `kind` raw plus `scopeName` (for SwiftUI identity).
  - `struct Money { minor: Int; currency: String; exponent: Int }`, `struct ExtraUsage { used: Money; limit: Money }`.
  - `struct UsageReport { limits: [UsageLimit]; extra: ExtraUsage? }` and `enum OAuthUsageParser { static func parse(_ data: Data) throws -> UsageReport }`. `extra` comes from `spend` when `spend.enabled` is true, else nil. `shareOfWeekly` comes from `weekly_scoped_shares[].allowance_percent_of_weekly` matched by `limit_index`.
  - `struct Profile { accountUUID, email, organizationUUID, organizationName: String; organizationType, rateLimitTier, seatTier: String? }` with `static func parse(_ data: Data) throws -> Profile`.
- Dates: `resets_at` has a fractional-second and offset form (`2026-10-20T03:20:00.561169+00:00`) and a whole-second form (`2026-10-26T00:00:00+00:00`); parse both.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func parsesMeasuredUsage() throws {
    let report = try OAuthUsageParser.parse(fixture("oauth-usage-2026-10-20.json"))
    #expect(report.limits.map(\.kind) == [.session, .weeklyAll, .weeklyScoped])
    #expect(report.limits.map(\.percent) == [12, 8, 0])
    #expect(report.limits[2].scopeName == "Fable")
    #expect(report.limits[2].shareOfWeekly == 50)
    #expect(report.limits[0].isActive && !report.limits[1].isActive)
    #expect(report.limits[0].resetsAt == iso("2026-10-20T03:20:00.561Z"))   // to the millisecond
    #expect(report.limits[2].resetsAt == iso("2026-10-26T00:00:00Z"))
    #expect(report.extra == ExtraUsage(used: Money(minor: 0, currency: "USD", exponent: 2), limit: Money(minor: 0, currency: "USD", exponent: 2)))
}
@Test func keepsUnknownKindAndSeverity() throws   // {"limits":[{"kind":"daily_new","group":"x","percent":5,"severity":"critical","resets_at":null,"scope":null,"is_active":true}]} → .other("daily_new"), .other("critical"), resetsAt nil
@Test func skipsMalformedEntryKeepsTheRest() throws // one entry missing "percent" among two good ones → 2 limits
@Test func keepsPercentOver100() throws            // percent 130 → 130 (clamping is the view's job)
@Test func noLimitsKeyThrows()                      // {} → throws
@Test func extraIsNilWhenSpendDisabled() throws
@Test func parsesCredentials() throws               // expiresAt 1792476437162 → Date(timeIntervalSince1970: 1792476437.162); tier "default_claude_max_20x"
@Test func credentialsExpireSixtySecondsEarly()     // isExpired at expiresAt-59s → true, at expiresAt-61s → false
@Test func credentialsWithoutAccessTokenThrow()
@Test func parsesLocalAccount()                     // {"oauthAccount":{"accountUuid":"a","organizationUuid":"b"}} → LocalAccount("a","b"); {} → nil
@Test func parsesScrubbedProfile() throws           // fixture → email "test@example.com", organizationName "Example Org", organizationType "claude_max", rateLimitTier "default_claude_max_20x", seatTier nil
```

Write the bodies of the commented tests with the inputs and expectations shown; `fixture(_:)` loads from `Bundle.module`.

- [ ] **Step 2:** Run `cd Core && swift test`. Expected: compile failure (types not defined).
- [ ] **Step 3:** Implement the three files with `Decodable` wire types kept `private`; decode `limits` as `[FailableDecodable<WireLimit>]` so one bad entry is skipped.
- [ ] **Step 4:** Run `./scripts/test.sh`. Expected: all pass, exit 0.
- [ ] **Step 5:** Commit: `"Core: parse Claude Code credentials, account file, usage and profile"`.

---

### Task 3: Every user-facing text

**Files:**
- Create: `Core/Sources/GondarCore/Text.swift`
- Test: `Core/Tests/GondarCoreTests/TextTests.swift`

**Interfaces:**
- Consumes: `UsageLimit`, `LimitKind`, `Severity`, `Money`, `Profile` (Task 2).
- Produces:
  - `enum LimitText { static func name(_ limit: UsageLimit) -> String; static func isWarning(_ limit: UsageLimit) -> Bool; static func barFraction(_ limit: UsageLimit) -> Double }`
  - `enum ResetText { static func countdown(to: Date, now: Date) -> String; static func full(resetsAt: Date?, now: Date, calendar: Calendar, locale: Locale) -> String }`
  - `enum PlanText { static func label(organizationType: String?, rateLimitTier: String?) -> String? }`
  - `enum UpdatedText { static func text(fetchedAt: Date, now: Date) -> String }`
  - `enum MoneyText { static func text(_ money: Money, locale: Locale) -> String }`
- Rules this task fixes:
  - Names: session → "Current session"; weeklyAll → "Weekly · all models"; weeklyScoped → "Weekly · \(scopeName ?? "one model")"; other(raw) → raw with `_` as spaces and the first letter capitalised.
  - Warning: `severity != .normal || percent >= 80`.
  - Bar fraction: `min(max(percent, 0), 100) / 100`.
  - Countdown: under 1 min "under 1 m"; under 1 h "36 m"; under 24 h "1 h 36 m"; otherwise "5 d 3 h". Minutes round down.
  - Full: nil → "No reset time"; in the past → "Resetting now"; today → "Resets in 1 h 36 m · 11:20 PM"; other days → "Resets in 5 d 22 h · Sun, Oct 25, 8:00 PM". Times use the locale's own time format (`Date.FormatStyle` with `.hour().minute()`), in the calendar's time zone.
  - Plan: `claude_team` → "Team", `claude_max` → "Max", `claude_pro` → "Pro", `claude_enterprise` → "Enterprise", else nil; tier `default_claude_max_5x` → "Max 5x", `default_claude_max_20x` → "Max 20x", else omitted; joined with " · ", e.g. "Max · Max 20x"; nil when both are unknown.
  - Updated: under 60 s "Updated just now"; then "Updated 1 min ago", "Updated 5 min ago", "Updated 2 h ago".
  - Money: currency-formatted from `minor / 10^exponent`, e.g. "$0.00" in `en_US`.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func namesEachKind()                 // session, weeklyAll, weeklyScoped("Fable") → "Weekly · Fable", other("daily_new") → "Daily new"
@Test func warnsOnSeverityOrEightyPercent() // (normal,79) false, (normal,80) true, (other("high"),10) true
@Test func clampsBar()                     // 130 → 1.0, -5 → 0.0, 12 → 0.12
@Test func countsDown()                    // 30 s → "under 1 m", 36 m 59 s → "36 m", 1 h 36 m → "1 h 36 m", 5 d 3 h 20 m → "5 d 3 h"
@Test func pastResetReadsResettingNow()    // resetsAt = now - 5 s → "Resetting now"
@Test func fullTextToday()                 // now 2026-10-20T01:44Z, reset 03:20Z, tz America/New_York, en_US → "Resets in 1 h 36 m · 11:20 PM"
@Test func fullTextOtherDay()              // reset 2026-10-26T00:00Z, same tz/locale → begins "Resets in 5 d" and contains "Sun, Oct 25"
@Test func planLabel()                     // ("claude_team", nil) → "Team"; (nil,nil) → nil; ("claude_pro", "x") → "Pro"
@Test func updatedText()                   // 10 s "Updated just now", 61 s "Updated 1 min ago", 7300 s "Updated 2 h ago"
@Test func moneyText()                     // Money(1234,"USD",2), en_US → "$12.34"
```

Before fixing the expected strings for the two `fullText` tests and `moneyText`, print what Foundation produces for `en_US` on the build Mac and use that exact output, since separators and am/pm casing come from the OS.

- [ ] **Step 2:** Run `cd Core && swift test`. Expected: compile failure.
- [ ] **Step 3:** Implement `Text.swift`.
- [ ] **Step 4:** Run `./scripts/test.sh`. Expected: exit 0.
- [ ] **Step 5:** Commit: `"Core: limit names, reset countdowns, plan and money text"`.

---

### Task 4: Display state across switches and failures, and the poll schedule

**Files:**
- Create: `Core/Sources/GondarCore/UsageState.swift`, `PollSchedule.swift`
- Test: `Core/Tests/GondarCoreTests/UsageStateTests.swift`, `PollScheduleTests.swift`

**Interfaces:**
- Consumes: `UsageReport`, `Profile` (Task 2).
- Produces:
  - `enum Source { case claudeCode, claudeAI }`
  - `struct Snapshot { profile: Profile; plan: String?; report: UsageReport; fetchedAt: Date; source: Source }`
  - `enum Problem { case claudeCodeNotSignedIn, tokenExpired, unauthorized, rateLimited, offline, unreadableResponse }` with `var message: String`:
    - claudeCodeNotSignedIn → "Sign in to Claude Code, or to claude.ai below."
    - tokenExpired → "Open Claude Code to refresh."
    - unauthorized → "Claude Code's login was refused. Sign in to Claude Code again."
    - rateLimited → "Asked too often. Trying again shortly."
    - offline → "Offline."
    - unreadableResponse → "Anthropic changed the usage format. An update is needed."
  - `enum Display { case loading; case ready(Snapshot); case stale(Snapshot, Problem); case unavailable(Problem) }`
  - `struct UsageState { private(set) var display: Display; private(set) var accountUUID: String? }` with `mutating func accountChanged(to accountUUID: String?)`, `mutating func received(_ snapshot: Snapshot)`, `mutating func failed(_ problem: Problem)`.
  - `struct PollSchedule { static let interval: Duration = .seconds(120); static let minimumGap: Duration = .seconds(60); var failures: Int; func nextDelay(retryAfter: Duration?) -> Duration; static func mayPollNow(lastAttempt: Date?, now: Date) -> Bool }`.
- Rules:
  - `accountChanged` to a different non-nil UUID → `display = .loading`, previous snapshot gone; to nil → `.unavailable(.claudeCodeNotSignedIn)`; to the same UUID → no change.
  - `received` with `snapshot.profile.accountUUID != accountUUID` → ignored. Otherwise `.ready`.
  - `failed` → `.stale(last, problem)` if a snapshot for this account exists (from `.ready` or `.stale`), else `.unavailable(problem)`.
  - `nextDelay`: `retryAfter` when given (at least `minimumGap`); otherwise 120 s × 2^failures, capped at 30 min.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func startsLoadingForNewAccount()            // accountChanged("a") → .loading, accountUUID "a"
@Test func showsSnapshotForCurrentAccount()        // accountChanged("a"), received(snap(account: "a")) → .ready
@Test func dropsSnapshotForPreviousAccount()       // accountChanged("a"), accountChanged("b"), received(snap(account: "a")) → still .loading
@Test func switchingClearsOldNumbers()             // ready for "a", accountChanged("b") → .loading
@Test func sameAccountKeepsNumbers()               // ready for "a", accountChanged("a") → still .ready
@Test func signedOutIsUnavailable()                // accountChanged(nil) → .unavailable(.claudeCodeNotSignedIn)
@Test func staleKeepsLastSnapshot()                // ready, failed(.offline) → .stale(sameSnapshot, .offline); failed(.tokenExpired) again → .stale(sameSnapshot, .tokenExpired)
@Test func failureWithoutSnapshotIsUnavailable()   // loading, failed(.unauthorized) → .unavailable(.unauthorized)
@Test func backsOffAfterFailures()                 // failures 0 → 120 s, 1 → 240 s, 3 → 960 s, 10 → 1800 s
@Test func honoursRetryAfterButNotBelowMinimum()   // retryAfter 300 s → 300 s; retryAfter 5 s → 60 s
@Test func refusesPollWithinAMinute()              // lastAttempt now-30 s → false; now-61 s → true; nil → true
```

- [ ] **Step 2:** Run `cd Core && swift test`. Expected: compile failure.
- [ ] **Step 3:** Implement both files.
- [ ] **Step 4:** Run `./scripts/test.sh`. Expected: exit 0.
- [ ] **Step 5:** Commit: `"Core: display state across account switches and failures; poll schedule"`.

---

### Task 5: Read Claude Code's login, call Anthropic, follow the account

**Files:**
- Create: `App/Sources/CredentialReader.swift`, `AnthropicClient.swift`, `AccountFileWatcher.swift`, `UsageModel.swift`
- Modify: `App/Sources/GondarApp.swift` (own a `UsageModel`; label shows `model.menuBarText`)

**Interfaces:**
- Consumes: Tasks 2–4.
- Produces:
  - `enum CredentialReader { static func read() async -> String? }` — runs `/usr/bin/security find-generic-password -s "Claude Code-credentials" -w` with `Process`, returns trimmed stdout on exit 0, nil otherwise (exit 44 means no item). Never logs stdout.
  - `struct AnthropicClient { func usage(token: String) async -> Result<UsageReport, FetchError>; func profile(token: String) async -> Result<Profile, FetchError> }` with `enum FetchError { case unauthorized, rateLimited(retryAfter: Duration?), offline, unreadable }` — 401/403 → unauthorized, 429 → rateLimited (reads `Retry-After` seconds), `URLError` → offline, other status or parse failure → unreadable. Timeout 20 s. Base URL `https://api.anthropic.com/api/oauth/`.
  - `final class AccountFileWatcher { init(onChange: @escaping @Sendable () -> Void); func start(); func stop() }` — watches the home directory with a `DispatchSource` file-system-object source for `.write` and re-reads only when `~/.claude.json`'s modification date changed, because Claude Code replaces the file by rename and a watch on the file itself goes dead. Debounce 1 s.
  - `@MainActor @Observable final class UsageModel { private(set) var state: UsageState; private(set) var now: Date; var menuBarText: String; var sessionLimit: UsageLimit?; func start(); func refresh(); func viewerAppeared() }`.
- Poll cycle (`UsageModel.poll()`), in this order:
  1. Respect `PollSchedule.mayPollNow`.
  2. `CredentialReader.read()`; nil → `state.accountChanged(to: nil)`, stop.
  3. Parse credentials; if expired → re-read once on the next cycle (Claude Code may refresh it), and `state.failed(.tokenExpired)`; stop.
  4. If the token differs from the last one seen (compare a SHA-256 of it held in memory only), call `profile`; on success `state.accountChanged(to: profile.accountUUID)` and keep the profile; on failure map to a `Problem` and stop.
  5. Call `usage`; on success `state.received(Snapshot(profile:, plan: PlanText.label(...), report:, fetchedAt: now, source: .claudeCode))`; on failure `state.failed(...)`, `failures += 1`.
  6. Sleep `nextDelay`.
- `AccountFileWatcher` change → forget the token fingerprint and poll now (ignoring `mayPollNow`, since an account switch must show within seconds).
- Pause the loop on `NSWorkspace.willSleepNotification`, poll once on `didWakeNotification`.
- `now` ticks every 30 s so countdowns move without polling.
- `menuBarText`: session percent as "12%"; "–" when there is no session limit.

- [ ] **Step 1:** Implement the four files and the label wiring.
- [ ] **Step 2:** Run `./scripts/test.sh`. Expected: exit 0.
- [ ] **Step 3: The Keychain check from the installed app (spec, "Source 1").** Run `./scripts/install-local.sh`, wait 5 s, then screenshot every display (`screencapture -x`) and look at each. Expected: the menu bar shows the live session percentage (compare with `/usage` in Claude Code) and **no** Keychain dialog. If a dialog appears, stop and record it in the spec's "Source 1" section; per the spec, Tasks 10–11 then move ahead of Task 6, and this task gains a "Use Claude Code's login" toggle that gates `CredentialReader`.
- [ ] **Step 4: The account-switch check.** Ask the maintainer to run `/login` in Claude Code to switch accounts while the app runs. Expected: within 5 s the label goes to "–" then to the other account's percentage. Record the result in the spec.
- [ ] **Step 5:** Commit: `"Read Claude Code's login and show the live session percentage"`.

---

### Task 6: The menu bar label and the panel

**Files:**
- Create: `App/Sources/MenuBarLabel.swift`, `PanelView.swift`, `PanelHeader.swift`, `LimitRow.swift`, `PanelFooter.swift`, `PanelWindowObserver.swift` (copied)
- Modify: `App/Sources/GondarApp.swift`

**Interfaces:**
- Consumes: `UsageModel` (Task 5), `LimitText`, `ResetText`, `UpdatedText`, `MoneyText`, `Display`, `Problem.message`.
- Produces: `LimitRow(limit: UsageLimit, now: Date, compact: Bool)` and `PanelHeader(model: UsageModel, compact: Bool)` — reused by the floating window; `PanelFooter(model:onPopOut:)`.
- Layout (panel 340 points wide; PortGlimpse's paddings: 18 leading, 10 trailing):
  - Label: a placeholder 18-point amber rounded bar on a dark tile (replaced by the icon in Task 8) plus `menuBarText` in IBM Plex Mono; amber text when `LimitText.isWarning(session)`.
  - Header: email (Figtree 13 semibold, text), organisation · plan (Figtree 12, muted), and on the right `UpdatedText` (12, muted). `.stale` adds the problem's message in amber on a second line. `.loading` shows a small `ProgressView`; `.unavailable` shows only the message.
  - Rows: name (Figtree 13 semibold) and percent (IBM Plex Mono 13) on one line; a 6-point bar (track `Theme.line`, fill `Theme.amber`, inactive limits fill `Theme.muted`) at `LimitText.barFraction`; `ResetText.full` (Figtree 12, muted) beneath. Rows divided by `Theme.line`.
  - Extra usage row when `report.extra != nil`: "Extra usage" and "\(MoneyText used) of \(MoneyText limit)".
  - Footer: "Pop out", "Refresh" (disabled while `mayPollNow` is false), a source line "From Claude Code", a Settings menu with "Launch at login" (Task 9) and "Check for updates" (Task 9), and "Quit" — PortGlimpse's `PanelFooter` styling.
- Opening the panel calls `model.viewerAppeared()` (through `PanelWindowObserver`), which polls when the last poll is older than 60 s.

- [ ] **Step 1:** Implement the views.
- [ ] **Step 2:** Run `./scripts/test.sh`. Expected: exit 0.
- [ ] **Step 3: Live check.** `./scripts/install-local.sh`, click the icon, screenshot every display. Compare against Claude Code's `/usage`: same percentages and reset times. Check against the spec's "The panel" and PortGlimpse's panel side by side: fonts load (not system font), nothing truncated at 340 points, colours as Global Constraints. Measure computed sizes rather than trusting a scaled screenshot. Fix anything off before committing.
- [ ] **Step 4: Failure-state check.** Temporarily point `AnthropicClient`'s base URL at `https://127.0.0.1:9/` in a Debug build: the panel keeps the numbers and shows "Offline." in amber with the age. Revert.
- [ ] **Step 5:** Commit: `"Menu bar label and usage panel"`.

---

### Task 7: The floating window

**Files:**
- Create: `App/Sources/FloatingWindow.swift` (copied from PortGlimpse), `App/Sources/WindowView.swift`
- Modify: `App/Sources/GondarApp.swift` (copy PortGlimpse's `popOut()` and `statusItemButton()`), `PanelFooter.swift`

**Interfaces:**
- Consumes: `LimitRow`, `PanelHeader`, `PanelFooter`, `UsageModel.viewerAppeared()`.
- Produces: `FloatingWindowController(model:content:)` with `show()`; autosave name `GondarWindow`; default size 320×300; minimum 220×140.
- Rules:
  - Level `.floating`, on all Spaces and over full-screen apps — as PortGlimpse.
  - Below 280 points wide, `compact: true`: each row is one line, name · percent · countdown (`ResetText.countdown`), no bar; the header is the email only.
  - The window remembers being open: `UserDefaults` key `floatingWindowOpen`, set on show and cleared on close; at launch, if set, show it.
  - Closing it does not quit.

- [ ] **Step 1:** Implement.
- [ ] **Step 2:** Run `./scripts/test.sh`. Expected: exit 0.
- [ ] **Step 3: Live check.** Install, Pop out, then: drag it to another display if there is one, resize below 280 to see the compact layout, switch Spaces and enter a full-screen app (the window stays), quit and relaunch (it reopens at the same place). Screenshot each.
- [ ] **Step 4:** Commit: `"Always-on-top floating window"`.

---

### Task 8: The icon

**Files:**
- Create: `scripts/make-icon.swift`, `App/Resources/Assets.xcassets/AppIcon.appiconset/*`
- Modify: `App/Sources/MenuBarLabel.swift`

**Interfaces:**
- Produces: `MenuBarIcon` drawing the same mark at 18 points in full colour.
- The mark (spec, "Icon"; a starting point the maintainer will settle): PortGlimpse's dark tile `#221E1B` with an amber `#F48E48` gauge — a 240° arc track in `#4A3F35` with an amber arc filling about 60 % of it — drawn by `make-icon.swift` in PortGlimpse's geometry (824-point tile inset 100 in a 1024 canvas, every macOS size).

- [ ] **Step 1:** Write `make-icon.swift` from PortGlimpse's, replacing the colon with the gauge, and run `swift scripts/make-icon.swift App/Resources/Assets.xcassets/AppIcon.appiconset`.
- [ ] **Step 2:** Replace the placeholder in `MenuBarLabel` with `MenuBarIcon`.
- [ ] **Step 3:** Run `./scripts/test.sh`, install, compare the menu bar icon with PortGlimpse's mark at the same size. Expected: same size and weight family.
- [ ] **Step 4:** Commit: `"Gauge icon for the app and menu bar"`.

---

### Task 9: Launch at login and the update check

**Files:**
- Create: `App/Sources/LoginItem.swift` (copied as is), `App/Sources/UpdateChecker.swift` (copied), `Core/Sources/GondarCore/AppVersion.swift` (copied with `ReleaseFeed`), `Core/Tests/GondarCoreTests/AppVersionTests.swift` (copied)
- Modify: `PanelFooter.swift`, `GondarApp.swift`

**Interfaces:**
- `UpdateChecker.feed` becomes `URL?` and is `nil` until the public repo exists; with `nil`, `check` returns at once and the "Check for updates" item is hidden. `installCommand` is `nil` the same way.

- [ ] **Step 1:** Copy and adapt; `loginItem.enableOnFirstLaunch()` at launch, as PortGlimpse.
- [ ] **Step 2:** Run `./scripts/test.sh`. Expected: exit 0, the copied `AppVersionTests` pass.
- [ ] **Step 3:** Install; check System Settings → General → Login Items lists Gondar.
- [ ] **Step 4:** Commit: `"Launch at login; update check, off until the repo is public"`.

---

### Task 10: Measure the claude.ai usage endpoint (needs the maintainer)

**Files:**
- Modify: `docs/superpowers/specs/2026-10-20-gondar-design.md` ("Source 2")
- Create: `docs/superpowers/specs/fixtures/claude-ai-usage-<date>.json` (scrubbed), `Core/Tests/GondarCoreTests/Fixtures/` copy

- [ ] **Step 1:** Ask the maintainer to open claude.ai → Settings → Usage in a browser with its developer tools' network panel and record the request that returns the limits (URL pattern, method, which cookies, and the organisation UUID in the path).
- [ ] **Step 2:** Save the response with every account, organisation and person value replaced by fakes; grep it for real names and emails before saving.
- [ ] **Step 3:** Write the findings into the spec's "Source 2": endpoint, how the organisation is chosen, how its fields map onto `UsageReport`, and anything missing (plan name, email).
- [ ] **Step 4:** Commit: `"Spec: measured claude.ai usage endpoint"`.

---

### Task 11: claude.ai sign-in and fallback

The exact parser and field names come from Task 10's measurement, so this task is planned in outline; the implementer extends this plan with exact interfaces after Task 10 before writing code.

**Files:**
- Create: `Core/Sources/GondarCore/WebUsageParser.swift` + tests, `App/Sources/WebSession.swift`, `App/Sources/SignInWindow.swift`
- Modify: `UsageModel.swift`, `PanelFooter.swift`

**Fixed decisions:**
- `WebUsageParser.parse(_ data: Data) throws -> UsageReport`, tested against Task 10's fixture in the same style as Task 2.
- Sign-in happens in a `WKWebView` window loading `https://claude.ai/login`, with a `WKWebsiteDataStore(forIdentifier:)` store owned by the app; requests read cookies from that store and go only to `claude.ai`.
- When source 1 has no usable token (`claudeCodeNotSignedIn` or `tokenExpired`) and a claude.ai session exists, poll through it, but only for the organisation whose UUID equals `LocalAccount.organizationUUID` when Claude Code has one; if that organisation is not reachable, keep the stale state.
- With no Claude Code at all, use the organisation the claude.ai session marks active; if several exist, a picker in the panel header that remembers the choice in `UserDefaults` (UUID only).
- `Snapshot.source = .claudeAI`; the footer source line reads "From claude.ai"; the footer gains "Sign in to claude.ai" / "Sign out of claude.ai".
- Tests for `UsageState` stay unchanged; add `UsageModel`-free Core tests for the organisation choice as a pure function `chooseOrganization(available: [String], claudeCode: String?, remembered: String?) -> String?`.

- [ ] **Step 1:** Extend this task with exact interfaces and tests from Task 10's findings; commit the plan change.
- [ ] **Step 2:** Implement test-first as in Tasks 2–4, then wire the app.
- [ ] **Step 3: Live check.** Add a Debug-only launch argument `-GondarIgnoreClaudeCode YES` that makes `CredentialReader.read()` return nil, so the fallback can be tested without signing out of Claude Code; launch with it, sign in to claude.ai in the app, and compare with Settings → Usage.
- [ ] **Step 4:** Commit: `"claude.ai sign-in as a fallback source"`.
