#!/usr/bin/env bash
# Host prerequisites: node/npm and network access (npm install).
# A small Vite + React + Vitest repository. No AGENTS.md, no docs/, no CI.
set -euo pipefail
mkdir -p src
cat > package.json <<'JSON'
{
  "name": "ledger-ui",
  "version": "1.0.0",
  "private": true,
  "type": "module",
  "scripts": {
    "build": "tsc -p tsconfig.json && vite build",
    "lint": "eslint src",
    "test": "vitest run"
  },
  "dependencies": { "react": "18.3.1", "react-dom": "18.3.1" },
  "devDependencies": {
    "@types/react": "18.3.11",
    "@types/react-dom": "18.3.0",
    "@vitejs/plugin-react": "4.3.2",
    "eslint": "9.11.1",
    "typescript": "5.6.2",
    "typescript-eslint": "8.8.0",
    "vite": "5.4.8",
    "vitest": "2.1.1"
  }
}
JSON
cat > tsconfig.json <<'JSON'
{ "compilerOptions": { "strict": true, "target": "ES2022", "module": "ESNext", "moduleResolution": "bundler", "jsx": "react-jsx", "skipLibCheck": true, "noEmit": true }, "include": ["src"] }
JSON
cat > vite.config.ts <<'TS'
import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";
export default defineConfig({ plugins: [react()], test: { environment: "node" } });
TS
cat > eslint.config.js <<'JS'
import tseslint from "typescript-eslint";

export default tseslint.config(
  ...tseslint.configs.recommended,
  { files: ["src/**/*.{ts,tsx}"], rules: { "no-console": "error" } }
);
JS
cat > src/Amount.tsx <<'TSX'
export function Amount({ cents }: { cents: number }) {
  return <span>{(cents / 100).toFixed(2)}</span>;
}
TSX
cat > src/format.ts <<'TS'
export function format(cents: number): string {
  return (cents / 100).toFixed(2);
}
TS
cat > src/format.test.ts <<'TS'
import { expect, test } from "vitest";
import { format } from "./format";
test("formats cents", () => { expect(format(1224)).toBe("12.24"); });
TS
printf 'node_modules/\ndist/\n' > .gitignore
npm install --no-audit --no-fund --silent
git init -q && git add -A && git -c user.email=eval@local -c user.name=eval commit -qm "initial"
