# Gondar

Gondar is a free Mac menu bar app that shows how much of your Claude usage limits you have used, and when each one resets.

## What it shows

- **Menu bar** — the current session's usage as a percentage, always in view.
- **Panel** — click the percentage for every limit: the session, the weekly limits and any per-model ones, each with a bar, the percentage used, and when it resets.
- **Pop-out window** — "Pop out" in the panel opens an always-on-top window with one line per limit, above other windows on every Space and over full-screen apps.

Gondar follows the account Claude Code is signed in to: sign in to another account and Gondar switches to it.

## Install

```
curl -fsSL https://zewify.com/gondar/install.sh | sh
```

Run the same command again to update.
The installer never uses sudo; it puts Gondar in `/Applications` (or `~/Applications` when that is not writable) and opens it.

## Requirements

- macOS 14 or later.
- Claude Code, signed in on this Mac with a Claude subscription.

Gondar reads Claude Code's login from the Keychain by running macOS's own `security` tool, and uses it only to ask `api.anthropic.com` for the account's usage and profile.
It never sends prompts, never refreshes or changes the login, and never writes to the Keychain or to Claude Code's files.

## Live numbers from Claude Code's status line (optional)

On its own, Gondar asks Anthropic for the numbers every five minutes.
Claude Code also reports the same limits to its status line after each reply; route the status line through Gondar's bundled `gondar-feed` tool and the numbers update while you work.

In `~/.claude/settings.json`, change only `statusLine.command`: put the tool's path, in quotes, in front of the command you already have.
For example, a status line that runs `npx -y example-statusline` becomes:

```json
"statusLine": {
  "type": "command",
  "command": "\"/Applications/Gondar.app/Contents/MacOS/gondar-feed\" npx -y example-statusline"
}
```

Leave `padding`, `refreshInterval` and the other settings as they are.
`gondar-feed` passes its input to your command unchanged and returns its output and exit status, so the status line looks the same.
With no status line yet, the command can be the tool's path alone; it shows nothing and only feeds Gondar.
Settings → "Connect Claude Code's status line…" in the panel works out the exact command for your settings file.
Gondar only reads that file; you make the change.

## Privacy

Gondar keeps two files in `~/Library/Application Support/Gondar/`, readable only by you:

- `last.json` — the last numbers shown, so a relaunch shows them at once: the account and organisation IDs, the limits and when they were read. Never a token, an email address, an organisation name or a plan.
- `statusline.json` — written by `gondar-feed`: only the rate limits from Claude Code's status line input, when each was received, and SHA-256 hashes of session IDs with each session's API time, so an idle session's repeated numbers are not taken as new. Nothing else from the status line input (folders, transcripts, models, costs) is written.

The login token is never logged, written to disk or sent anywhere but `api.anthropic.com`.
The only other network request is an optional daily check for a newer release on GitHub, which sends no credentials; turn it off under Settings → "Check for updates".

## Build from source

You need Xcode and XcodeGen (`brew install xcodegen`).

- `./scripts/test.sh` runs the tests and builds the app.
- `./scripts/install-local.sh` builds a Release copy into `/Applications` and opens it.

## Not affiliated with Anthropic

Gondar is made by Zewify and is not affiliated with, endorsed by or sponsored by Anthropic.
Claude and Claude Code are trademarks of Anthropic.

## Licence

Gondar is source available, not open source.
The source is published so you can read exactly what the app does, and build it for yourself.
Zewify keeps all rights to it; no licence to copy, modify or redistribute it is granted.

The bundled fonts — Bricolage Grotesque, Figtree and IBM Plex Mono — are under the SIL Open Font License; their licences are in `App/Resources/Fonts`.
