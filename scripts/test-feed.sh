#!/usr/bin/env bash
# Tests gondar-feed as Claude Code runs it: from inside the built app, under a throwaway HOME.
# Usage: scripts/test-feed.sh [path to gondar-feed]; the default is the Debug app's copy.
set -euo pipefail
cd "$(dirname "$0")/.."
feed="${1:-$PWD/build/DerivedData/Build/Products/Debug/Gondar.app/Contents/MacOS/gondar-feed}"
[[ -x "$feed" ]] || { echo "FAIL: no executable at $feed" >&2; exit 1; }

home="$(mktemp -d)"
trap 'chmod -R u+w "$home" 2>/dev/null; rm -rf "$home"' EXIT
export HOME="$home"
support="$home/Library/Application Support"
file="$support/Gondar/statusline.json"
failures=0
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }

input='{"session_id":"s-1","transcript_path":"/x/t.jsonl","cwd":"/private/project","model":{"id":"m"},"cost":{"total_cost_usd":1.5},"rate_limits":{"five_hour":{"used_percentage":42.4,"resets_at":1790000000},"seven_day":{"used_percentage":7,"resets_at":1790500000}}}'

# The wrapped command sees stdin unchanged, byte for byte.
out="$(printf '%s' "$input" | "$feed" cat)"
[[ "$out" == "$input" ]] || fail "cat did not echo stdin unchanged: $out"

# The written file: mode 600, folder 700, only the limits and the time.
[[ -f "$file" ]] || fail "no feed file written"
if [[ -f "$file" ]]; then
  [[ "$(stat -f %Lp "$file")" == 600 ]] || fail "file mode is $(stat -f %Lp "$file"), not 600"
  [[ "$(stat -f %Lp "$support/Gondar")" == 700 ]] || fail "folder mode is $(stat -f %Lp "$support/Gondar"), not 700"
  for word in cwd transcript_path session_id model cost private; do
    grep -q "$word" "$file" && fail "file contains $word"
  done
  grep -q '"five_hour"' "$file" || fail "file lacks five_hour"
  grep -q '"received_at"' "$file" || fail "file lacks received_at"
fi

# Input without limits (a new or API-key session) leaves the stored numbers alone.
before="$(cat "$file")"
printf '{}' | "$feed" true
printf '{"cwd":"/x","rate_limits":null}' | "$feed" true
[[ "$(cat "$file")" == "$before" ]] || fail "input without limits changed the file"

# A new window replaces the old; then an idle session re-sending an older, lower number for it does not lower it.
printf '{"rate_limits":{"five_hour":{"used_percentage":40,"resets_at":1790018000}}}' | "$feed" true
printf '{"rate_limits":{"five_hour":{"used_percentage":20,"resets_at":1790018000}}}' | "$feed" true
grep -q '"used_percentage":40' "$file" || fail "same window at 20 % replaced 40 %: $(cat "$file")"
grep -q '"seven_day"' "$file" || fail "a limit the input lacked was dropped"

# A temp file a killed writer left behind goes once it is a minute old; a fresh one stays.
touch -t 202001010000 "$support/Gondar/.statusline.json.99999.tmp"
touch "$support/Gondar/.statusline.json.99998.tmp"
printf '{}' | "$feed" true
[[ ! -e "$support/Gondar/.statusline.json.99999.tmp" ]] || fail "a stale temp file was left"
[[ -e "$support/Gondar/.statusline.json.99998.tmp" ]] || fail "a fresh temp file was removed"
rm -f "$support/Gondar/.statusline.json.99998.tmp"

