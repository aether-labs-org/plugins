#!/usr/bin/env bash
# Export a .drawio file to png|svg|pdf with the diagram XML embedded (stays editable).
# Usage: export_drawio.sh <file.drawio> [png|svg|pdf]   -> writes <file>.drawio.<fmt> beside it.
# Sensor contract line 1. Exit 0 pass / 1 fail / 2 skip (draw.io Desktop not installed).
set -uo pipefail
id=drawio-export
class=correctness
src="$1"; fmt="${2:-svg}"
if ! command -v drawio >/dev/null 2>&1; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "draw.io Desktop CLI not found - install it from https://github.com/jgraph/drawio-desktop/releases; the .drawio file is still the deliverable"
  exit 2
fi
src_abs="$(cd "$(dirname "$src")" && pwd)/$(basename "$src")"
out_abs="$src_abs.$fmt"
work="$(dirname "$src_abs")"
tmp=""
# The snap build of draw.io can only read and write non-hidden paths under $HOME.
bin="$(command -v drawio)"
case "$bin:$(readlink -f "$bin")" in
  /snap/*|*/snap)
    case "$src_abs" in
      "$HOME"/.*|"$HOME"/*/.*) tmp=1 ;;
      "$HOME"/*) ;;
      *) tmp=1 ;;
    esac ;;
esac
if [ -n "$tmp" ]; then
  work="$(mktemp -d "$HOME/sa-drawio-export.XXXXXX")"
  cp "$src_abs" "$work/"
fi
in="$work/$(basename "$src_abs")"
timeout 120 drawio -x -f "$fmt" -e -b 10 -o "$in.$fmt" "$in" >/dev/null 2>&1
if [ -s "$in.$fmt" ]; then
  [ -n "$tmp" ] && mv "$in.$fmt" "$out_abs" && rm -rf "$work"
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" pass "exported $out_abs with the diagram embedded"
  exit 0
fi
[ -n "$tmp" ] && rm -rf "$work"
printf '%s\t%s\t%s\t%s\n' "$id" "$class" fail "draw.io produced no $fmt for $src"
printf '  guidance: open %s in draw.io; if it fails to load, re-run the diagram validator first.\n' "$src"
exit 1
