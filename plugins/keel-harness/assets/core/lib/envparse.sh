#!/usr/bin/env bash
# Managed by keel-harness. Edit only between the keel:repo-specific markers - see .agents/README.md.
# envparse.sh - reads KEY=value files without executing them. Sourced as: . scripts/lib/envparse.sh
# Accepts blank lines, `#` comment lines, unquoted values (a trailing ` # comment` is dropped) and
# single- or double-quoted values, which may span lines. Nothing is expanded: `$VAR` stays literal,
# and a value containing `$(` or a backtick is rejected, because v0.2 would have executed it.

KEEL_ENV_ERROR=""

# keel_env_load FILE -> sets each KEY in the caller's shell; returns 1 with KEEL_ENV_ERROR set.
keel_env_load() {
  local file="$1" n=0 line t key rest q="" buf="" open="" start=0
  KEEL_ENV_ERROR=""
  if [ ! -f "$file" ]; then KEEL_ENV_ERROR="$file: no such file"; return 1; fi
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    line="${line%$'\r'}"
    if [ -n "$open" ]; then
      case "$line" in
        *"$q"*)
          buf="$buf"$'\n'"${line%%"$q"*}"
          _keel_env_tail "$file" "$n" "${line#*"$q"}" || return 1
          _keel_env_set "$file" "$start" "$key" "$buf" || return 1
          open="" ;;
        *) buf="$buf"$'\n'"$line" ;;
      esac
      continue
    fi
    t="${line#"${line%%[![:space:]]*}"}"
    case "$t" in '' | '#'*) continue ;; esac
    key="${t%%=*}"
    case "$key" in
      "$t" | '' | [0-9]* | *[!A-Z0-9_]*)
        KEEL_ENV_ERROR="$file:$n: not a KEY=value line (keys are UPPER_CASE)"; return 1 ;;
    esac
    rest="${t#*=}"
    case "$rest" in
      \'* | \"*)
        q="${rest:0:1}"; rest="${rest:1}"
        case "$rest" in
          *"$q"*)
            _keel_env_tail "$file" "$n" "${rest#*"$q"}" || return 1
            _keel_env_set "$file" "$n" "$key" "${rest%%"$q"*}" || return 1 ;;
          *) open=1; start=$n; buf="$rest" ;;
        esac ;;
      *)
        rest="${rest%%[[:space:]]#*}"
        rest="${rest%"${rest##*[![:space:]]}"}"
        _keel_env_set "$file" "$n" "$key" "$rest" || return 1 ;;
    esac
  done < "$file"
  if [ -n "$open" ]; then KEEL_ENV_ERROR="$file:$start: $key has an unterminated quote"; return 1; fi
  return 0
}

# _keel_env_tail FILE LINE REST -> what follows a closing quote must be blank or a comment.
_keel_env_tail() {
  local t="${3#"${3%%[![:space:]]*}"}"
  case "$t" in '' | '#'*) return 0 ;; esac
  KEEL_ENV_ERROR="$1:$2: unexpected text after the closing quote"
  return 1
}

# _keel_env_set FILE LINE KEY VALUE
_keel_env_set() {
  case "$4" in
    *'$('* | *'`'*) KEEL_ENV_ERROR="$1:$2: $3 contains \$( or a backtick, which keel never executes"; return 1 ;;
  esac
  printf -v "$3" '%s' "$4"
}

# keel_env_load_sensor ID CLASS FILE -> loads FILE, or prints a fail line 1 with guidance and exits 1.
keel_env_load_sensor() {
  keel_env_load "$3" && return 0
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" fail "rule env file could not be read: $KEEL_ENV_ERROR"
  printf '  guidance: %s\n' "Fix that line of $3: plain KEY=value, quoted values may span lines, and nothing in it is executed. Do not delete the file or move the sensor to disabled/ to make this pass."
  exit 1
}
