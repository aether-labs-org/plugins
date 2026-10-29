#!/usr/bin/env bash
# Managed by keel-harness. Edit only between the keel:repo-specific markers - see .agents/README.md.
# dependencies - security. Fails when a manifest gained a direct dependency since the base commit and no
# ADR added in the same change names that manifest by path. Manifests: package.json (dependencies,
# devDependencies, peerDependencies, optionalDependencies), pyproject.toml ([project] dependencies and
# optional-dependencies, dependency-groups, poetry and uv tables), pom.xml (<dependency> outside
# dependencyManagement, plugins and exclusions) and build.gradle / build.gradle.kts (api, implementation,
# runtimeOnly ... with "group:artifact:version", group:/name: maps or a libs.* alias; project() is not external).
# A version change, a removal or a dependency that was already there is not new. There is no baseline.
# Env (.agents/rules/dependencies.env): INCLUDE and EXCLUDE (git pathspecs, one per line) limit the manifests.
# Base: KEEL_GUARD_BASE, else the merge-base with origin/HEAD, else HEAD. SCOPE is not used.
# In:  KEEL_MEASURE=1 prints path<TAB>number of direct dependencies, per manifest.
# Out: line 1 = id<TAB>class<TAB>status<TAB>summary. Exit 0 pass / 1 fail / 2 skip.
set -uo pipefail
# --- keel:repo-specific begin ---
id=dependencies
class=security
ADR_DIRS="docs/adr doc/adr docs/decisions docs/architecture/decisions"
GUIDANCE='remove the new dependency, or add an ADR in this same change that names the manifest by path and says why the dependency is needed and why neither the standard library nor an existing dependency will do. Check that the package exists and is the one you mean: a name suggested by a model may not exist, or may be a look-alike. Never add the dependency to an allow-list, edit this sensor or move it to disabled/ to make this pass.'
# --- keel:repo-specific end ---

