# Gondar Status Line Feed Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Read usage from Claude Code's status line feed so the rate-limited usage endpoint is asked rarely, keep the last numbers across relaunches, and colour the panel bars by level.

**Architecture:** A tiny `gondar-feed` tool in the app bundle wraps the existing status line command and writes only `rate_limits` to a file; Core parses and merges feed and API limits by freshness; the app watches the file, slows API polling while the feed is fresh, and persists the last snapshot.

**Tech Stack:** Swift 6, SwiftUI, XcodeGen (a second `tool` target), Swift Testing, macOS 14+.

**Spec:** `docs/superpowers/specs/2026-10-20-gondar-design.md`, section "Source 0: Claude Code's status line" (read it first), plus the bar-colour line under "The panel".

## Global Constraints

- Everything in the first plan's Global Constraints still binds (`docs/superpowers/plans/2026-10-20-gondar-app.md`).
- The feed tool stores only `rate_limits` and a received time; never the working folder, transcript path, model, cost or session ID.
- The feed tool must always run the wrapped command with identical stdin and pass through its stdout, stderr and exit code, even when its own write fails.
- Files: `~/Library/Application Support/Gondar/statusline.json` and `last.json`, written atomically, mode 0600; `last.json` holds account and organisation UUIDs, limits and a time — never a token or an email.
- Gondar never edits `~/.claude/settings.json`.
- Feed freshness 10 minutes; API interval while the feed is fresh 15 minutes; otherwise 120 s as before.

## Review Focus

1. **The wrapped status line breaks.** Exit codes, stderr, a wrapped command that reads stdin twice or not at all, a missing Application Support folder. Pinned in Task 2's script test.
2. **Feed numbers under the wrong account.** Feed data received before an account change must never show for the new account. Pinned in Task 1 (`feedBeforeAccountChangeIsIgnored`).
3. **A stale feed shown as live.** A feed older than 10 minutes falls back to the API and the source line says so. Pinned in Task 1 (`staleFeedIsIgnored`).
4. **A saved snapshot for another account at launch.** Pinned in Task 3 (`savedSnapshotForOtherAccountIsIgnored`).
5. **Unexpected feed shapes.** Null limits, missing `rate_limits`, `used_percentage` as a string, `resets_at` in milliseconds by mistake. Pinned in Task 1.

---

### Task 1: Core — parse the feed and merge it with API limits

