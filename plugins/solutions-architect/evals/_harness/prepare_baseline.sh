#!/usr/bin/env bash
# Builds the v0.2.0 arm: the plugin as it was at the v0.2.0 commit, with the CURRENT evals/
# overlaid so both arms run the same cases. Usage: prepare_baseline.sh <output dir>
# Prints the plugin directory to pass to run.py / `claude plugin eval`. Runs no model.
set -euo pipefail
out="${1:?usage: prepare_baseline.sh <output dir>}"
base="1d82dd9"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin="$(cd "$here/../.." && pwd)"
top="$(git -C "$plugin" rev-parse --show-toplevel)"
rel="${plugin#"$top"/}"
mkdir -p "$out"
git -C "$top" archive "$base" "$rel" | tar -x -C "$out"
rm -rf "$out/$rel/evals"
cp -r "$plugin/evals" "$out/$rel/evals"
rm -rf "$out/$rel/evals/results"
echo "$out/$rel"
