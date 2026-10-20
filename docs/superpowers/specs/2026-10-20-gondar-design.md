# Gondar — design

Gondar is the app's name.
It is a free Mac menu bar app with an always-on-top floating window that shows a Claude subscription's usage limits: the current session, the weekly limits for all models and for each scoped model (Fable today), and when each one resets.
It is a Zewify product.

## Why

To see their usage today, a person opens the Claude app, then Settings, then Usage.
Gondar puts those numbers in view at any time, without opening anything.
A terminal status line can show the session figure, but only while a Claude Code session is running.
Free apps that do this already exist (CodexBar, ClaUse Bar, Clabar and others); Gondar is Zewify's own take on it.
The floating window is the part those apps don't obviously offer.

## Goals

- The menu bar always shows the session percentage at a glance.
- Clicking it opens a panel listing every limit: its name, a bar, the percentage, and when it resets, as both a countdown and a clock time.
- A floating window shows the same limits, one line each, stays above other windows on every Space and over full-screen apps, and reopens where it was left.
- New limits that Anthropic adds (a new scoped model, say) appear without an app update.
- It works on a Mac where Claude Code is not running, and on a Mac where Claude Code was never installed.
- Anyone can install it from zewify.com.

## Non-goals

- Sending prompts or using the login for anything but reading usage.
- Usage history, charts or cost estimates.
- Several accounts at once: a person may switch Claude accounts from time to time, and the app shows only the one signed in now (see "Following the signed-in account").
- The Mac App Store (see "Distribution").
- Notifications at thresholds — a later version, if wanted.
- Windows, iPhone or iPad.

## Anti-goals

- Logging the person out of Claude Code, or making Claude Code ask them to sign in again.
- A Keychain prompt every time the app reads usage, or after every update.
- Showing a number as current when it is stale; a stale value must say how old it is.
- Anything that identifies the person who builds it (the Zewify rule).

## Where the numbers come from

There is no documented API for plan usage, so both sources below are undocumented and can change without notice.
The app must fail visibly, never silently: if a source stops answering in the shape it expects, it shows the last good values marked stale and a short reason.

### Source 1: Claude Code's login (measured 2026-10-20)

Claude Code stores its login in the login Keychain as a generic password with service `Claude Code-credentials`.
Its value is JSON: `claudeAiOauth.accessToken`, `refreshToken`, `expiresAt` (milliseconds), `subscriptionType` (for example `max`) and `rateLimitTier` (for example `default_claude_max_20x`).
The access token lasted about four hours when measured, and Claude Code refreshes it whenever it runs.

