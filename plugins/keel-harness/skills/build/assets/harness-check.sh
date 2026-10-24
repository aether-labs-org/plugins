#!/usr/bin/env bash
# Managed by keel-harness. Edit only between the keel:repo-specific markers - see .agents/README.md.
# harness-check - portable, read-only validator of the harness in this repository.
# Run from the repository root: bash scripts/harness-check.sh (or make harness-check).
# Prints one line per warning: warn<TAB><check-id><TAB><file><TAB><message><TAB><fix>, then
# "harness-check: N warning(s)" or "harness-check: harness is clean".
# Exit 0 clean, 1 warnings, 2 no .agents/state.yml. KEEL_TODAY=YYYY-MM-DD overrides today.
set -uo pipefail

if [ ! -f .agents/state.yml ]; then
  echo "harness-check: no harness installed - run /keel-harness:build"
  exit 2
fi

today="${KEEL_TODAY:-$(date +%Y-%m-%d)}"
nwarn=0
warn() { # warn <check-id> <file> <message> <fix>
  nwarn=$((nwarn + 1))
  printf 'warn\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4"
}
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
TAB="$(printf '\t')"

agents_files() {
  git ls-files --cached --others --exclude-standard -- 'AGENTS.md' '*/AGENTS.md' 2>/dev/null | while IFS= read -r f; do [ -f "$f" ] && printf '%s\n' "$f"; done
}

# --- agents-size
check_agents_size() {
  local f n
  agents_files | while IFS= read -r f; do
    n=$(wc -l < "$f" | tr -d ' ')
    [ "$n" -gt 100 ] && printf '%s\t%s\n' "$f" "$n"
  done > "$tmp/sizes"
  while IFS="$TAB" read -r f n; do
    [ -n "$f" ] || continue
    warn agents-size "$f" "$n lines, over the 100-line ceiling" "Move detail into a docs/ topic file and keep a pointer; see .agents/README.md"
  done < "$tmp/sizes"
}

# --- stale-command
cmd_resolves() { # cmd_resolves "<command text>" -> 0 when it resolves (or is not a checked kind)
  local t1 t2 t3 _r
  read -r t1 t2 t3 _r <<< "$1"
  case "$t1" in
    make)
      [ -n "$t2" ] || return 0
      case "$t2" in -*) return 0 ;; esac
      [ -f Makefile ] || [ -f GNUmakefile ] || [ -f makefile ] || return 1
      grep -qE "^${t2}[[:space:]]*:" Makefile GNUmakefile makefile 2>/dev/null ;;
    npm)
      [ "$t2" = run ] || return 0
      grep -qE "\"$t3\"[[:space:]]*:" package.json 2>/dev/null ;;
    pnpm | yarn)
      [ -n "$t2" ] || return 0
      [ "$t2" = run ] && t2="$t3"
      case "$t2" in
        install | i | add | remove | rm | update | up | upgrade | init | exec | dlx | create | link | unlink | publish | pack | outdated | audit | store | why | list | ls | ci | rebuild | config | -*) return 0 ;;
      esac
      grep -qE "\"$t2\"[[:space:]]*:" package.json 2>/dev/null ;;
    ./gradlew | ./mvnw) [ -f "$t1" ] ;;
    .venv/bin/*) [ -e "$t1" ] ;;
    uv)
      [ "$t2" = run ] || return 0
      [ -n "$t3" ] || return 0
      command -v "$t3" >/dev/null 2>&1 || [ -e "$t3" ] ;;
    *) return 0 ;;
  esac
}
check_stale_command() {
  local f c
  agents_files | while IFS= read -r f; do
    grep -o '`[^`]*`' "$f" | tr -d '`' | awk '{ gsub(/&&|;/, "\n"); print }' | sed 's/^ *//; s/ *$//' | sort -u | while IFS= read -r c; do
      [ -n "$c" ] && ! cmd_resolves "$c" && printf '%s\t%s\n' "$f" "$c"
    done
  done > "$tmp/stale"
  while IFS="$TAB" read -r f c; do
    [ -n "$f" ] || continue
    warn stale-command "$f" "\`$c\` no longer resolves" "Fix or remove the command in $f (a Makefile target, package.json script or file)"
  done < "$tmp/stale"
}