# A held lock (a writer stopped by Ctrl-Z) delays the wrapped command by at most about 100 ms and skips the write.
lock="$support/Gondar/statusline.lock"
before="$(cat "$file")"
perl -e 'use Fcntl ":flock"; open F, ">>", $ARGV[0]; flock F, LOCK_EX; $| = 1; print "held\n"; sleep 5' "$lock" > "$home/held" &
holder=$!
until [[ -s "$home/held" ]]; do perl -e 'select undef, undef, undef, 0.01'; done
start=$(perl -MTime::HiRes=time -e 'printf "%d", time * 1000')
out="$(printf '{"rate_limits":{"five_hour":{"used_percentage":99,"resets_at":1790036000}}}' | "$feed" echo ran)"
end=$(perl -MTime::HiRes=time -e 'printf "%d", time * 1000')
kill "$holder"; wait "$holder" 2>/dev/null || true
[[ "$out" == ran ]] || fail "held lock: wrapped command printed '$out'"
(( end - start < 300 )) || fail "held lock: took $((end - start)) ms"
held_ms=$((end - start))
[[ "$(cat "$file")" == "$before" ]] || fail "held lock: the file was written anyway"

# A closed stdin still runs the wrapped command.
out="$("$feed" echo ran <&-)" && status=0 || status=$?
[[ "$out" == ran && $status == 0 ]] || fail "closed stdin: got '$out', status $status"

# A large input reaches a child that never reads stdin without hanging.
big="$(head -c 2000000 /dev/zero | tr '\0' 'a')"
printf '%s' "$big" | "$feed" true || fail "a child that ignores a large stdin did not exit 0"

# Exit status passes through, including death by a signal (128 + n).
printf '{}' | "$feed" sh -c 'exit 3' && status=0 || status=$?
[[ $status == 3 ]] || fail "exit status was $status, not 3"
printf '{}' | "$feed" sh -c 'kill -TERM $$' && status=0 || status=$?
[[ $status == 143 ]] || fail "signal exit status was $status, not 143"

# Stderr passes through and stays off stdout.
err="$(printf '{}' | "$feed" sh -c 'echo oops >&2' 2>&1 >/dev/null)"
[[ "$err" == oops ]] || fail "stderr was '$err', not 'oops'"

# Input that is not JSON still runs the wrapped command and leaves the file alone.
before="$(cat "$file" 2>/dev/null || true)"
out="$(printf 'not json' | "$feed" cat)"
[[ "$out" == "not json" ]] || fail "non-JSON input was not passed through: $out"
[[ "$(cat "$file" 2>/dev/null || true)" == "$before" ]] || fail "non-JSON input changed the file"

# A command that cannot be found fails like a shell would (127) and says so on stderr.
printf '{}' | "$feed" gondar-no-such-command 2>/dev/null && status=0 || status=$?
[[ $status == 127 ]] || fail "missing command exit status was $status, not 127"

# An unwritable Application Support folder still runs the wrapped command.
rm -rf "$support/Gondar"
chmod 555 "$support"
out="$(printf '%s' "$input" | "$feed" echo ran)" && status=0 || status=$?
[[ "$out" == ran && $status == 0 ]] || fail "read-only folder: got '$out', status $status"
chmod 755 "$support"

# With no wrapped command: no output, exit 0, and the file is still written.
out="$(printf '%s' "$input" | "$feed")" && status=0 || status=$?
[[ -z "$out" && $status == 0 ]] || fail "no arguments: got '$out', status $status"
[[ -f "$file" ]] || fail "no arguments: no feed file written"

# One call stays well under 100 ms (best of five, so a cold cache does not decide it).
best=999999
for _ in 1 2 3 4 5; do
  start=$(perl -MTime::HiRes=time -e 'printf "%d", time * 1000')
  printf '%s' "$input" | "$feed" true
  end=$(perl -MTime::HiRes=time -e 'printf "%d", time * 1000')
  (( end - start < best )) && best=$((end - start))
done
(( best < 100 )) || fail "one call took ${best} ms"

if (( failures > 0 )); then
  echo "test-feed: $failures failure(s)" >&2
  exit 1
fi
echo "test-feed: all passed (fastest call ${best} ms, ${held_ms} ms past a held lock)"