`GET https://api.anthropic.com/api/oauth/usage` with `Authorization: Bearer <accessToken>` and `anthropic-beta: oauth-2025-04-20` returned the usage.
The field that matters is `limits`, a list in which each entry has `kind` (`session`, `weekly_all`, `weekly_scoped`), `group`, `percent`, `severity` (`normal` seen; other values not yet seen), `resets_at` (ISO 8601 with a fraction and an offset), `is_active`, and a `scope` that names a model's `display_name` (`Fable`) for scoped limits.
`weekly_scoped_shares` says what share of the weekly allowance a scoped limit gets (Fable: 50 %).
`extra_usage` and `spend` describe paid usage beyond the plan (enabled, used and limit amounts in minor units, in the account's own currency, for example USD).
The older fields (`five_hour`, `seven_day`, `seven_day_opus` and many codenamed nulls) carry the same data less generally; the app reads `limits` and ignores the rest.
The full raw response, saved the same day, is `fixtures/oauth-usage-2026-10-20.json` beside this document; it holds no account, organisation or person identifiers, so it can be the Core's first test fixture as is.
In it, `percent` is an integer from 0 to 100, `group` is `session` or `weekly`, and `scope` is an object `{model: {id, display_name}, surface}` or null.
Each entry in `weekly_scoped_shares` points at a limit by its position in `limits` (`limit_index`).
`spend` uses money objects `{amount_minor, currency, exponent}`.
The parser must tolerate unknown `kind`, `severity` and extra fields, and skip an entry it cannot read rather than fail the whole response.
Builder's call: `percent` is read as a number and rounded to the nearest whole one, so a fraction such as `12.5` shows as 13 % rather than dropping the entry.
A missing `is_active` counts as active.
If the response lists at least one limit but none can be read, the whole response is unreadable: the panel keeps the last numbers, marked stale, with "Anthropic changed the usage format. An update is needed."
Reset times are rounded to the nearest minute, because the server jitters about a second either side of the boundary (`09:39:59.757`, `09:40:00.236`) and the clock time must never read a minute early.

Read the Keychain item by running `/usr/bin/security find-generic-password -s "Claude Code-credentials" -w`, not through `SecItemCopyMatching`.
When measured, that read returned without a prompt, presumably because Claude Code writes the item through `security` itself, so the item's access list already trusts it.
A direct Keychain API call from an ad hoc signed app would prompt, and the "Always Allow" grant would not survive the next release's new signature.
The builder must confirm the no-prompt behaviour from the installed app, not only from a terminal, before building more of source 1 than the read itself.
If the installed app does get a prompt, the builder's call is: claude.ai sign-in (source 2) becomes the primary source and is built first, and Claude Code's item is read only when the person turns on "Use Claude Code's login" in the panel, which explains that macOS may ask again after each update.
Record the result here either way.
The read has three outcomes: the item's value; no item (`security` exits 44), which means Claude Code is signed out; or a failure, including a read that has not finished after 10 seconds and is stopped, which says nothing about whether Claude Code is signed in and keeps the last numbers, marked stale.
Confirmed 2026-10-20 from the installed app (`/Applications/Gondar.app`, ad hoc signed, hardened runtime): reading the item through `security` raised no Keychain dialog, and the menu bar showed the live session percentage, matching a direct read of the usage endpoint.

The app never refreshes Claude Code's token itself, because refreshing rotates the refresh token and would leave Claude Code holding a dead one (the first anti-goal).
When the token is expired, the app reads the item again on each poll, since Claude Code may have refreshed it meanwhile; if it is still expired, it falls back to source 2 when signed in there, and otherwise shows the stale state with "Open Claude Code to refresh".

### Source 2: claude.ai sign-in

For people without Claude Code, and as the fallback above, the person signs in to claude.ai in a window inside the app (a `WKWebView` with its own persistent data store).
The app then reads the same numbers the claude.ai Settings → Usage page reads, with that web session's cookies.
That endpoint has not been measured yet: the builder's first task is to sign in, find the request the Usage page makes and the organisation it is scoped to, and record its shape here before writing the parser.
Both sources must map into one model, so the UI never knows which one answered.
If the claude.ai response turns out to lack the `limits` list, the parser maps whatever it has into the same model and says in this document what is missing.
The measurement needs a real sign-in, so the builder asks the maintainer to sign in when step 3 starts; any fixture saved from it must have its account and organisation IDs replaced with fakes before it is committed, because the repo will be public.

A claude.ai login can belong to several organisations (a Team organisation and a personal one, say).
The builder's call: show the organisation that the claude.ai session marks as active or default; if there are several, the panel gets a small organisation picker that remembers the choice.
When source 2 is the fallback for source 1, it must use the organisation Claude Code is signed in to (`oauthAccount.organizationUuid`, below); if the claude.ai session has no access to that organisation, the fallback is not used and the app shows the stale state instead.

### Following the signed-in account

A person may switch between Claude accounts (with `/login` in Claude Code), and the app must simply show whichever account is signed in, with no setting to change.
Claude Code records the signed-in account in `~/.claude.json` under `oauthAccount` (measured 2026-10-20): `emailAddress`, `accountUuid`, `organizationUuid`, `organizationName`, `organizationType`, `seatTier`, among others.
Builder's call: the app reads it once at start and again whenever a watch on the home folder sees the file rewritten (debounced by a second), not on every poll, so a switch shows within seconds rather than at the next poll.
When `accountUuid` or `organizationUuid` changes, the app throws away the previous account's numbers at once and polls immediately; it must never show one account's numbers under another account's name, even for a moment, and shows a loading state instead.
The Keychain token itself carries no readable account ID, so the builder checks that it belongs to the account in `~/.claude.json` (the `api.anthropic.com/api/oauth/profile` endpoint is the first thing to try, once per token, not every poll); if the two disagree in the middle of a switch, the app waits for the next read rather than guessing.
Builder's call: it waits a minute and checks again, twice; the third disagreement in a row shows "Waiting for Claude Code to finish switching accounts." with the last numbers marked stale, and counts as a failed poll so backoff applies, because a switch that never settles (an organisation switch on the same token, say) would otherwise call the profile endpoint every minute and show an endless spinner.
The count resets as soon as the two agree.
Measured 2026-10-20: `GET api.anthropic.com/api/oauth/profile` with the same headers returns `account.uuid` and `organization.uuid`, and both matched `~/.claude.json`'s `accountUuid` and `organizationUuid`; it also gives `account.email`, `organization.name`, `organization.organization_type` (for example `claude_max`), `rate_limit_tier` and `seat_tier`.
A scrubbed copy is `fixtures/oauth-profile-2026-10-20.json`.
A bad token gets HTTP 401 from the usage endpoint.
So the profile endpoint is the account check, and its fields are what the header shows; `~/.claude.json` is only the trigger that says "re-check now".
The profile is fetched once per token (the app keeps a SHA-256 of the token in memory to tell), and again after the file names a different account.
For source 2, the account is whichever one is signed in to claude.ai in the app's own window, and switching means signing out and in there.

### Polling

Poll every two minutes, and once immediately when the panel or the floating window opens (builder's call on the exact interval, never more often than once a minute).
On a 429 or a network failure, back off and keep the last values, marked stale.
When the Mac sleeps, stop; on wake, poll once.

Builder's calls:
- The interval is 120 seconds.
- After a failure the wait is 120 s × 2^n for n failures in a row, capped at 30 minutes; a `Retry-After` only ever lengthens it, because the usage endpoint answers 429 with `retry-after: 0`.
- No poll runs within 60 seconds of the last attempt, the person's Refresh included; the time of the last attempt is saved, so the floor holds across relaunches.
- Opening the panel or the window does not poll while backing off after a failure, since the scheduled retry handles that and an extra request would prolong a rate limit.
- An expired token is not counted as a failure: the Keychain is read again at the next interval.
- A refused token (HTTP 401 or 403) is not counted as a failure either, because the fix is local: the app keeps reading the Keychain every interval and does not call the API again until the token's fingerprint changes, showing "Claude Code's login was refused. Sign in to Claude Code again." meanwhile.

## Interface

Colours are PortGlimpse's, from `portglimpse/App/Sources/Theme.swift` (which takes them from TickThock's dark tokens): page `#16130F`, panel `#201B17`, raised `#2A241F`, text `#F6EDE3`, soft text `#D8CBBD`, muted `#A8998A`, lines `#342C25` / `#4A3F35`, amber `#F48E48`, amber face `#FFB067 → #EE8237`, text on amber `#1B1815`, amber tint `#2C211A` / `#4D3424`.
Dark appearance only, as in PortGlimpse.
Copy PortGlimpse's `Theme.swift` and its floating window controller as the starting point rather than reinventing them.

### Menu bar

A small mark followed by the session percentage, for example `12%`.
The text turns amber when the session's `severity` is not `normal`, or at 80 % if `severity` never changes (builder's call on the exact rule, written into this document).
Builder's call: amber when `severity` is anything but `normal`, or when the percentage is 80 or more.
That rule is the menu bar's own; the rows colour their percentages by level instead (see the panel).
When there is no usable data, the mark shows alone with a dash.
A stale number is drawn muted, whatever its percentage, so it never looks current.

