#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/keel_helpers.sh"
LIB="$KEEL/skills/build/assets/lib/envparse.sh"
[ -f "$LIB" ]; check "envparse.sh exists" $?

d="$(mktemp -d)"; _keel_tmps="$_keel_tmps $d"
# load FILE -> prints the named variables, one per line, or "ERR <message>"
load() {
  local f="$1"; shift
  bash -c '. "$1"; f="$2"; shift 2
    keel_env_load "$f" || { echo "ERR $KEEL_ENV_ERROR"; exit 1; }
    for k in "$@"; do eval "printf \"%s=[%s]\\n\" \"\$k\" \"\${$k-}\""; done' _ "$LIB" "$f" "$@"
}

cat > "$d/ok.env" <<'E'
# Managed by keel-harness - see .agents/README.md
RULE_ID=file-size
KIND=metric                       # metric | structure
  LIMIT=300
INCLUDE='src/'
LAYERS='domain|src/d|com.d||domainModels
web|src/w|com.w|domain|adapter'
NOTE="it's fine"   # trailing comment
LITERAL=$HOME
EMPTY=
E
printf 'CRLF=yes\r\nLAST=noeol' >> "$d/ok.env"
out="$(load "$d/ok.env" RULE_ID KIND LIMIT INCLUDE LAYERS NOTE LITERAL EMPTY CRLF LAST)"
[ "$out" = 'RULE_ID=[file-size]
KIND=[metric]
LIMIT=[300]
INCLUDE=[src/]
LAYERS=[domain|src/d|com.d||domainModels
web|src/w|com.w|domain|adapter]
NOTE=[it'"'"'s fine]
LITERAL=[$HOME]
EMPTY=[]
CRLF=[yes]
LAST=[noeol]' ]; check "parses comments, quotes, multi-line, CRLF, no trailing newline; expands nothing" $?

for case in 'X=$(touch PWNED)|contains $( or a backtick' 'X=`id`|contains $( or a backtick' \
            "X='open|unterminated quote" 'not a line|not a KEY=value line' 'lower=1|not a KEY=value line' \
            "X='a' junk|unexpected text after the closing quote"; do
  printf '%s\n' "${case%%|*}" > "$d/bad.env"
  out="$(cd "$d" && load "$d/bad.env" X)"; rc=$?
  [ $rc -ne 0 ] && printf '%s' "$out" | grep -qF "${case#*|}" && printf '%s' "$out" | grep -qF 'bad.env:1:'
  check "rejects '${case%%|*}' with file:line and reason" $?
done
[ ! -e "$d/PWNED" ]; check "nothing in an env file is executed" $?

# sensors: a hostile env file fails the sensor instead of running; a missing lib is a skip
r="$(new_repo)"
install_asset "$r" build/assets/lib/baseline.sh scripts/lib/baseline.sh
install_asset "$r" build/assets/lib/envparse.sh scripts/lib/envparse.sh
install_asset "$r" rules/assets/sensors/file-size.sh scripts/sensors/file-size.sh
mkdir -p "$r/.agents/rules" "$r/src"
printf 'LIMIT=$(touch PWNED)\nINCLUDE=src\n' > "$r/.agents/rules/file-size.env"
out="$(cd "$r" && bash scripts/sensors/file-size.sh)"; rc=$?
[ $rc -eq 1 ] && [ "$(printf '%s\n' "$out" | head -1 | cut -f1,3)" = "file-size	fail" ] && [ ! -e "$r/PWNED" ]
check "sensor: hostile env -> fail line 1, nothing executed" $?
printf '%s\n' "$out" | grep -q '^  guidance: '; check "sensor: hostile env -> guidance" $?
rm "$r/scripts/lib/envparse.sh"; printf 'LIMIT=10\nINCLUDE=src\n' > "$r/.agents/rules/file-size.env"
out="$(cd "$r" && bash scripts/sensors/file-size.sh)"; rc=$?
[ $rc -eq 2 ] && printf '%s' "$out" | head -1 | grep -q 'envparse.sh is missing'; check "sensor: missing lib -> skip naming it" $?

finish
