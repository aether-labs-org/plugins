#!/usr/bin/env bash
# measure.sh - read-only as-is measurements for the keel `rules` skill.
# Run from the repository root: bash measure.sh <subcommand> [args]. It never writes inside the
# repository (temporary files live outside it). Unknown subcommand -> exit 64.
#   file-size [pathspec...]            files, p50/p75/p90, max, over:N buckets
#   tree [depth=2]                     count<TAB>dir (directories of <depth> path components)
#   imports <java|kotlin|python> <prefix>   from<TAB>to<TAB>count between packages under <prefix>
#   imports ts <src_root>              the same between top-level dirs, plus "unresolved N"
#   framework-imports <path_prefix>    framework_prefix<TAB>count
#   tests                              main/test/unit/integration/e2e counts and tools
#   language <stoplist> [pathspec...]  runs sensors/code-language.sh in measure mode
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cmd_file_size() {
  git ls-files -z -- "$@" | while IFS= read -r -d '' f; do
    [ -f "$f" ] || continue
    grep -Iq . "$f" 2>/dev/null || continue
    printf '%s\t%s\n' "$(wc -l < "$f" | tr -d ' ')" "$f"
  done > "$tmp/sizes"
  sort -n -t "$(printf '\t')" -k1,1 "$tmp/sizes" | awk -F'\t' '
    { c[NR] = $1 + 0; p[NR] = $2; if ($1 + 0 > 200) o200++; if ($1 + 0 > 300) o300++
      if ($1 + 0 > 500) o500++; if ($1 + 0 > 1000) o1000++ }
    function nr(q,   i) { i = int((q * NR + 99) / 100); if (i < 1) i = 1; return c[i] }
    END {
      printf "files %d\n", NR
      if (NR > 0) { printf "p50 %d\np75 %d\np90 %d\n", nr(50), nr(75), nr(90); printf "max %d %s\n", c[NR], p[NR] }
      else { print "p50 0"; print "p75 0"; print "p90 0"; print "max 0 -" }
      printf "over:200 %d\nover:300 %d\nover:500 %d\nover:1000 %d\n", o200, o300, o500, o1000
    }'
}

cmd_tree() {
  local depth="${1:-2}"
  git ls-files | awk -v d="$depth" '
    { n = split($0, a, "/"); k = (n - 1 < d) ? n - 1 : d
      if (k < 1) { dir = "." } else { dir = a[1]; for (i = 2; i <= k; i++) dir = dir "/" a[i] }
      cnt[dir]++ }
    END { for (x in cnt) printf "%d\t%s\n", cnt[x], x }' | sort -t "$(printf '\t')" -k1,1nr -k2,2
}

# imports <lang> <prefix|src_root>
cmd_imports() {
  local lang="${1:-}" prefix="${2:-}"
  [ -n "$lang" ] && [ -n "$prefix" ] || { echo "usage: imports <java|kotlin|python|ts> <prefix>" >&2; return 64; }
  local globs
  case "$lang" in
    java) globs="*.java" ;;
    kotlin) globs="*.kt" ;;
    python) globs="*.py" ;;
    ts) globs="*.ts *.tsx *.js *.jsx" ;;
    *) echo "unknown language: $lang" >&2; return 64 ;;
  esac
  cat > "$tmp/imports.awk" <<'AWK'