# --- agents-not-loaded
check_agents_not_loaded() {
  local f
  [ -f AGENTS.md ] || return 0
  for f in CLAUDE.md .claude/CLAUDE.md; do
    if [ -f "$f" ] && ! grep -q '@AGENTS\.md' "$f"; then
      warn agents-not-loaded "$f" "Claude Code skips AGENTS.md because $f does not import it" "Add @AGENTS.md as the first line of $f (/keel-harness:build proposes it)"
    fi
  done
}

# --- dangling-pointer
check_dangling_pointer() {
  local f t why
  agents_files | while IFS= read -r f; do
    d="$(dirname "$f")"
    # Pointers are written `→ path` (or `-> path` when typed by hand).
    grep -oE '(→|->) *`?[^ `)|]*' "$f" | sed -E 's/^(→|->) *`?//; s/[.,;]*$//' | sort -u | while IFS= read -r t; do
      case "$t" in '' | *'{'* | *'<'* | http*) continue ;; esac
      path="${t%%#*}"; anchor=""
      case "$t" in *'#'*) anchor="${t#*#}" ;; esac
      target=""
      if [ -e "$path" ]; then target="$path"; elif [ -e "$d/$path" ]; then target="$d/$path"; fi
      if [ -z "$target" ]; then printf '%s\t%s\t%s\n' "$f" "$t" "target is missing"; continue; fi
      if [ -n "$anchor" ] && [ -f "$target" ] && ! grep -qF "<a id=\"$anchor\"></a>" "$target"; then
        printf '%s\t%s\t%s\n' "$f" "$t" "anchor <a id=\"$anchor\"></a> is missing"; continue
      fi
      if [ -f "$target" ] && [ "$(grep -c '[^[:space:]]' "$target")" -le 5 ] && grep -q 'TODO' "$target"; then
        printf '%s\t%s\t%s\n' "$f" "$t" "target is still a TODO stub"
      fi
    done
  done > "$tmp/dangling"
  while IFS="$TAB" read -r f t why; do
    [ -n "$f" ] || continue
    warn dangling-pointer "$f" "pointer to $t: $why" "Create or complete the target (/keel-harness:rules writes rule sections) or remove the pointer"
  done < "$tmp/dangling"
}

# --- hook-missing
check_hook_missing() {
  grep -qE 'hook: *not_installed' .agents/state.yml && return 0
  if [ -f .claude/settings.json ] && grep -q '"Stop"' .claude/settings.json && grep -q 'scripts/hooks/claude-stop\.sh' .claude/settings.json && [ -x scripts/hooks/claude-stop.sh ]; then
    return 0
  fi
  warn hook-missing .claude/settings.json "no Stop hook pointing at an executable scripts/hooks/claude-stop.sh" "Run /keel-harness:build to install the Stop hook, or see .agents/README.md"
}

# --- guard-missing
check_guard_missing() {
  [ -f scripts/sensors/guard.sh ] && [ -f scripts/lib/envparse.sh ] && return 0
  warn guard-missing scripts/sensors/guard.sh "no guard sensor or no scripts/lib/envparse.sh, so the harness can be loosened without anyone noticing" "Run /keel-harness:build to install scripts/sensors/guard.sh and scripts/lib/envparse.sh"
}

