#!/usr/bin/env bash
# Parity: on the same repository, `bash scripts/gate.sh` and `kh gate` print the same report,
# write the same log and exit with the same code. Only the timing columns are normalised.
set -uo pipefail
. "$(dirname "$0")/keel_helpers.sh"
BIN="${KEEL_BIN:-$(cd "$(dirname "$0")/.." && pwd)/cli/kh/dist/kh}"
SUMS="$(dirname "$BIN")/SHA256SUMS"
if [ ! -x "$BIN" ]; then
  if [ -n "${CI:-}" ]; then fail "kh not built (make -C cli/kh build is required in CI)"; finish; fi
  echo "  skip kh parity: $BIN not built (make -C cli/kh build)"; exit 0
fi

# mk -> repo with the real gate.sh and gate.env (installed by copy, whatever KEEL_ENGINE says)
mk() {
  local r; r="$(new_repo "$@")"
  mkdir -p "$r/scripts/sensors" "$r/.agents"
  cp "$KEEL/skills/build/assets/gate.sh" "$r/scripts/gate.sh"
  cp "$KEEL/skills/build/assets/gate.env" "$r/.agents/gate.env"
  printf '%s\n' "$r"
}
# sensor REPO RELPATH SCRIPT-BODY
sensor() { mkdir -p "$(dirname "$1/$2")"; printf '#!/usr/bin/env bash\n%s\n' "$3" > "$1/$2"; }
# norm: drop the per-sensor time column and the spent value; everything else must match byte for byte
norm() { sed -E 's/ +[0-9]+(\.[0-9])?m?s$/ <t>/; s/spent [0-9]+(\.[0-9])?m?s/spent <t>/'; }
# same NAME REPO [MODE]: import keel.yaml from the layout, commit it, run both engines, compare
same() {
  local name="$1" r="$2" mode="${3:-fast}" b c rb rc lb lc
  (cd "$r" && "$BIN" import --force --sums "$SUMS" >/dev/null && git add .agents/keel.yaml .agents/keel.lock >/dev/null 2>&1 &&
    { git rev-parse -q --verify HEAD >/dev/null && git commit -qm keel >/dev/null || true; })
  b="$(cd "$r" && LC_ALL=C bash scripts/gate.sh "$mode" 2>&1)"; rb=$?
  lb="$(norm < "$r/$(log_of "$mode")")"
  c="$(cd "$r" && LC_ALL=C "$BIN" gate "$mode" 2>&1)"; rc=$?
  lc="$(norm < "$r/$(log_of "$mode")")"
  [ "$rb" = "$rc" ] && [ "$(printf '%s\n' "$b" | norm)" = "$(printf '%s\n' "$c" | norm)" ] && [ "$lb" = "$lc" ]
  check "parity: $name (rc $rb)" $?
  if [ "$rb" != "$rc" ] || [ "$(printf '%s\n' "$b" | norm)" != "$(printf '%s\n' "$c" | norm)" ]; then
    diff <(printf '%s\n' "$b" | norm) <(printf '%s\n' "$c" | norm) | head -10 | sed 's/^/    /'
  fi
}
log_of() { if [ "$1" = slow ]; then echo .agents/last-run-slow.log; else echo .agents/last-run.log; fi; }

r="$(mk)"
sensor "$r" scripts/sensors/a.sh "printf 'a\tcorrectness\tpass\tok a\n'"
sensor "$r" scripts/sensors/b.sh "printf 'b\theuristic\tfail\t2 file(s) above baseline\n  src/x.ts: 3 problems (allowed 1)\n  guidance: fix it\n'; exit 1"
sensor "$r" scripts/sensors/c.sh "printf 'c\tcorrectness\tskip\ttool missing - run: make bootstrap\n'; exit 2"
same "pass, fail with details and guidance, skip" "$r"

r="$(mk)"
sensor "$r" scripts/sensors/acentuação-longa-demais.sh "printf 'acentuação-longa-demais\theuristic\tpass\tCódigo em português: 0 arquivos fora do padrão, nenhum acima do baseline\n'"
sensor "$r" scripts/sensors/ação.sh "printf 'ação\tcorrectness\tpass\tnão\n'"
sensor "$r" scripts/sensors/notabs.sh "echo 'no tabs on this line'"
sensor "$r" scripts/sensors/quiet.sh "exit 0"
sensor "$r" scripts/sensors/stderr.sh "printf 'stderr\tcorrectness\tfail\tmixed\n'; echo '  to stderr' >&2; echo '  to stdout'; printf '\n\n'; exit 3"
same "non-ASCII and long fields (byte padding), no TAB, empty output, stderr, rc 3" "$r"

r="$(mk)"
sensor "$r" scripts/sensors/a.sh "printf 'a\tcorrectness\tpass\tok\n'"
sensor "$r" scripts/sensors/_util.sh "exit 1"
sensor "$r" scripts/sensors/disabled/x.sh "exit 1"
sensor "$r" scripts/sensors/slow/s.sh "printf 's\tcorrectness\tpass\tslow one\n'"
sensor "$r" scripts/sensors/architecture.sh "printf 'architecture\tcorrectness\tpass\tok\n'"
sensor "$r" scripts/sensors/architecture-grep.sh "printf 'architecture-grep\tcorrectness\tpass\tok\n'"
same "discovery order and ignored files (fast)" "$r"
same "slow gate" "$r" slow

r="$(mk)"
sensor "$r" scripts/sensors/many.sh "printf 'many\tcorrectness\tfail\tmany\n'; for i in \$(seq 1 60); do echo \"  line \$i\"; done; exit 1"
same "truncation at 40 lines" "$r"

r="$(mk)"; printf 'CEILING_SECONDS=1\r\nSLOW_CEILING_SECONDS=600\r\n' > "$r/.agents/gate.env"
sensor "$r" scripts/sensors/slow1.sh "sleep 1.2; printf 'slow1\tcorrectness\tpass\tslow\n'"
same "over ceiling, CRLF gate.env" "$r"

r="$(mk)"
sensor "$r" scripts/sensors/scope.sh "printf 'scope\tcorrectness\tpass\t%s\n' \"\$(printf '%s' \"\$SCOPE\" | tr '\n' ',')\""
(cd "$r" && git add -A && git commit -qm base); echo 2 > "$r/my file ação.ts"; echo 1 > "$r/b.ts"; mkdir -p "$r/.agents/.gate-lock"
same "SCOPE: untracked, spaces, non-ASCII, run state excluded" "$r"

r="$(mk --no-commit)"
sensor "$r" scripts/sensors/a.sh "printf 'a\tcorrectness\tpass\tok\n'"
same "no commits yet" "$r"

r="$(mk)"
same "no sensors" "$r"
finish
