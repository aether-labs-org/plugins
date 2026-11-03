#!/usr/bin/env bash
# A minimal web fixture: a static page with one Playwright journey (add an item to the cart), the bundled
# gate runner, the opt-in journey sensor, and one uncommitted regression (the button adds two items).
# Needs network at scaffold time: npm install, and the Chromium that Playwright drives.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$here/../rules-brownfield/harness.sh"
git init -q
install_harness
mkdir -p public e2e scripts/lib scripts/sensors/slow .agents/rules docs
cp "$here/../../assets/core/lib/envparse.sh" scripts/lib/envparse.sh
cp "$here/../../assets/core/sensors/slow/journey.sh" scripts/sensors/slow/journey.sh
chmod +x scripts/sensors/slow/journey.sh
cat > package.json <<'JSON'
{
  "name": "shop",
  "version": "1.0.0",
  "private": true,
  "scripts": { "start": "node server.js", "test:e2e": "playwright test" },
  "devDependencies": { "@playwright/test": "1.48.2" }
}
JSON
cat > playwright.config.js <<'JS'
const { defineConfig } = require("@playwright/test");
module.exports = defineConfig({
  testDir: "e2e",
  workers: 1,
  use: { baseURL: "http://127.0.0.1:4173" },
  webServer: { command: "node server.js", url: "http://127.0.0.1:4173", reuseExistingServer: false },
});
JS
cat > server.js <<'JS'
const http = require("http");
const fs = require("fs");
const path = require("path");
http.createServer((req, res) => {
  const file = path.join(__dirname, "public", req.url === "/" ? "index.html" : req.url);
  fs.readFile(file, (err, data) => {
    if (err) { res.writeHead(404); res.end("not found"); return; }
    res.writeHead(200, { "Content-Type": file.endsWith(".js") ? "text/javascript" : "text/html" });
    res.end(data);
  });
}).listen(4173, "127.0.0.1");
JS
cat > public/index.html <<'HTML'
<!doctype html>
<html><body>
  <h1>Shop</h1>
  <button id="add">Add to cart</button>
  <p id="count">Cart: 0</p>
  <script src="/app.js"></script>
</body></html>
HTML
cat > public/app.js <<'JS'
let count = 0;
document.getElementById("add").addEventListener("click", () => {
  count += 1;
  document.getElementById("count").textContent = "Cart: " + count;
});
JS
cat > e2e/cart.spec.js <<'JS'
const { test, expect } = require("@playwright/test");
test("add to cart updates the count", async ({ page }) => {
  await page.goto("/");
  await page.click("#add");
  await expect(page.locator("#count")).toHaveText("Cart: 1");
});
JS
cat > docs/testing.md <<'MD'
# Testing

<a id="journey"></a>
### User journeys run in the slow gate

**Rule.** `make gate-slow` runs the Playwright journeys under `e2e/`.
**Why.** A flow that works in each unit can still be broken end to end.
**When it fails.** Open the trace it prints and fix the behaviour; do not edit the journey.
MD
cat > .agents/rules/journey.env <<'ENV'
RULE_ID=journey
KIND=convention
ORIGIN=user
APPROVED_AT=2026-10-29
ENFORCEMENT=sensor:journey
DOC=docs/testing.md#journey
JOURNEY_DIR=e2e
ENV
printf 'node_modules/\ntest-results/\n' >> .gitignore
npm install --no-audit --no-fund --silent
npx playwright install chromium
git add -A && git -c user.email=eval@local -c user.name=eval commit -qm "shop"
# The planted regression, left uncommitted: one click now adds two items.
sed -i 's/count += 1;/count += 2;/' public/app.js