# --- sensor-malformed
check_sensor_malformed() {
  local s name id cls problems
  for s in scripts/sensors/*.sh scripts/sensors/slow/*.sh; do
    [ -f "$s" ] || continue
    name="$(basename "$s" .sh)"
    case "$name" in _*) continue ;; esac
    id="$(sed -n 's/^id=//p' "$s" | head -1 | tr -d '\r"')"
    cls="$(sed -n 's/^class=//p' "$s" | head -1 | tr -d '\r"')"
    problems=""
    [ "$id" = "$name" ] || problems="${problems}id= is '$id' but the file is $name.sh; "
    case "$cls" in security | correctness | heuristic) ;; *) problems="${problems}class= is '$cls'; " ;; esac
    [ -x "$s" ] || problems="${problems}not executable; "
    [ -z "$problems" ] || warn sensor-malformed "$s" "${problems%; }" "Fix the sensor against the contract in .agents/README.md (id= equals the file name, class=security|correctness|heuristic, chmod +x)"
  done
}

# --- sensor-unavailable
check_sensor_unavailable() {
  local f s name rc
  f="$(git ls-files --cached --others --exclude-standard 2>/dev/null | grep -E '\.(ts|tsx|js|jsx|py|java|kt)$' | head -1)"
  [ -n "$f" ] || return 0
  for s in scripts/sensors/*.sh; do
    [ -f "$s" ] || continue
    name="$(basename "$s" .sh)"
    case "$name" in _*) continue ;; esac
    env SCOPE="$f" bash "$s" > /dev/null 2>&1
    rc=$?
    if [ "$rc" -eq 2 ]; then
      warn sensor-unavailable "$s" "exits 2 (skip) with SCOPE=$f, so it guards nothing" "Install the tool it needs (make bootstrap) or move the sensor to scripts/sensors/disabled/ if the stack no longer uses it"
    fi
  done
}

# --- rule-inconsistent
envval() { # envval FILE KEY -> the value of KEY= (first line; quotes and trailing comment removed)
  local v
  v="$(tr -d '\r' < "$1" | sed -n "s/^$2=//p" | head -1)"
  case "$v" in
    \'*) v="${v#\'}"; v="${v%%\'*}" ;;
    \"*) v="${v#\"}"; v="${v%%\"*}" ;;
    *) v="${v%%[[:space:]]#*}"; v="${v%"${v##*[![:space:]]}"}" ;;
  esac
  printf '%s' "$v"
}
check_rule_inconsistent() {
  local f k v problems doc path anchor id item section name val
  for f in .agents/rules/*.env; do
    [ -f "$f" ] || continue
    problems=""
    for k in RULE_ID KIND ORIGIN APPROVED_AT ENFORCEMENT DOC; do
      [ -n "$(envval "$f" "$k")" ] || problems="${problems}missing $k; "
    done
    id="$(envval "$f" RULE_ID)"
    doc="$(envval "$f" DOC)"
    section=""
    if [ -n "$doc" ]; then
      path="${doc%%#*}"
      case "$doc" in *'#'*) anchor="${doc#*#}" ;; *) anchor="$id" ;; esac
      if [ ! -f "$path" ]; then
        problems="${problems}DOC file $path is missing; "
      elif ! grep -qF "<a id=\"$anchor\"></a>" "$path"; then
        problems="${problems}anchor <a id=\"$anchor\"></a> is missing in $path; "
      else
        section="$(awk -v a="<a id=\"$anchor\"></a>" 'index($0, a) { on = 1; print; next } on && index($0, "<a id=\"") { exit } on { print }' "$path")"
      fi
    fi
    v="$(envval "$f" ENFORCEMENT)"
    if [ -n "$v" ] && [ "$v" != inferential ]; then
      for item in $(printf '%s' "$v" | tr ',' ' '); do
        case "$item" in
          sensor:*)
            name="${item#sensor:}"
            [ -f "scripts/sensors/$name.sh" ] || [ -f "scripts/sensors/slow/$name.sh" ] || problems="${problems}sensor $name has no file in scripts/sensors/ or scripts/sensors/slow/; " ;;
        esac
      done
    fi
    v="$(envval "$f" DECISION)"
    if [ -n "$v" ] && [ ! -f "$v" ]; then problems="${problems}DECISION file $v is missing; "; fi
    if [ -n "$section" ]; then
      tr -d '\r' < "$f" | grep -E '^[A-Z_]*(LIMIT|MIN|MAX|SCORE|COVERAGE|THRESHOLD)[A-Z_]*=' | sed 's/[[:space:]]*#.*$//' > "$tmp/numeric"
      while IFS='=' read -r name val; do
        [ -n "$name" ] || continue
        case "$val" in '' | *[!0-9]*) continue ;; esac
        printf '%s\n' "$section" | grep -qw -- "$val" || problems="${problems}$name=$val does not appear in the section; "
      done < "$tmp/numeric"
    fi
    [ -z "$problems" ] || warn rule-inconsistent "$f" "${problems%; }" "Make the env file and its docs section agree (edit both, see .agents/README.md) or re-run /keel-harness:rules"
  done
}

# --- topic-size
check_topic_size() {
  local f n
  for f in docs/architecture.md docs/conventions.md docs/testing.md; do
    [ -f "$f" ] || continue
    n=$(wc -l < "$f" | tr -d ' ')
    [ "$n" -gt 300 ] && warn topic-size "$f" "$n lines, over the 300-line ceiling" "Split it by subtopic (e.g. docs/conventions-naming.md) and update the DOC= pointers; /keel-harness:rules can propose the split"
  done
}

# --- baseline-malformed and baseline-stale
check_baselines() {
  local f id header rb stored cur sensor rc
  for f in .agents/baselines/*.tsv; do
    [ -f "$f" ] || continue
    id="$(basename "$f" .tsv)"
    header="$(head -1 "$f" | tr -d '\r')"
    if ! printf '%s\n' "$header" | grep -qE '^# measured_at: [0-9-]+ review_by: [0-9-]+'; then
      warn baseline-malformed "$f" "first line is not '# measured_at: YYYY-MM-DD review_by: YYYY-MM-DD'" "Re-measure it: KEEL_MEASURE=1 bash scripts/sensors/$id.sh > $f"
      continue
    fi
    if ! tr -d '\r' < "$f" | awk -F'\t' '/^#/ || NF == 0 { next } !(NF == 2 && $1 != "" && $2 ~ /^[0-9]+$/) { bad = 1 } END { exit bad }'; then
      warn baseline-malformed "$f" "a row is not path<TAB>integer" "Re-measure it: KEEL_MEASURE=1 bash scripts/sensors/$id.sh > $f"
      continue
    fi
    rb="$(printf '%s\n' "$header" | sed 's/.*review_by: *\([0-9-]*\).*/\1/')"
    if [[ "$rb" < "$today" ]]; then
      sensor=""
      if [ -f "scripts/sensors/$id.sh" ]; then sensor="scripts/sensors/$id.sh"; elif [ -f "scripts/sensors/slow/$id.sh" ]; then sensor="scripts/sensors/slow/$id.sh"; fi
      [ -n "$sensor" ] || continue
      stored="$(tr -d '\r' < "$f" | awk -F'\t' '!/^#/ && NF >= 2 { s += $2 } END { print s + 0 }')"
      # An empty baseline has nothing left to burn down.
      [ "$stored" -gt 0 ] || continue
      env -u SCOPE KEEL_MEASURE=1 bash "$sensor" > "$tmp/measure.out" 2> /dev/null
      rc=$?
      [ "$rc" -eq 0 ] || continue
      cur="$(awk -F'\t' '!/^#/ && NF >= 2 { s += $2 } END { print s + 0 }' "$tmp/measure.out")"
      if [ "$cur" -ge "$stored" ]; then
        warn baseline-stale "$f" "past its review_by ($rb) and the current total ($cur) is not below the stored total ($stored)" "Fix some of the baselined violations, then re-measure downward: KEEL_MEASURE=1 bash scripts/sensors/$id.sh > $f"
      fi
    fi
  done
}

# --- review-due
check_review_due() {
  local d
  d="$(sed -n 's/^harness_review_by: *\([0-9-]*\).*/\1/p' .agents/state.yml | head -1)"
  [ -n "$d" ] || return 0
  if [[ "$d" < "$today" ]]; then
    warn review-due .agents/state.yml "harness_review_by $d has passed" "Re-read the harness with /keel-harness:doctor, then move harness_review_by six months ahead"
  fi
}

check_agents_size
check_stale_command
check_agents_not_loaded
check_dangling_pointer
check_hook_missing
check_guard_missing
check_sensor_malformed
check_sensor_unavailable
check_rule_inconsistent
check_topic_size
check_baselines
check_review_due

if [ "$nwarn" -eq 0 ]; then
  echo "harness-check: harness is clean"
  exit 0
fi
echo "harness-check: $nwarn warning(s)"
exit 1
