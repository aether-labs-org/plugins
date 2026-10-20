#!/usr/bin/env bash
# package.json + tsconfig.json + the harness from the bundled assets, no src/. No npm install needed:
# the gate has no tool sensors to run yet (a gate with zero runnable sensors is valid).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$here/../rules-brownfield/harness.sh"
cat > package.json <<'JSON'
{ "name": "ledger", "version": "0.1.0", "private": true, "type": "module",
  "scripts": { "build": "tsc -p tsconfig.json", "test": "vitest run" },
  "devDependencies": { "typescript": "5.6.2", "vitest": "2.1.1" } }
JSON
cat > tsconfig.json <<'JSON'
{ "compilerOptions": { "strict": true, "target": "ES2022", "outDir": "dist" }, "include": ["src"] }
JSON
printf 'node_modules/\n' > .gitignore
install_harness
sed -i 's/^mode: brownfield/mode: greenfield/' .agents/state.yml
git init -q && git add -A && git -c user.email=eval@local -c user.name=eval commit -qm "initial"
