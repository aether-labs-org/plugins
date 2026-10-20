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
      case "$f" in .agents/last-green | .agents/last-seen | .agents/last-fail | .agents/last-run*.log | .agents/.gate-lock/*) continue ;; esac
      printf '%s %s\n' "$f" "$(git hash-object -- "$f" 2>/dev/null)"
    done
  } | git hash-object --stdin
}

# normalise_report: drops timings and the verdict line so two runs of the same failure compare equal.
normalise_report() {
  sed -e '/^gate: /d' -e 's/[[:space:]]*[0-9][0-9.]*m\{0,1\}s[[:space:]]*$//'
}

loop_guard_message() {
  printf '{"systemMessage":"%s"}\n' "$(json_escape "keel gate is still failing with the same result; stopping the loop. Run make gate-fast to see it.")"
}

_claude_stop_main() {
  local input header fp lock out rc report norm last active=0
  input="$(cat)"
  cd "$(dirname "$0")/../.." || return 0
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  mkdir -p .agents
  printf '%s' "$input" | grep -Eq '"stop_hook_active"[[:space:]]*:[[:space:]]*true' && active=1

  # .agents/last-green: the tree the gate last passed on. .agents/last-seen: the tree the hook last
  # looked at, whatever the result. Both include HEAD, so a commit made this turn is a change.
  fp="$(tree_fingerprint)"
  if [ -f .agents/last-green ] && [ "$(cat .agents/last-green)" = "$fp" ]; then
    return 0
  fi
  if [ -f .agents/last-seen ] && [ "$(cat .agents/last-seen)" = "$fp" ]; then
    # Nothing changed since a failing run that was already reported.
    [ "$active" = 1 ] && loop_guard_message
    return 0
  fi
  if [ ! -f .agents/last-seen ] && [ -z "$(git status --porcelain --untracked-files=all 2>/dev/null | grep -vE ' \.agents/(last-green|last-seen|last-fail|last-run[^/]*\.log|\.gate-lock/)')" ]; then
    # First look, nothing uncommitted: nothing this session changed. Remember the tree and stay quiet.
    printf '%s\n' "$fp" > .agents/last-seen
    return 0
  fi

  lock=".agents/.gate-lock"
  if [ -d "$lock" ] && [ -n "$(find "$lock" -maxdepth 0 -mmin +10 2>/dev/null)" ]; then
    rmdir "$lock" 2>/dev/null
  fi
  mkdir "$lock" 2>/dev/null || return 0
  # shellcheck disable=SC2064
  trap "rmdir '$lock' 2>/dev/null" EXIT

  out="$(bash scripts/gate.sh fast 2>&1)"; rc=$?
  printf '%s\n' "$fp" > .agents/last-seen
  case "$rc" in
    0)
      printf '%s\n' "$fp" > .agents/last-green
      rm -f .agents/last-fail
      return 0 ;;
    1) ;;
    *)
      printf '{"systemMessage":"%s"}\n' "$(json_escape "keel gate could not run (scripts/gate.sh exited $rc). Run make gate-fast to see why.")"
      return 0 ;;
  esac

  report="$(printf '%s\n' "$out" | head -40)"
  norm="$(printf '%s\n' "$report" | normalise_report)"
  last=""
  [ -f .agents/last-fail ] && last="$(cat .agents/last-fail)"
  printf '%s\n' "$norm" > .agents/last-fail
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