### The panel

Opened by clicking the menu bar item; a window-style `MenuBarExtra`, as in PortGlimpse.
A header with the signed-in account's email and organisation name, the plan (from `subscriptionType` and `rateLimitTier` where known, for example "Max · Max 20x") and "Updated 1 min ago".
Builder's call: the source line ("From Claude Code" or "From claude.ai") sits in the header, under the age, rather than in the footer.
The floating window does not show the email: it is kept as minimal as possible (decided 2026-10-20), so a switch shows in the panel.
One row per limit, in the order the source gives: a name ("Current session", "Weekly · all models", "Weekly · Fable"), a bar, the percentage, and "Resets in 1 h 36 m · 11:20 PM" (the clock time in the Mac's own format, with the date when it is not today).
Bars are amber; a limit that is not active is drawn muted.
The percentage is coloured by its level (decided on 2026-10-20): green `#7BC47F` under 50 %, amber `#F48E48` from 50 to 79 %, and red `#F26B5B` at 80 % and over or whenever `severity` is not `normal`.
A limit that is not active keeps its level colour, so the colour always means the level.
Each colour is at least 4.5:1 on the panel `#201B17` (8.2, 7.2 and 5.7).
If extra usage is enabled, a last row shows spend against its limit in its own currency.
Builder's call: when that limit is zero, the row shows the spend alone, as "<amount> used", since a zero cap is no limit worth comparing with.
A footer with "Pop out" (opens the floating window), "Refresh", a source line ("From Claude Code" or "From claude.ai"), "Sign in to claude.ai" / "Sign out", "Launch at login", and "Quit".
As built, the footer holds Settings (a menu with "Launch at login" and, once the repo is public, "Check for updates"), "Pop out", "Refresh" and "Quit"; "Sign in to claude.ai" and "Sign out" come with source 2.

### The floating window

The same limits as the panel, as minimal as possible (decided on 2026-10-20: no graph): always on top, on every Space and over full-screen apps, resizable, reopening at its last position and size.
Each limit is one line: the name, the percentage in IBM Plex Mono, right-aligned, and the countdown, muted ("1 h 36 m").
There are no bars, no account header, no extra usage row and no footer; those all stay in the panel.
The title area holds the traffic lights and "Gondar" in Bricolage Grotesque (the name came back on 2026-10-20).
A passed reset reads "Resetting now" and a limit without one reads "No reset time".
The percentage is coloured by its level, as in the panel.
Builder's call: it cannot be made narrower than 272 points, which fits "Weekly · all models", "100%" and "Resetting now" on one line, nor shorter than one line; shorter than its rows, it scrolls.
The first time it opens, it fits its height to its rows once, keeping its top edge and staying on the screen; after that, or as soon as the person moves or resizes it, the saved frame wins.
Closing it does not quit the app.
It remembers whether it was open and reopens at launch if it was.

### Stale numbers and errors

The builder's call on how stale states read: the numbers stay, the menu bar number turns muted, and the panel's header shows how old they are ("Updated 6 min ago") with the reason under it in amber.
The floating window shows one line above its rows instead, with the age muted and the reason in amber; while loading it shows a small spinner, and without numbers the reason alone.
As a backstop, numbers that no poll has replaced for longer than two intervals and a minute (300 seconds) are shown as stale with "Not updated for several minutes.", even when no failure explains it, so old numbers can never look current.
Without numbers to keep, the reason shows alone in place of the rows.
The reasons:
- "Sign in to Claude Code." — no Keychain item; the previous account's numbers are dropped.
- "Couldn't read Claude Code's login from the Keychain." — the read failed, timed out or was not in the expected shape.
- "Open Claude Code to refresh." — the token has expired.
- "Claude Code's login was refused. Sign in to Claude Code again." — HTTP 401 or 403.
- "Asked too often. Trying again shortly." — HTTP 429.
- "Offline." — no network, or the request did not complete.
- "Anthropic changed the usage format. An update is needed." — a response the parser cannot read.
- "Waiting for Claude Code to finish switching accounts." — the token and `~/.claude.json` disagreed three polls in a row.
- "Not updated for several minutes." — the backstop above.

### Icon

A new mark in PortGlimpse's colourway, the same way PortGlimpse's amber colon sits on TickThock's dark tile: an amber gauge or partly filled bar on the dark tile `#221E1B`.
That is the builder's starting point, not a settled choice; the maintainer settles it.
It is used in the menu bar in full colour at 18 points, as an app icon rendered by a `make-icon.swift` script like PortGlimpse's, and later on the product page.

The first cut, still the maintainer's to settle, has one geometry in `App/Sources/GaugeMark.swift`, shared by the menu bar and `scripts/make-icon.swift`:
- **Menu bar:** an 18-point tile inset 0.5 with a 4-point corner, as PortGlimpse's.
  On it is a 240° arc open at the bottom, with radius 4.8 points, a 2.4-point stroke and round ends, centred at (9, 8).
  The track is `#4A3F35` and amber `#F48E48` fills 60 % of it from the left end over the top.
- **App icon:** the same mark on the macOS grid (an 824-point tile inset 100 in 1024, corner 185), scaled by 824 / 18 about the centre, as PortGlimpse scales its colon.
  It is re-rendered with `./scripts/make-icon.sh`.

## How it is built

- Swift 6, SwiftUI, XcodeGen (`project.yml`; the generated `.xcodeproj` is gitignored), macOS 14 or later.
- A `GondarCore` Swift package holds every rule (credential parsing, both response parsers, the limit model, countdown and severity formatting, the polling schedule) with Foundation only and unit tests, recorded responses as fixtures; `App/` stays a thin SwiftUI shell.
  This is PortGlimpse's layout and its `scripts/test.sh` gate.
- An accessory app (no Dock icon), with "Launch at login" through `SMAppService`.
- Not sandboxed, because it runs `/usr/bin/security`.
- Tokens and cookies are never written to logs, files or `UserDefaults`, and travel only to `api.anthropic.com` and `claude.ai`.
- A daily update check, copied from PortGlimpse's `UpdateChecker`, against the public repo's latest GitHub release; it sends no credentials and shows "Update available" in the panel. Until the repo exists it is built but switched off.

## Distribution

Exactly the PortGlimpse and Komizo model: ad hoc signed, built and released by GitHub Actions on a `v<version>` tag, installed with `curl -fsSL https://zewify.com/<name>/install.sh | sh` (a redirect on the web server that serves zewify.com to `scripts/install.sh` on `main`), with product pages at `zewify.com/<name>/` in the zewify repo.
Not the Mac App Store, because a sandboxed app cannot run `security` against Claude Code's item; claude.ai sign-in alone would allow it, but source 1 is the main source.
Free, with no Pro tier.
A public, source-available repo in the `Zewify` org (no licence file, never called open source), authored `Zewify <dev@zewify.com>` (set in this repo's git config) and checked against `~/.config/zewify/identity-denylist` the way PortGlimpse is.
Until the real name is picked, the repo stays local on `main` with no remote, and the zewify site and installer are not started.

The app name must not contain "Claude" (Anthropic's trademark); describing it as "for Claude" in copy is the builder's starting assumption, still to be confirmed.
Using Claude logins from a third-party app is a grey area with Anthropic; reading usage only, never prompts, keeps it on the safe side, and a free, unpromoted app keeps it low-profile.

## Order of work

1. The Core, with source 1 and fixtures from the measured response, and the menu bar and panel against it — this alone solves the core problem.
2. The floating window.
3. Source 2, after measuring the claude.ai endpoint.
4. The icon, then the name, then the repo, release workflow and zewify.com pages.

## Left to the builder

Layout details, the polling interval within the limits above, row wording beyond the examples, how stale states read, and the error copy.
