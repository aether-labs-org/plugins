#!/usr/bin/env bash
# Managed by keel-harness. Edit only between the keel:repo-specific markers - see .agents/README.md.
# claude-stop.sh - Claude Code Stop-hook adapter. Runs the fast gate when the working tree changed
# since the last green run and hands a failing report (with each sensor's guidance) back to Claude
# as additionalContext. Never blocks: it always exits 0 and never emits a blocking decision.
# When sourced it defines functions only.

# json_escape STRING -> the string escaped for a JSON string literal (no surrounding quotes).
json_escape() {
  printf '%s\n' "$1" | LC_ALL=C awk '
    BEGIN {
      for (i = 1; i < 32; i++) esc[sprintf("%c", i)] = sprintf("\\u%04x", i)
      esc["\t"] = "\\t"; esc["\r"] = "\\r"; esc["\b"] = "\\b"; esc["\f"] = "\\f"
    }
    {
      out = ""; n = length($0)
      for (k = 1; k <= n; k++) {
        c = substr($0, k, 1)
        if (c == "\\") out = out "\\\\"
        else if (c == "\"") out = out "\\\""
        else if (c in esc) out = out esc[c]
        else out = out c
      }
      printf "%s%s", (NR > 1 ? "\\n" : ""), out
    }'
}

