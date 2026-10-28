#!/usr/bin/env bash
# The doctor-finds-drift repository (TypeScript repo + harness fixture + AGENTS.md) with the AGENTS.md
# size drift removed, then: the guard sensor is missing, and the repository's own harness-check.sh is
# an older copy that has no guard-missing check, so `make harness-check` reports a clean harness.
# Only the plugin's current validator finds it - that is what doctor adds over the repository's copy.
# Host prerequisite: gitleaks installed (otherwise secrets also reports sensor-unavailable).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$here/../doctor-finds-drift/scaffold.sh"
# drop the 120 filler lines appended by doctor-finds-drift
sed -i '/^- filler pointer line$/d' AGENTS.md
rm scripts/sensors/guard.sh
sed '/^check_guard_missing$/d' "$here/../../assets/core/harness-check.sh" > scripts/harness-check.sh
chmod +x scripts/harness-check.sh
printf '\nharness-check:\n\t@bash scripts/harness-check.sh\n' >> Makefile
git add -A && git -c user.email=eval@local -c user.name=eval commit -qm "older validator, no guard sensor"