RULE_ENV="${RULE_ENV:-.agents/rules/$id.env}"
if [ ! -f "$RULE_ENV" ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "no .agents/rules/$id.env - run the rules skill"
  exit 2
fi
INCLUDE=""; EXCLUDE=""
# shellcheck disable=SC1090,SC1091
. "${KEEL_ENVPARSE_LIB:-scripts/lib/envparse.sh}" 2>/dev/null || {
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "scripts/lib/envparse.sh is missing - run /keel-harness:build"
  exit 2
}
keel_env_load_sensor "$id" "$class" "$RULE_ENV"

# A temp dir: TMPDIR, else .agents/run/tmp/ (git-ignored), else none.
keel_tmpdir() { mktemp -d 2>/dev/null || { mkdir -p .agents/run/tmp 2>/dev/null && mktemp -d .agents/run/tmp/XXXXXX 2>/dev/null; }; }
tmp="$(keel_tmpdir)" || tmp=""
if [ -z "$tmp" ] || [ ! -d "$tmp" ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "no writable temp directory (TMPDIR or .agents/run/tmp/)"
  exit 2
fi
trap 'rm -rf "$tmp"' EXIT

# --- one awk program per manifest kind; each prints one dependency name per line
cat > "$tmp/pkg.awk" <<'AWK'
# package.json: the keys of the top-level dependency objects. Reads characters, so one-line objects work.
BEGIN { depth = 0; instr = 0; esc = 0; sec = 0; pend = 0; haslast = 0; buf = ""; last = "" }
{
  n = length($0)
  for (i = 1; i <= n; i++) {
    c = substr($0, i, 1)
    if (instr) {
      if (esc) { esc = 0; buf = buf c }
      else if (c == "\\") esc = 1
      else if (c == "\"") { instr = 0; last = buf; haslast = 1 }
      else buf = buf c
      continue
    }
    if (c == "\"") { instr = 1; buf = ""; pend = 0; continue }
    if (c == ":") {
      if (haslast) {
        if (depth == 1 && (last == "dependencies" || last == "devDependencies" || last == "peerDependencies" || last == "optionalDependencies")) pend = 1
        else if (sec > 0 && depth == sec) print last
      }
      haslast = 0; continue
    }
    if (c == "{") { depth++; if (pend) { sec = depth; pend = 0 }; haslast = 0; continue }
    if (c == "}") { if (sec > 0 && depth == sec) sec = 0; depth--; haslast = 0; continue }
    if (c == "," || c == "[" || c == "]") haslast = 0
  }
}
AWK
cat > "$tmp/toml.awk" <<'AWK'
# pyproject.toml: PEP 621 arrays, PEP 735 groups, uv dev-dependencies and poetry tables. Names are normalised.
function trim(s) { sub(/^[ \t\r]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
function norm(s) {
  s = tolower(s)
  if (match(s, /^[a-z0-9][a-z0-9._-]*/)) { s = substr(s, 1, RLENGTH); gsub(/[._]/, "-", s); return s }
  return ""
}
# scan(s): the rest of an array; quoted strings outside an inline table are requirements
function scan(s,   i, c, n, nm) {
  n = length(s)
  for (i = 1; i <= n && arr; i++) {
    c = substr(s, i, 1)
    if (inq) {
      if (c == q) { inq = 0; if (br == 0) { nm = norm(cur); if (nm != "") print nm }; cur = "" }
      else cur = cur c
    } else if (c == "\"" || c == "'") { inq = 1; q = c; cur = "" }
    else if (c == "#") return
    else if (c == "{") br++
    else if (c == "}") { if (br > 0) br-- }
    else if (c == "]") arr = 0
  }
}
BEGIN { arr = 0; inq = 0; br = 0; table = ""; cur = ""; q = "" }
{
  line = $0; sub(/\r$/, "", line)
  if (arr) { scan(line); next }
  t = trim(line)
  if (t == "" || substr(t, 1, 1) == "#") next
  if (substr(t, 1, 1) == "[") {
    h = t; sub(/#.*$/, "", h); h = trim(h); gsub(/^\[+/, "", h); gsub(/\]+$/, "", h); table = trim(h)
    if (table ~ /^tool\.poetry\.(group\.[^.]+\.)?(dev-)?dependencies\.[^.]+$/) {
      nm = table; sub(/^.*dependencies\./, "", nm); gsub(/"/, "", nm); nm = norm(nm)
      if (nm != "" && nm != "python") print nm
    }
    next
  }
  eq = index(t, "=")
  if (eq == 0) next
  key = trim(substr(t, 1, eq - 1)); val = substr(t, eq + 1)
  start = 0
  if (table == "project" && key == "dependencies") start = 1
  else if (table == "project.optional-dependencies" || table == "dependency-groups") start = 1
  else if (table == "tool.uv" && key == "dev-dependencies") start = 1
  if (start) {
    i = index(val, "[")
    if (i > 0) { arr = 1; inq = 0; br = 0; scan(substr(val, i + 1)) }
    next
  }
  if (table ~ /^tool\.poetry\.(group\.[^.]+\.)?(dev-)?dependencies$/ && key ~ /^[A-Za-z0-9][A-Za-z0-9._-]*$/) {
    nm = norm(key); if (nm != "" && nm != "python") print nm
  }
}
AWK
cat > "$tmp/pom.awk" <<'AWK'
# pom.xml: groupId:artifactId of every <dependency> that is not managed, not a plugin's and not an exclusion.
function txt(s) { sub(/^[^>]*>/, "", s); sub(/^[ \t\r]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
BEGIN { inc = 0; mgmt = 0; plug = 0; excl = 0; indep = 0; g = ""; a = "" }
{
  n = split($0, P, "<")
  for (k = 2; k <= n; k++) {
    p = "<" P[k]
    if (inc) { if (index(p, "-->") > 0) inc = 0; continue }
    if (substr(p, 1, 4) == "<!--") { if (index(p, "-->") == 0) inc = 1; continue }
    if (p ~ /^<dependencyManagement[ >]/) mgmt++
    else if (p ~ /^<\/dependencyManagement[ >]/) mgmt--
    else if (p ~ /^<plugin[ >]/) plug++
    else if (p ~ /^<\/plugin[ >]/) plug--
    else if (p ~ /^<exclusion[ >]/) excl++
    else if (p ~ /^<\/exclusion[ >]/) excl--
    else if (p ~ /^<dependency[ >]/) { if (mgmt == 0 && plug == 0) { indep = 1; g = ""; a = "" } }
    else if (p ~ /^<\/dependency[ >]/) { if (indep && g != "" && a != "") print g ":" a; indep = 0 }
    else if (indep && excl == 0 && p ~ /^<groupId[ >]/) g = txt(p)
    else if (indep && excl == 0 && p ~ /^<artifactId[ >]/) a = txt(p)
  }
}
AWK
cat > "$tmp/gradle.awk" <<'AWK'
# build.gradle / build.gradle.kts: external coordinates of the dependency configurations.
BEGIN {
  CFG = "^[ \t]*(api|implementation|compileOnly|runtimeOnly|annotationProcessor|kapt|ksp|compile|runtime|testCompile|testRuntime|developmentOnly|[a-z][A-Za-z]*(Implementation|Api|CompileOnly|RuntimeOnly|AnnotationProcessor))([ \t(]|$)"
}
{
  line = $0; sub(/\r$/, "", line)
  if (line ~ /^[ \t]*(\/\/|\/\*|\*)/) next
  sub(/[ \t]\/\/.*$/, "", line)
  if (!match(line, CFG)) next
  rest = substr(line, RLENGTH)
  if (rest ~ /project[ \t]*\(/) next
  if (match(rest, /group[ \t]*[:=][ \t]*["'][^"']+["']/)) {
    g = substr(rest, RSTART, RLENGTH); sub(/^[^"']*["']/, "", g); sub(/["'].*$/, "", g)
    if (match(rest, /name[ \t]*[:=][ \t]*["'][^"']+["']/)) {
      m = substr(rest, RSTART, RLENGTH); sub(/^[^"']*["']/, "", m); sub(/["'].*$/, "", m); print g ":" m
    }
    next
  }
  if (match(rest, /["'][^"':]+:[^"':]+(:[^"']*)?["']/)) {
    s = substr(rest, RSTART + 1, RLENGTH - 2); split(s, f, ":"); print f[1] ":" f[2]; next
  }
  if (match(rest, /libs\.[A-Za-z0-9_.-]+/)) print substr(rest, RSTART, RLENGTH)
}
AWK

# deps_of FILE -> the direct dependencies of one manifest (content on stdin), sorted, unique
deps_of() { # deps_of KIND
  tr -d '\r' | awk -f "$tmp/$1.awk" 2>/dev/null | LC_ALL=C sort -u
}
kind_of() { # kind_of PATH -> pkg | toml | pom | gradle | (empty)
  case "${1##*/}" in
    package.json) echo pkg ;;
    pyproject.toml) echo toml ;;
    pom.xml) echo pom ;;
    build.gradle | build.gradle.kts) echo gradle ;;
  esac
}

specs=()
# A trailing "/" is dropped: git ignores some :(exclude) pathspecs next to "src/" (2.43), never next to "src".
while IFS= read -r l; do [ -n "$l" ] && { [ "$l" = / ] || l="${l%/}"; specs[${#specs[@]}]="$l"; }; done <<LIST
$INCLUDE
LIST
[ ${#specs[@]} -gt 0 ] || specs[0]="."
while IFS= read -r l; do [ -n "$l" ] && specs[${#specs[@]}]=":(exclude)$l"; done <<LIST
$EXCLUDE
LIST
specs[${#specs[@]}]=":(exclude)node_modules/*"
specs[${#specs[@]}]=":(exclude)*/node_modules/*"
git ls-files -z --cached --others --exclude-standard -- "${specs[@]}" 2>/dev/null | tr '\0' '\n' | LC_ALL=C sort -u > "$tmp/cand"
: > "$tmp/manifests"
while IFS= read -r f; do
  [ -n "$f" ] && [ -f "$f" ] && [ -n "$(kind_of "$f")" ] && printf '%s\n' "$f" >> "$tmp/manifests"
done < "$tmp/cand"
checked=$(grep -c . "$tmp/manifests")

if [ "${KEEL_MEASURE:-}" = 1 ]; then
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    printf '%s\t%s\n' "$f" "$(deps_of "$(kind_of "$f")" < "$f" | grep -c .)"
  done < "$tmp/manifests"
  exit 0
fi

if ! git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" pass "No commits yet - nothing to compare."
  exit 0
fi
base="${KEEL_GUARD_BASE:-}"
if [ -z "$base" ] && git rev-parse --verify -q refs/remotes/origin/HEAD >/dev/null 2>&1; then
  base="$(git merge-base HEAD refs/remotes/origin/HEAD 2>/dev/null)"
fi
: "${base:=HEAD}"
short="$(git rev-parse --short "$base" 2>/dev/null)" || {
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" fail "KEEL_GUARD_BASE=$base is not a commit."
  printf '  guidance: %s\n' "Set KEEL_GUARD_BASE to the branch the change will merge into (e.g. origin/main), or unset it."
  exit 1
}
if ! git cat-file -e "$base:.agents/state.yml" 2>/dev/null; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" pass "Harness installed in this change - nothing to compare (base $short)."
  exit 0
fi
adr_dir="$(sed -n 's/^adr_dir:[[:space:]]*\([^#[:space:]]*\).*/\1/p' .agents/state.yml 2>/dev/null | head -1)"
[ -n "$adr_dir" ] && ADR_DIRS="$adr_dir"

# New direct dependencies: names in the manifest now that were not in it at the base (a manifest that
# did not exist at the base has every dependency new). Rows: manifest<TAB>name.
: > "$tmp/new"
while IFS= read -r f; do
  [ -n "$f" ] || continue
  k="$(kind_of "$f")"
  deps_of "$k" < "$f" > "$tmp/cur"
  git show "$base:$f" 2>/dev/null | deps_of "$k" > "$tmp/old"
  comm -13 "$tmp/old" "$tmp/cur" | while IFS= read -r d; do printf '%s\t%s\n' "$f" "$d"; done >> "$tmp/new"
done < "$tmp/manifests"

# ADRs added since the base (committed or not)
for d in $ADR_DIRS; do
  git diff --name-only --diff-filter=A "$base" -- "$d" 2>/dev/null
  git ls-files --others --exclude-standard -- "$d" 2>/dev/null
done | sort -u > "$tmp/adrs"

# named MANIFEST -> 0 when an added ADR names the manifest by its whole path (not a longer or shorter one)
named() {
  local esc a
  esc="$(printf '%s' "$1" | sed 's/[][\.*^$+?(){}|]/\\&/g')"
  while IFS= read -r a; do
    [ -f "$a" ] || continue
    grep -E -e "(^|[^A-Za-z0-9_./-])(\./)?${esc}(\$|[^A-Za-z0-9_.-]|\.([^A-Za-z0-9_-]|\$))" -- "$a" >/dev/null 2>&1 && return 0
  done < "$tmp/adrs"
  return 1
}
: > "$tmp/left"; covered=0
while IFS="$(printf '\t')" read -r f d; do
  [ -n "$f" ] || continue
  if named "$f"; then covered=$((covered + 1)); else printf '%s: %s\n' "$f" "$d" >> "$tmp/left"; fi
done < "$tmp/new"

nl=$(grep -c . "$tmp/left")
if [ "$nl" -eq 0 ]; then
  if [ "$covered" -gt 0 ]; then
    printf '%s\t%s\t%s\t%s\n' "$id" "$class" pass "$covered new direct dependency(ies) since $short, each in a manifest named by an ADR added in this change."
  else
    printf '%s\t%s\t%s\t%s\n' "$id" "$class" pass "$checked manifest(s) checked, no new direct dependency since $short."
  fi
  exit 0
fi
printf '%s\t%s\t%s\t%s\n' "$id" "$class" fail "$nl new direct dependency(ies) since $short without an ADR naming the manifest."
head -5 "$tmp/left" | sed 's/^/  /'
printf '  guidance: %s\n' "$GUIDANCE"
exit 1
