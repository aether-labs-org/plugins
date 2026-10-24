#!/usr/bin/env bash
# keel_run_sensor.sh FILE -> runs one sensor from the repository root the way the selected engine
# does: `bash FILE` (KEEL_ENGINE=bash), or `keel gate --sensor <id>` on a keel.yaml imported from
# the same layout (KEEL_ENGINE=cli). SCOPE, KEEL_MEASURE and the rest of the environment pass through.
if [ "${KEEL_ENGINE:-bash}" = cli ]; then
  "$KEEL_BIN" import --force --sums "$KEEL_SUMS" >/dev/null || exit 3
  exec "$KEEL_BIN" gate --sensor "$(basename "$1" .sh)"
fi
exec bash "$1"
