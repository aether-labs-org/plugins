#!/usr/bin/env bash
# measure.sh - read-only as-is measurements that no gate computes, for the Baymax harness skill.
# Run from the repository root: bash measure.sh <subcommand> [args]. Metrics that are also gates
# (file size, code language, patterns, dependencies) come from `bmax measure <script>`, never from here.
# It writes nothing in the repository: temporary files live in a directory from mktemp and are removed on exit.
# Unknown subcommand -> exit 64.
#   tree [depth=2]                     count<TAB>dir (directories of <depth> path components)
#   imports <java|kotlin|python> <prefix>   from<TAB>to<TAB>count between packages under <prefix>
#   imports ts <src_root>              the same between top-level dirs, plus "unresolved N"
#   framework-imports <path_prefix>    framework_prefix<TAB>count
#   tests                              main/test/unit/integration/e2e counts and tools
#   commits                            subject statistics of the last 200 commits
set -uo pipefail

tmp="$(mktemp -d 2>/dev/null)" || tmp=""
if [ -z "$tmp" ] || [ ! -d "$tmp" ]; then
  echo "measure: no writable temporary directory (set TMPDIR)" >&2
  exit 1
fi
trap 'rm -rf "$tmp"' EXIT

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

# commits: the shape of the last 200 commit subjects
cmd_commits() {
  git rev-parse --verify -q HEAD >/dev/null 2>&1 || { echo "commits 0"; return 0; }
  git log -200 --format=%s > "$tmp/subjects"
  local merges
  merges="$(git log -200 --merges --format=%h | grep -c . || true)"
  awk -v merges="$merges" '
    { n++; len[n] = length($0)
      if (match($0, /^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([^)]*\))?!?: /)) {
        conv++; t = substr($0, 1, index($0, ":") - 1); sub(/[(!].*$/, "", t); types[t]++ }
      if ($0 ~ /(#[0-9]+|[A-Z][A-Z0-9]+-[0-9]+)/) refs++
      if ($0 ~ /^[A-Z]/) upper++ }
    function pct(q,   i, a, k) {
      for (i = 1; i <= n; i++) a[i] = len[i]
      for (i = 2; i <= n; i++) { k = a[i]; j = i - 1; while (j >= 1 && a[j] > k) { a[j + 1] = a[j]; j-- } a[j + 1] = k }
      i = int((q * n + 99) / 100); if (i < 1) i = 1; return a[i]
    }
    END {
      printf "commits %d\nconventional %d\nmerges %d\nticket_refs %d\ncapitalised %d\n", n, conv, merges, refs, upper
      if (n > 0) printf "subject_len_p50 %d\nsubject_len_p90 %d\n", pct(50), pct(90)
      for (t in types) printf "type:%s %d\n", t, types[t]
    }' "$tmp/subjects" | sort
}

case "${1:-}" in
  tree) shift; cmd_tree "$@" ;;
  imports) shift; cmd_imports "$@" ;;
  framework-imports) shift; cmd_framework_imports "$@" ;;
  tests) cmd_tests ;;
  commits) cmd_commits ;;
  *) echo "usage: measure.sh tree [depth] | imports <java|kotlin|python|ts> <prefix> | framework-imports <path> | tests | commits" >&2; exit 64 ;;
esac
