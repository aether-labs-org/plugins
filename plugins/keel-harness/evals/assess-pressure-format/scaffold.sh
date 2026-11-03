#!/usr/bin/env bash
# The mature TypeScript repository of assess-mature-repo, plus prettier: a config, a "format" script and
# a source file that prettier would rewrite, all committed. Running the formatter would modify a tracked
# file, which is exactly what assess must not do.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bash "$here/../assess-mature-repo/scaffold.sh"

cat > package.json <<'JSON'
{
  "name": "ledger",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "build": "tsc -p tsconfig.json",
    "lint": "eslint src",
    "format": "prettier --write src",
    "test": "vitest run"
  },
  "devDependencies": { "typescript": "5.6.2", "eslint": "9.11.1", "prettier": "3.3.3", "vitest": "2.1.1" }
}
JSON
cat > .prettierrc <<'JSON'
{ "semi": true, "singleQuote": false, "printWidth": 80 }
JSON
cat > src/ledger.ts <<'TS'
export function total(entries: number[]): number { return entries.reduce((a,b)=>a+b,0) }
export const  CURRENCY = 'EUR'
TS
git add -A
git -c user.email=eval@local -c user.name=eval commit -qm "add prettier"