**Files:**
- Create: `Core/Sources/GondarCore/StatusLineFeed.swift`
- Test: `Core/Tests/GondarCoreTests/StatusLineFeedTests.swift`, fixture `Fixtures/statusline-sample.json` (hand-made from the spec's shape; replaced by a scrubbed real sample in Task 4)

**Interfaces:**
- `public struct FeedSnapshot: Sendable, Equatable { receivedAt: Date; limits: [UsageLimit] }`
- `public enum StatusLineFeed { static func extract(statusLineJSON: Data, receivedAt: Date) throws -> Data` (the minimal JSON `{"received_at": <unix s>, "rate_limits": {...}}` the tool writes) `; static func parse(_ data: Data) throws -> FeedSnapshot }`
- `public enum LimitMerge { static func merge(api: UsageReport?, feed: FeedSnapshot?, feedAccepted: Bool, now: Date) -> (report: UsageReport, live: Bool) }` — `feedAccepted` is false when the feed predates the last account change; the feed is used only when accepted and `now - receivedAt < 600 s`; feed limits replace API limits of the same kind (`session`, `weekly_all`, and scoped Sonnet/Opus by scope name); other API limits and `extra` are kept; `live` is true when any feed limit was used.
- `public enum PollSchedule` gains `static let feedInterval: Duration = .seconds(900)`.
- Mapping per the spec; `used_percentage` number or numeric string, rounded; `resets_at` Unix seconds (a value above 10^11 is treated as milliseconds), rounded to the minute; null/missing entries skipped; missing `rate_limits` → empty feed, not an error; feed limits are `isActive: true`, `severity: .normal`.

- [ ] Write failing tests: `extractKeepsOnlyRateLimits` (input with cwd, transcript_path, cost, session_id → output has only `received_at` and `rate_limits`), `parsesFeed` (36.4 → 36, resets rounded), `mapsSonnetAndOpus`, `skipsNullLimits`, `missingRateLimitsIsEmpty`, `millisecondResetsAreTolerated`, `feedReplacesApiByKind`, `apiOnlyLimitsAreKept` (Fable and extra stay), `staleFeedIsIgnored` (601 s), `feedBeforeAccountChangeIsIgnored` (feedAccepted false), `liveFlag`.
- [ ] Run, see them fail; implement; run `./scripts/test.sh`; identity check; commit "Core: parse Claude Code's status line feed and merge it with API limits".

### Task 2: The `gondar-feed` tool

**Files:**
- Create: `Feed/main.swift`; `scripts/test-feed.sh`
- Modify: `project.yml` (a `tool` target `gondar-feed` depending on `GondarCore`, embedded in the app at `Contents/MacOS`), `scripts/test.sh` (runs `test-feed.sh`), `CLAUDE.md`

**Behaviour:** read stdin to EOF; `StatusLineFeed.extract`; create the folder (0700) and write `statusline.json` atomically (temp file + rename, 0600), ignoring any error; if arguments were given, run them (`posix_spawnp` or `Process` with the executable resolved on PATH) with the same stdin bytes, inheriting stdout and stderr, and exit with the child's status; with no arguments print nothing and exit 0.

- [ ] `scripts/test-feed.sh` (bash, uses a temp HOME): wrapped `cat` echoes stdin unchanged; wrapped `sh -c 'exit 3'` → exit 3; stderr passes through; the written file has mode 600 and contains no `cwd`/`transcript_path`; a read-only Application Support folder still runs the wrapped command; no args → no output, exit 0; runtime of one call under 100 ms.
- [ ] Implement; `./scripts/test.sh` (now includes the feed test); identity check; commit "gondar-feed: wrap the status line and save its rate limits".

### Task 3: App — use the feed, slow the API, keep the last snapshot, colour the bars

**Files:**
- Create: `App/Sources/FeedWatcher.swift`, `Core/Sources/GondarCore/SavedSnapshot.swift` + tests
- Modify: `App/Sources/UsageModel.swift`, `PanelHeader.swift`, `PanelFooter.swift` (Settings item), `LimitRow.swift` (bar colour), `Core/.../UsageState.swift` (if a `live` flag is needed on `Snapshot`)

**Interfaces / rules:**
- `FeedWatcher` watches `~/Library/Application Support/Gondar/` (same directory-watch pattern as `AccountFileWatcher`), debounced 0.5 s, calls back with the parsed `FeedSnapshot`.
- `UsageModel` keeps the last API report and the last feed; every change re-merges with `LimitMerge` and updates `state` (a feed-only snapshot is allowed when no API report exists yet, using the header fields from `~/.claude.json`).
- Account: record the time of the last account change; `feedAccepted = feed.receivedAt > lastAccountChange`.
- API cadence: `PollSchedule.feedInterval` while the merged result is live, else the existing schedule; backoff rules unchanged.
- `SavedSnapshot` (Core): `encode(snapshot:accountKey:) -> Data`, `decode(_:) -> (AccountKey, UsageReport, Date)?`; tests `roundTrips`, `containsNoEmailOrToken`, `savedSnapshotForOtherAccountIsIgnored` (a pure `restore(saved:currentAccount:) -> ...?`).
- Save after every shown snapshot; restore at launch as `.stale(…, .restored)` — a new Problem "Last numbers from before Gondar restarted." with short label "Restored" — until the first live/API result.
- Header falls back to `~/.claude.json` `oauthAccount` fields (email, organisation, plan via `PlanText`) before the profile arrives; the source line reads "Live from Claude Code" when live, else "From Anthropic".
- Settings menu: "Connect Claude Code's status line…" opens a small sheet/alert showing the exact `statusLine.command` value (`"/Applications/Gondar.app/Contents/MacOS/gondar-feed" ` + the current command read from `~/.claude/settings.json`, or just the tool if none) with a Copy button. Read-only access to settings.json.
- Bars use `Theme.level(LimitText.level(limit))` (a design decision).

- [ ] Core tests first (SavedSnapshot, any merge glue); implement app; `./scripts/test.sh`; Debug demo still works.
- [ ] Live check without touching settings.json: install once; run `echo '<sample JSON>' | /Applications/Gondar.app/Contents/MacOS/gondar-feed` with a sample whose `five_hour.used_percentage` differs from the API value → the menu bar and panel change within a second and the source line says "Live from Claude Code"; quit and relaunch once → numbers appear immediately marked "Restored". Screenshot each.
- [ ] Identity check; commit "Use the status line feed, keep the last numbers, colour bars by level".

### Task 4: Hook-up and real sample (needs the maintainer)

- [ ] Ask the maintainer to set `statusLine.command` in `~/.claude/settings.json` to the value the Settings item shows (Gondar and its builder never edit that file).
- [ ] After one Claude Code response, copy `statusline.json`, confirm the real shape matches Task 1's parser; if not, fix the parser test-first. Save it as a fixture (it contains only rate limits).
- [ ] Record the measured shape in the spec's Source 0; commit.