function norm(p,   n, a, i, out, k, st) {
  n = split(p, a, "/"); k = 0
  for (i = 1; i <= n; i++) {
    if (a[i] == "" || a[i] == ".") continue
    if (a[i] == "..") { if (k > 0) k--; continue }
    st[++k] = a[i]
  }
  out = ""; for (i = 1; i <= k; i++) out = out (i > 1 ? "/" : "") st[i]
  return out
}
BEGIN { pp = prefix; if (lang != "ts") gsub(/\./, "/", pp); sub(/\/$/, "", pp) }
FNR == 1 {
  f = FILENAME; from = ""
  i = index("/" f, "/" pp "/")
  if (i > 0) { rest = substr("/" f, i + length(pp) + 2); k = index(rest, "/"); if (k > 0) from = substr(rest, 1, k - 1) }
}
from == "" { next }
{
  line = $0
  if (lang == "java" || lang == "kotlin") {
    if (match(line, /^[ \t]*import[ \t]+(static[ \t]+)?/)) {
      t = substr(line, RLENGTH + 1); sub(/[; \t\r].*$/, "", t)
      if (index(t, prefix ".") == 1) { r = substr(t, length(prefix) + 2); split(r, a, "."); to = a[1]
        if (to != "" && to != from && index(r, ".") > 0) print "E\t" from "\t" to }
    }
  } else if (lang == "python") {
    if (match(line, /^[ \t]*(from|import)[ \t]+/)) {
      t = substr(line, RLENGTH + 1); sub(/[ \t\r].*$/, "", t)
      if (index(t, prefix ".") == 1) { r = substr(t, length(prefix) + 2); split(r, a, "."); to = a[1]
        if (to != "" && to != from) print "E\t" from "\t" to }
    }
  } else {
    spec = ""
    if (match(line, /(from|import|require\()[ \t]*\(?[ \t]*["'][^"']+["']/)) {
      t = substr(line, RSTART, RLENGTH); sub(/^[^"']*["']/, "", t); sub(/["'].*$/, "", t); spec = t
    }
    if (spec != "") {
      if (substr(spec, 1, 1) == ".") {
        d = f; sub(/[^\/]*$/, "", d); tgt = norm(d spec)
        if (index(tgt, pp "/") == 1) { r = substr(tgt, length(pp) + 2); split(r, a, "/"); to = a[1]
          if (to != "" && to != from) print "E\t" from "\t" to }
      } else print "U"
    }
  }
}
AWK
  # shellcheck disable=SC2086
  git ls-files -z -- $globs | xargs -0 awk -v lang="$lang" -v prefix="$prefix" -f "$tmp/imports.awk" 2>/dev/null > "$tmp/imp.raw"
  awk -F'\t' '$1 == "E" { c[$2 "\t" $3]++ } $1 == "U" { u++ }
    END { for (k in c) printf "%s\t%d\n", k, c[k]; if (lang == "ts") printf "unresolved %d\n", u + 0 }' lang="$lang" "$tmp/imp.raw" | sort -t "$(printf '\t')" -k1,1 -k2,2 | awk '/^unresolved/ { last = $0; next } { print } END { if (last != "") print last }'
}

cmd_framework_imports() {
  local pre="${1:-}"
  [ -n "$pre" ] || { echo "usage: framework-imports <path_prefix>" >&2; return 64; }
  cat > "$tmp/fw.awk" <<'AWK'
BEGIN { n = split("org.springframework jakarta. javax.persistence django flask fastapi sqlalchemy express @nestjs react", P, " ") }
{
  t = ""
  if (match($0, /^[ \t]*import[ \t]+(static[ \t]+)?/)) t = substr($0, RLENGTH + 1)
  else if (match($0, /^[ \t]*from[ \t]+/)) t = substr($0, RLENGTH + 1)
  else if (match($0, /(from|require\()[ \t]*\(?[ \t]*["']/)) t = substr($0, RSTART + RLENGTH)
  if (t == "") next
  sub(/^[ \t]*["']/, "", t)
  for (i = 1; i <= n; i++) {
    p = P[i]
    if (index(t, p) == 1) {
      c = substr(t, length(p) + 1, 1)
      if (substr(p, length(p), 1) == "." || c !~ /[A-Za-z0-9_]/) { print p; break }
    }
  }
}
AWK
  git ls-files -z -- "$pre" | xargs -0 awk -f "$tmp/fw.awk" 2>/dev/null | sort | uniq -c | awk '{ printf "%s\t%d\n", $2, $1 }' | sort -t "$(printf '\t')" -k2,2nr -k1,1
}

cmd_tests() {
  git ls-files > "$tmp/all"
  grep -E '\.(java|kt|py|ts|tsx|js|jsx|go)$' "$tmp/all" > "$tmp/src" || true
  awk '
    function base(p,   n, a) { n = split(p, a, "/"); return a[n] }
    function is_int(p, b) { return (b ~ /[a-z0-9]IT\.[A-Za-z]+$/ || b ~ /IntegrationTest/ || p ~ /(^|\/)integration\//) }
    function is_e2e(p, b) { return (p ~ /(^|\/)(e2e|cypress|playwright)\// || b ~ /\.e2e\./) }
    function is_test(p, b) {
      return (b ~ /(Test|Tests|Spec)\.[A-Za-z]+$/ || b ~ /[a-z0-9]IT\.[A-Za-z]+$/ || b ~ /\.(test|spec|e2e)\./ || b ~ /^test_.*\.py$/ || b ~ /_test\.(py|go)$/ || is_e2e(p, b) || p ~ /(^|\/)(test|tests|__tests__)\//)
    }
    {
      p = $0; b = base(p)
      if (is_test(p, b)) {
        t++; tb[b] = 1
        if (is_e2e(p, b)) e2e++; else if (is_int(p, b)) integ++; else unit++
      } else { m++; mp[m] = p }
    }
    END {
      for (i = 1; i <= m; i++) {
        b = base(mp[i]); stem = b; ext = ""
        if (match(b, /\.[A-Za-z]+$/)) { stem = substr(b, 1, RSTART - 1); ext = substr(b, RSTART) }
        if (stem == "index" || stem == "__init__") continue
        if (!((stem "Test" ext) in tb || (stem "Tests" ext) in tb || (stem "IT" ext) in tb || (stem ".test" ext) in tb || (stem ".spec" ext) in tb || ("test_" stem ext) in tb || (stem "_test" ext) in tb)) un++
      }
      printf "main %d\ntest %d\nunit %d\nintegration %d\ne2e %d\nuntested_main %d\n", m, t, unit, integ, e2e, un
    }' "$tmp/src"
  local cfg
  cfg="$(grep -E '(^|/)(build\.gradle(\.kts)?|pom\.xml|package\.json|pyproject\.toml|setup\.cfg|requirements[^/]*\.txt|\.coveragerc|\.nycrc|stryker\.conf\.[a-z]+|mutmut_config\.py)$' "$tmp/all" | while IFS= read -r f; do [ -f "$f" ] && printf '%s\n' "$f"; done)"
  has() { [ -n "$cfg" ] && printf '%s\n' "$cfg" | tr '\n' '\0' | xargs -0 grep -qE "$1" 2>/dev/null; }
  if has 'pitest|info\.solidsoft'; then echo "mutation_tool pitest"
  elif has 'stryker'; then echo "mutation_tool stryker"
  elif has 'mutmut'; then echo "mutation_tool mutmut"
  else echo "mutation_tool none"; fi
  if has 'jacoco'; then echo "coverage_tool jacoco"
  elif has 'istanbul|nyc'; then echo "coverage_tool istanbul"
  elif has '"?c8"?'; then echo "coverage_tool c8"
  elif has 'coverage'; then echo "coverage_tool coverage.py"
  else echo "coverage_tool none"; fi
}

cmd_language() {
  local sl="${1:-}"; shift
  [ -n "$sl" ] || { echo "usage: language <stoplist> [pathspec...]" >&2; return 64; }
  [ -f "$sl" ] || sl="$here/../assets/core/sensors/rules/stoplists/$sl"
  [ -f "$sl" ] || { echo "stoplist not found: $sl" >&2; return 64; }
  local inc="" p
  for p in "$@"; do inc="${inc}${inc:+
}${p}"; done
  printf "INCLUDE='%s'\nSTOPLIST='%s'\n" "$inc" "$sl" > "$tmp/language.env"
  RULE_ENV="$tmp/language.env" KEEL_MEASURE=1 KEEL_MEASURE_WORDS=1 KEEL_BASELINE_LIB="$here/../assets/core/lib/baseline.sh" \
    KEEL_ENVPARSE_LIB="$here/../assets/core/lib/envparse.sh" \
    bash "$here/../assets/core/sensors/rules/code-language.sh"
}

sub="${1:-}"; [ $# -gt 0 ] && shift
case "$sub" in
  file-size) cmd_file_size "$@" ;;
  tree) cmd_tree "$@" ;;
  imports) cmd_imports "$@" ;;
  framework-imports) cmd_framework_imports "$@" ;;
  tests) cmd_tests ;;
  language) cmd_language "$@" ;;
  *) echo "usage: measure.sh file-size|tree|imports|framework-imports|tests|language ..." >&2; exit 64 ;;
esac
