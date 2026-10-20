#!/usr/bin/env bash
# Managed by keel-harness. Edit only between the keel:repo-specific markers - see .agents/README.md.
# junit.sh - reads JUnit XML reports (Gradle build/test-results, Maven target/surefire-reports).
# Sourced by the JVM tests sensor and the ArchUnit engine of the architecture sensor: `gradle -q`
# and `mvn -q` print no assertion text, the reports do. Only reports written after SINCE_FILE count,
# so a report left over from an earlier run is never read. Gradle rewrites every report of the task
# on each run, filtered or not, so callers that ran only some classes pass their names to filter.

# junit_reports SINCE_FILE -> paths of TEST-*.xml written after SINCE_FILE
junit_reports() {
  find . \( -name .git -o -name node_modules \) -prune -o \
    \( -path '*/build/test-results/*' -o -path '*/target/surefire-reports/*' -o -path '*/target/failsafe-reports/*' \) \
    -name 'TEST-*.xml' -newer "$1" -print 2>/dev/null
}

# _junit_awk MODE ONLY -> awk program over one report; MODE "line" prints "Class.test: first line of
# the message" per failed test, MODE "full" prints each decoded failure message whole. ONLY is
# "|ClassA|ClassB|" (simple names) to keep, or empty for all.
_junit_awk() {
  awk -v mode="$1" -v only="$2" '
    function dec(s) {
      gsub(/&lt;/, "<", s); gsub(/&gt;/, ">", s); gsub(/&quot;/, "\"", s); gsub(/&apos;/, "\047", s)
      gsub(/&#10;/, "\n", s); gsub(/&#13;/, "", s); gsub(/&amp;/, "\\&", s); return s
    }
    function attr(line, key,   i, rest) {
      i = index(line, key "=\""); if (!i) return ""
      rest = substr(line, i + length(key) + 2); return substr(rest, 1, index(rest, "\"") - 1)
    }
    /<testcase / { cls = attr($0, "classname"); name = attr($0, "name"); n = split(cls, p, "."); short = p[n] }
    /<(failure|error) / {
      if (only != "" && index(only, "|" short "|") == 0) next
      m = dec(attr($0, "message")); sub(/^[A-Za-z0-9_.$]+(Error|Exception): /, "", m)
      if (mode == "full") { print m; next }
      split(m, ln, "\n"); print short "." name ": " ln[1]
    }'
}

# _junit_only CLASS... -> "|A|B|" (empty when no class is given)
_junit_only() { [ $# -gt 0 ] && printf '|%s' "$@" && printf '|'; }

# junit_failures SINCE_FILE [CLASS...] -> one line per failed test: "Class.test: <first message line>"
junit_failures() {
  local since="$1" only; shift; only="$(_junit_only "$@")"
  junit_reports "$since" | while IFS= read -r f; do _junit_awk line "$only" < "$f"; done
}

# junit_messages SINCE_FILE [CLASS...] -> every failure message, decoded, whole
junit_messages() {
  local since="$1" only; shift; only="$(_junit_only "$@")"
  junit_reports "$since" | while IFS= read -r f; do _junit_awk full "$only" < "$f"; done
}