# tree_fingerprint -> hash of HEAD, the tracked diff, and the path and hash of every untracked file.
# HEAD is in it so that a change committed during the turn still counts as a change. keel's own
# state files are excluded so writing them never changes the fingerprint.
tree_fingerprint() {
  {
    git rev-parse -q --verify HEAD 2>/dev/null
    git diff HEAD --binary 2>/dev/null || git diff --cached --binary 2>/dev/null
    git ls-files --others --exclude-standard -z 2>/dev/null | while IFS= read -r -d '' f; do
      case "$f" in .agents/run/* | .agents/last-green | .agents/last-seen | .agents/last-fail | .agents/last-run*.log | .agents/.gate-lock/*) continue ;; esac
      printf '%s %s\n' "$f" "$(git hash-object -- "$f" 2>/dev/null)"
    done
  } | git hash-object --stdin
}

# normalise_report: drops timings and the verdict line so two runs of the same failure compare equal.
normalise_report() {
  sed -e '/^gate: /d' -e 's/[[:space:]]*[0-9][0-9.]*m\{0,1\}s[[:space:]]*$//'
}

# note_failures REPORT SESSION: counts, per sensor, the sessions in a row in which it failed the gate
# (.agents/run/fail-streaks: sensor<TAB>count<TAB>last session). A gate run in which a sensor does not
# fail starts its count over. At the third session in a row it writes the lesson
# .agents/run/learnings/<date>-sensor-<id>-fails-every-session.md and raises its Seen: line afterwards
# (contracts/learnings.md). Best effort: it never prints, and the caller ignores its status.
note_failures() {
  local report="$1" session="$2" streaks=.agents/run/fail-streaks failing id line count last new="" lf guidance dir=.agents/run/learnings
  case "$session" in '' | *[!A-Za-z0-9_.-]*) return 0 ;; esac
  failing="$(printf '%s\n' "$report" | awk '($1 == "x" || $1 == "✗") && $3 ~ /^\[/ { print $2 }')"
  for id in $failing; do
    case "$id" in '' | *[!A-Za-z0-9_.-]*) continue ;; esac
    count=0; last=""
    if [ -f "$streaks" ]; then
      line="$(awk -F'\t' -v id="$id" '$1 == id { print $2 "\t" $3; exit }' "$streaks" 2>/dev/null)"
      count="${line%%$'\t'*}"; last="${line#*$'\t'}"
      case "$count" in '' | *[!0-9]*) count=0; last="" ;; esac
    fi
    if [ "$last" != "$session" ]; then
      count=$((count + 1))
      if [ "$count" -ge 3 ] && mkdir -p "$dir" 2>/dev/null; then
        lf="$(ls "$dir"/*-sensor-"$id"-fails-every-session.md 2>/dev/null | head -1)"
        if [ -n "$lf" ]; then
          printf '%s\n' "$(sed "s/^Seen: .*/Seen: $count/" "$lf")" > "$lf" 2>/dev/null
        else
          guidance="$(printf '%s\n' "$report" | awk -v id="$id" 'f && /^  guidance:/ { sub(/^  guidance:[ ]*/, ""); print; exit } f && !/^  / { f = 0 } $2 == id && !/^  / { f = 1 }')"
          {
            printf 'Source: gate failure - sensor %s failed in %s sessions in a row (Stop hook)\n' "$id" "$count"
            printf 'Seen: %s\n' "$count"
            printf 'Proposed: rule\n\n'
            printf 'The %s sensor failed at the end of %s sessions in a row, so agents keep missing what it checks.\n' "$id" "$count"
            printf 'Its guidance: %s\n\n' "${guidance:-(none printed)}"
            printf 'Decide: sharpen the AGENTS.md line or docs/ section behind this sensor (or write one), add an exemplar,\n'
            printf 'record an ADR if the sensor itself is wrong, or discard this lesson. /keel-harness:assess proposes the route.\n'
          } > "$dir/$(date -u +%Y-%m-%d)-sensor-$id-fails-every-session.md" 2>/dev/null
        fi
      fi
    fi
    new="${new}${id}"$'\t'"${count}"$'\t'"${session}"$'\n'
  done
  printf '%s' "$new" > "$streaks" 2>/dev/null
  return 0
}

loop_guard_message() {
  printf '{"systemMessage":"%s"}\n' "$(json_escape "keel gate is still failing with the same result; stopping the loop. Run make gate-fast to see it.")"
}

_claude_stop_main() {
  local input header fp lock out rc report norm last session active=0
  input="$(cat)"
  cd "$(dirname "$0")/../.." || return 0
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  mkdir -p .agents/run
  printf '%s' "$input" | grep -Eq '"stop_hook_active"[[:space:]]*:[[:space:]]*true' && active=1
  session="$(printf '%s' "$input" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"

  # .agents/run/last-green: the tree the gate last passed on. .agents/run/last-seen: the tree the hook last
  # looked at, whatever the result. Both include HEAD, so a commit made this turn is a change.
  fp="$(tree_fingerprint)"
  if [ -f .agents/run/last-green ] && [ "$(cat .agents/run/last-green)" = "$fp" ]; then
    return 0
  fi
  if [ -f .agents/run/last-seen ] && [ "$(cat .agents/run/last-seen)" = "$fp" ]; then
    # Nothing changed since a failing run that was already reported.
    [ "$active" = 1 ] && loop_guard_message
    return 0
  fi
  if [ ! -f .agents/run/last-seen ] && [ -z "$(git status --porcelain --untracked-files=all 2>/dev/null | grep -vE ' \.agents/(run/|last-green|last-seen|last-fail|last-run[^/]*\.log|\.gate-lock/)')" ]; then
    # First look, nothing uncommitted: nothing this session changed. Remember the tree and stay quiet.
    printf '%s\n' "$fp" > .agents/run/last-seen
    return 0
  fi

  lock=".agents/run/.gate-lock"
  if [ -d "$lock" ] && [ -n "$(find "$lock" -maxdepth 0 -mmin +10 2>/dev/null)" ]; then
    rmdir "$lock" 2>/dev/null
  fi
  mkdir "$lock" 2>/dev/null || return 0
  # shellcheck disable=SC2064
  trap "rmdir '$lock' 2>/dev/null" EXIT

  out="$(bash scripts/gate.sh fast 2>&1)"; rc=$?
  printf '%s\n' "$fp" > .agents/run/last-seen
  case "$rc" in 0 | 1) note_failures "$out" "$session" > /dev/null 2>&1 || true ;; esac
  case "$rc" in
    0)
      printf '%s\n' "$fp" > .agents/run/last-green
      rm -f .agents/run/last-fail
      return 0 ;;
    1) ;;
    *)
      printf '{"systemMessage":"%s"}\n' "$(json_escape "keel gate could not run (scripts/gate.sh exited $rc). Run make gate-fast to see why.")"
      return 0 ;;
  esac

  report="$(printf '%s\n' "$out" | head -40)"
  norm="$(printf '%s\n' "$report" | normalise_report)"
  last=""
  [ -f .agents/run/last-fail ] && last="$(cat .agents/run/last-fail)"
  printf '%s\n' "$norm" > .agents/run/last-fail
  if [ "$active" = 1 ] && [ "$norm" = "$last" ]; then
    loop_guard_message
    return 0
  fi
  header="keel gate failed after your changes. Fix each failing sensor below by following its guidance: block, then finish. Do not edit tests, .agents/baselines/ or .agents/state.yml to make it pass."
  printf '{"hookSpecificOutput":{"hookEventName":"Stop","additionalContext":"%s"}}\n' "$(json_escape "$header
$report")"
  return 0
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  _claude_stop_main
  exit 0
fi
