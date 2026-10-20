#!/usr/bin/env bash
# The doctor-finds-drift repository (TypeScript repo + harness fixture + AGENTS.md), but with the
# AGENTS.md size drift removed and a CLAUDE.md that does not import it: exactly one condition is broken.
# Host prerequisite for exactly one warning: gitleaks installed (otherwise secrets also reports
# sensor-unavailable).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$here/../doctor-finds-drift/scaffold.sh"
# drop the 120 filler lines appended by doctor-finds-drift
sed -i '/^- filler pointer line$/d' AGENTS.md
printf '# Project notes\nUse npm. Keep functions small.\n' > CLAUDE.md
git add -A && git -c user.email=eval@local -c user.name=eval commit -qm "claude.md without the import"
