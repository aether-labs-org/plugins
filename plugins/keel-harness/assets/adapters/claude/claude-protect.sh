#!/usr/bin/env bash
# Managed by keel-harness. Edit only between the keel:repo-specific markers - see .agents/README.md.
# claude-protect.sh - Claude Code PreToolUse adapter for Write, Edit and NotebookEdit. It reads the
# consequence map (.agents/consequence.yml) and decides for the file the tool is about to change:
#   harness path, no current build/rules approval -> deny, naming the approved route
#   harness path, current approval                 -> no output (the normal permission flow runs)
#   any other mapped category (auth, data, ...)    -> ask, naming the category
#   no match, no map, anything it cannot parse     -> no output
# It never exits non-zero and never prints anything but one decision object: a hook that errors would
# block every edit in the session, and the deny decision is the protection, not the exit code. When it
# cannot read the payload it says nothing and the normal permission flow runs. It does not see Bash
# commands that write harness paths; `guard` in the gate, pre-commit and CI catches loosenings.
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

# json_string KEY JSON -> the decoded value of the first string-valued "KEY" in JSON, else nothing.
# A quote inside a JSON string is always written \", so "KEY": cannot be forged from another string's
# content. Decodes \" \\ \/ and \u00XX for ASCII; any other escape is dropped (a path has none).
json_string() {
  local raw v out="" i=0 c hex pat
  pat='"'"$1"'"[[:space:]]*:[[:space:]]*"([^"\\]|\\.)*"'
  # Newlines become spaces first, so a pretty-printed payload matches too; a raw newline cannot occur inside a JSON string.
  raw="$(printf '%s' "$2" | LC_ALL=C tr '\n\r' '  ' | LC_ALL=C grep -oE "$pat" 2>/dev/null | head -n 1)"
  [ -n "$raw" ] || return 0
  v="${raw#*:}"
  v="${v#"${v%%[![:space:]]*}"}"
  v="${v#\"}"; v="${v%\"}"
  while [ "$i" -lt "${#v}" ]; do
    c="${v:$i:1}"
    if [ "$c" = "\\" ]; then
      i=$((i + 1)); c="${v:$i:1}"
      case "$c" in
        '"' | '\' | /) out="$out$c" ;;
        u)
          hex="${v:$((i + 1)):4}"
          case "$hex" in
            00[0-7][0-9a-fA-F]) [ "$hex" = 0000 ] || out="$out$(printf "\\x${hex#00}")"; i=$((i + 4)) ;;
          esac ;;
      esac
    else
      out="$out$c"
    fi
    i=$((i + 1))
  done
  printf '%s' "$out"
}

# norm_path ABSOLUTE -> the path with ., .. and // resolved lexically (.. at / stays at /).
norm_path() {
  local seg n=0 i=0 out="" IFS=/
  local -a st=()
  set -f
  for seg in $1; do
    case "$seg" in
      '' | .) ;;
      ..) if [ "$n" -gt 0 ]; then n=$((n - 1)); unset "st[$n]"; fi ;;
      *) st[n]="$seg"; n=$((n + 1)) ;;
    esac
  done
  set +f
  while [ "$i" -lt "$n" ]; do out="$out/${st[$i]}"; i=$((i + 1)); done
  printf '%s\n' "${out:-/}"
}

# glob_to_ere GLOB -> an anchored extended regex. `**/` is zero or more directories, `**` crosses
# slashes, `*` and `?` stay inside one path segment, every other character is literal.
glob_to_ere() {
  local g="$1" re="" c i=0 len=${#1}
  while [ "$i" -lt "$len" ]; do
    c="${g:$i:1}"
    case "$c" in
      '*')
        if [ "${g:$i:2}" = '**' ]; then
          if [ "${g:$((i + 2)):1}" = / ]; then re="$re(.*/)?"; i=$((i + 3)); else re="$re.*"; i=$((i + 2)); fi
          continue
        fi
        re="${re}[^/]*" ;;
      '?') re="${re}[^/]" ;;
      '.' | '[' | ']' | '(' | ')' | '{' | '}' | '+' | '^' | '$' | '|' | '\') re="$re\\$c" ;;
      *) re="$re$c" ;;
    esac
    i=$((i + 1))
  done
  printf '^%s$' "$re"
}

# glob_match GLOB PATH -> 0 when the repository-relative PATH matches GLOB.
glob_match() {
  local re
  re="$(glob_to_ere "$1")"
  [[ $2 =~ $re ]]
}

