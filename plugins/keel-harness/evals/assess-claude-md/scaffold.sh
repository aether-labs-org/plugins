#!/usr/bin/env bash
# The assess-mature-repo repository plus a 20-line AGENTS.md and a CLAUDE.md that does not import
# it. Claude Code would skip AGENTS.md entirely, so the Context axis must come out `partial`.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$here/../assess-mature-repo/scaffold.sh"

{
  printf '# AGENTS.md — ledger\nTypeScript / Node ledger service. Last updated: 2026-10-20.\n\n## Commands\n'
  printf '| Purpose | Command | Pass signal |\n| --- | --- | --- |\n'
  printf '| Build | `npm run build` | exit 0 |\n| Lint | `npm run lint` | exit 0 |\n| Test | `npm test` | all tests pass |\n\n'
  printf '## Before you finish\nRun the build, lint and test commands above and read them.\n\n'
  printf '## Reading tool output\n- The first error in a chain is the root cause.\n'
  printf -- '- Test failures: fix top-down.\n'
} > AGENTS.md
printf '# Project notes\nUse npm. Keep functions small.\n' > CLAUDE.md
git add -A && git -c user.email=eval@local -c user.name=eval commit -qm "add instruction files"
