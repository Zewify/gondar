# Gondar

A free Mac menu bar app that shows how much of your Claude usage limits is left; a Zewify product.
Design: `docs/superpowers/specs/2026-10-20-gondar-design.md`.
Plan: `docs/superpowers/plans/2026-10-20-gondar-app.md`.

## Layout

- `Core/` — the `GondarCore` Swift package: every rule, Foundation only.
- `App/` — the thin SwiftUI menu bar app.
- `Feed/` — `gondar-feed`, a command-line tool shipped at `Gondar.app/Contents/MacOS/gondar-feed`.
  Claude Code's status line command wraps through it: it merges only `rate_limits`, each limit's own received time, and a SHA-256 of the session ID with its API time into `~/Library/Application Support/Gondar/statusline.json` (atomic, 0600). Numbers count only when the session's `cost.total_api_duration_ms` rose since its previous input, so idle re-sends and a pre-`/login` session's old numbers never look fresh; a genuine report replaces each limit it carries outright (the app compares windows with the API's). Then it runs the wrapped command with the same stdin, its output inherited and its exit status passed through.
  The person wires it by hand in `~/.claude/settings.json`, changing only `statusLine.command` (leave `padding`, `refreshInterval` and the rest as they are) to the tool's path followed by the existing command, for example `"/Applications/Gondar.app/Contents/MacOS/gondar-feed" npx -y example-statusline`. Gondar never edits that file.

## Commands

- `./scripts/test.sh` — core tests, the installer tests (`scripts/test-install.sh`), an app build, then `scripts/test-feed.sh` (the built app's `gondar-feed`, under a temp `HOME`). Run before every commit; the exit code is the verdict.
- `./scripts/package.sh` — the release build: Release, universal (the app and `gondar-feed` both checked with `lipo`), `codesign --verify --deep --strict`, then the zip, its SHA-256 and the release notes in `build/release/`. The Release workflow runs it; locally it is only a dry run.
- `./scripts/build.sh [Debug|Release]` — generates the project and builds; prints the app path.
- `./scripts/install-local.sh` — a Release build copied to `/Applications` and launched.
- `open -n build/DerivedData/Build/Products/Debug/Gondar.app --args -GondarDemo stale` — a Debug build with made-up stale numbers and no network, opening the pop-out; it saves no window frame or flags, since it shares the installed app's defaults. Compiled out of Release.
- `./scripts/make-icon.sh` — re-renders AppIcon.appiconset from the mark in `App/Sources/GaugeMark.swift`; edit that file, not the PNGs.
- `project.yml` is the XcodeGen spec; the `.xcodeproj` is generated and gitignored, so never edit or commit it.

## Rules that are not obvious

- Identity check, run before every commit; it must print nothing: `grep -v '^#' ~/.config/zewify/identity-denylist | git grep -niEf /dev/stdin -- . ':!*.ttf'`.
- Zewify rule: nothing in the app, repo, commits or docs may identify the person who builds it.
- Commits use the repo's configured author (`Zewify`); never override it and never add co-author, "Generated with" or session trailers.
- The Core imports Foundation only — never AppKit, SwiftUI, Security or WebKit.
- Never refresh Claude Code's token, and never write to the Keychain or `~/.claude.json`.
- Tokens are never logged, written to disk or `UserDefaults`, or sent anywhere but `api.anthropic.com` and `claude.ai`.
- Poll every 300 seconds (five minutes; decided 2026-10-20, up from 120 s) when the status line feed is not live, and every 15 minutes while it is; after a failure back off 120 s × 2^n (240, 480, 960, then 1800 s), re-read the Keychain every 120 s without a usable token, and call numbers stale after 360 s (six minutes, longer than the regular interval so a check never flashes stale; each its own constant in `PollSchedule`, kept on purpose, 2026-10-20); never more often than once per 60 seconds, refreshes the person asks for included.
- "Claude" is never part of the product's name; "Claude Code" and "claude.ai" may be named as sources.
- Releases are ad hoc signed and installed only with `scripts/install.sh` (`curl -fsSL https://zewify.com/gondar/install.sh | sh`, a redirect on the web server that serves zewify.com to that file on `main`, so a push to `main` changes the live installer at once). The installer replaces the whole app, so the bundled `gondar-feed` updates with it at the same path, and it refuses a download whose app lacks `gondar-feed`.
- To release: bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`, write `docs/releases/<version>.md` (it becomes the release's "What's new"; every line must be true of the code), push `main` and wait for its Tests run to pass, then `git tag v<version>` on `main` and push the tag. The Release workflow runs one at a time and refuses a tag off `main` or one that doesn't match `MARKETING_VERSION`; it tests, packages and publishes the zip and its `.sha256`. Then bump `latestVersion` for Gondar in the zewify repo.
- The app's `UpdateChecker` asks `https://api.github.com/repos/Zewify/gondar/releases/latest` once a day and offers the install command; setting either constant to nil switches it off.
- `./scripts/test-install.sh` never touches the real app: it stubs `is_running`, `quit_app` and `launch_app` after sourcing the installer, and installs into a temp folder.
- Source available, not open source: no licence file, all rights kept by Zewify; never call it open source.