# trim STRING -> without leading and trailing blanks.
trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# map_categories MAPFILE REL -> the categories REL belongs to, space separated. Lines are `category: glob`
# or `!glob` (removes matches from the category declared above it); the last line that matches wins.
map_categories() {
  local line cat glob cur="" got=" "
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in *[[:space:]]'#'*) line="${line%%[[:space:]]#*}" ;; esac
    line="$(trim "$line")"
    case "$line" in
      '' | '#'*) continue ;;
      '!'*)
        glob="$(trim "${line#!}")"
        [ -n "$cur" ] && [ -n "$glob" ] || continue
        if glob_match "$glob" "$2"; then got="${got/ $cur / }"; fi ;;
      *:*)
        cat="$(trim "${line%%:*}")"; glob="$(trim "${line#*:}")"
        case "$cat" in '' | *[!a-z0-9_-]*) continue ;; esac
        cur="$cat"
        [ -n "$glob" ] || continue
        if glob_match "$glob" "$2"; then
          case "$got" in *" $cat "*) ;; *) got="$got$cat " ;; esac
        fi ;;
    esac
  done < "$1"
  trim "$got"
}

# approval_current ROOT -> 0 when a build or rules flow in ROOT has a current approval: .applied exists
# and is not older than .approved, was written at most 2 hours ago, and the hash in .approved is the
# hash of the proposal on disk. This is what `keel plan`, `keel approve` and `keel apply` leave behind.
approval_current() {
  local d="$1/.agents/run/flow" s ah ch
  for s in build rules; do
    [ -f "$d/$s.proposal" ] && [ -f "$d/$s.approved" ] && [ -f "$d/$s.applied" ] || continue
    [ "$d/$s.approved" -nt "$d/$s.applied" ] && continue
    [ -n "$(find "$d/$s.applied" -mmin -120 2>/dev/null)" ] || continue
    ah="$(head -n 1 "$d/$s.approved" 2>/dev/null | cut -f1)"
    ch="$(git hash-object "$d/$s.proposal" 2>/dev/null)"
    [ -n "$ah" ] && [ "$ah" = "$ch" ] && return 0
  done
  return 1
}

# rel_under ROOT ABS -> ABS relative to ROOT, or nothing when ABS is not under ROOT.
rel_under() {
  case "$2" in "$1"/*) printf '%s\n' "${2#"$1"/}" ;; esac
}

_claude_protect_main() {
  local input tool p root rootp abs dir dirp base cand rel first="" cats c rest harness=0 reason
  input="$(cat)"
  [ -n "$input" ] || return 0
  tool="$(json_string tool_name "$input")"
  case "$tool" in '' | Write | Edit | NotebookEdit) ;; *) return 0 ;; esac
  p="$(json_string file_path "$input")"
  [ -n "$p" ] || p="$(json_string notebook_path "$input")"
  [ -n "$p" ] || return 0

  root="${CLAUDE_PROJECT_DIR:-}"
  { [ -n "$root" ] && [ -d "$root" ]; } || root="$(git rev-parse --show-toplevel 2>/dev/null)"
  [ -n "$root" ] || root="$PWD"
  [ -f "$root/.agents/consequence.yml" ] || return 0
  root="$(norm_path "$root")"
  rootp="$(cd "$root" 2>/dev/null && pwd -P)"

  case "$p" in /*) abs="$p" ;; *) abs="$root/$p" ;; esac
  abs="$(norm_path "$abs")"
  dir="$(dirname "$abs")"; base="$(basename "$abs")"
  dirp="$(cd "$dir" 2>/dev/null && pwd -P)"

  # Every spelling of the path that can land under the root: as written, through the physical root, and
  # through the physical directory (a symlinked directory that leads into the harness).
  cats=""
  for cand in "$(rel_under "$root" "$abs")" "$(rel_under "$rootp" "$abs")" \
              "$( [ -n "$dirp" ] && rel_under "$rootp" "$dirp/$base")" "$( [ -n "$dirp" ] && rel_under "$root" "$dirp/$base")"; do
    [ -n "$cand" ] || continue
    rel="$cand"
    cats="$cats $(map_categories "$root/.agents/consequence.yml" "$rel")"
    [ -n "$first" ] || first="$rel"
  done
  [ -n "$(trim "$cats")" ] || return 0

  rest=""
  for c in $cats; do
    case "$c" in
      harness) harness=1 ;;
      *) case " $rest " in *" $c "*) ;; *) rest="$rest $c" ;; esac ;;
    esac
  done
  rest="$(trim "$rest")"

  if [ "$harness" = 1 ] && ! approval_current "$root"; then
    reason="$first is part of the agent harness (harness). Change it through /keel-harness:build or /keel-harness:rules, or record the decision in an ADR and ask the user."
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$(json_escape "$reason")"
    return 0
  fi
  if [ -n "$rest" ]; then
    reason="$first is in the consequence map (.agents/consequence.yml) under: $(printf '%s' "$rest" | tr ' ' ','). Confirm with the user before changing it."
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"%s"}}\n' "$(json_escape "$reason")"
  fi
  return 0
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  _claude_protect_main
  exit 0
fi
