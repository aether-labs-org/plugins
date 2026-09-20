#!/usr/bin/env bash
# Builds a small but mature TypeScript repository in the empty eval workspace:
# lockfile + build target + tsconfig + eslint + tests, no AGENTS.md, no docs/, no CI.
set -euo pipefail

mkdir -p src
cat > package.json <<'JSON'
{
  "name": "ledger",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "build": "tsc -p tsconfig.json",
    "lint": "eslint src",
    "test": "vitest run"
  },
  "devDependencies": { "typescript": "5.6.2", "eslint": "9.11.1", "vitest": "2.1.1" }
}
JSON
cat > package-lock.json <<'JSON'
{ "name": "ledger", "version": "1.0.0", "lockfileVersion": 3, "requires": true, "packages": {} }
JSON
cat > tsconfig.json <<'JSON'
{ "compilerOptions": { "strict": true, "target": "ES2022", "outDir": "dist" }, "include": ["src"] }
JSON
cat > eslint.config.js <<'JS'
export default [{ files: ["src/**/*.ts"], rules: { "no-console": "error" } }];
JS
cat > src/posting.ts <<'TS'
export function applyFee(cents: number): number {
  return Math.round(cents * 0.98);
}
TS
cat > src/posting.test.ts <<'TS'
import { expect, test } from "vitest";
import { applyFee } from "./posting";
test("applies the fee", () => { expect(applyFee(1224)).toBe(1200); });
TS
git init -q && git add -A && git -c user.email=eval@local -c user.name=eval commit -qm "initial"
