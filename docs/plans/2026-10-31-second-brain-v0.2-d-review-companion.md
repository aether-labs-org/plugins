# second-brain v0.2.3 (Milestone D: review companion) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The human reviews agent output inside Obsidian (desktop and mobile) and a review is verifiable: `reviewed_hash` pins the reviewed text, `sb lint` reports drift, and the `second-brain-companion` Obsidian plugin marks reviews, accepts agent blocks and shows a trust badge.

**Architecture:** One hash definition with shared test vectors, implemented twice: Python (`lib/sb/review.py`, used by `sb review` and lint) and TypeScript (`src/hash.ts` in a new repository). The Obsidian plugin writes trust fields through Obsidian's own APIs; the agent is still denied those fields by the guard (milestone B).

**Tech Stack:** Python 3.9+ standard library; TypeScript, esbuild and the Obsidian API from `obsidianmd/obsidian-sample-plugin`; Vitest; Web Crypto (`crypto.subtle`); BRAT for distribution.

**Spec:** `docs/specs/2026-10-31-second-brain-v0.2-design.md` (§7, D19, D28, D31). Requires milestones A–C.

## Global Constraints

- Hash: `reviewed_hash: sha256:<first 16 lowercase hex>` of the **review body** (spec §7.1): body after the frontmatter (exactly what `frontmatter.parse` returns as `body`, i.e. after BOM strip and CRLF → LF), minus trailing `> [!agent]` callouts, trailing spaces and tabs removed per line (`[ \t]+$`, not `str.rstrip()`), leading and trailing blank lines removed. No Unicode normalisation.
- Lint codes: `SB110` reviewed text changed since review (warning, fails `sb lint`); `SB112` reviewed note has agent blocks pending (info).
- Companion: repository `aether-labs-org/second-brain-companion` (the user creates it on GitHub); local path `~/Code/aether-labs/second-brain-companion`; plugin id `second-brain-companion`; `isDesktopOnly: false`; no Node APIs; license Apache-2.0 (as the Claude plugin).
- The agent never sets trust fields: `sb review` is denied to the agent's Bash (milestone B, D28).
- Plugin version becomes `0.2.3`.
- **Never commit, push, create a GitHub repository or publish a release without asking the user.** Checkpoint steps: stop, show `git status --short` in the repo concerned.

## Review Focus

1. **Obsidian rewrites the frontmatter** when the companion sets properties (quotes, block lists, key order): the body hash must not change. → Task 4 `marks reviewed without touching the body` (integration-style test over the pure functions).
2. **Agent block in the middle of a note** (not trailing): it is part of the reviewed text, not stripped. → Task 1 vector `agent-block-in-middle`.
3. **Note edited on mobile with CRLF or trailing spaces**: no false `SB110`. → Task 1 vectors `crlf`, `trailing-spaces`.
4. **`reviewed` set by hand without `reviewed_hash`** (vaults from before D): no `SB110`; review stays valid until re-marked. → Task 2 `test_reviewed_without_hash_is_not_sb110`.
5. **Accept agent blocks on a note with no blocks**: the command is a no-op with a notice, not a rewrite. → Task 4 `acceptAgentBlocks is a no-op without blocks`.

---

## File Structure

| Path | Responsibility |
| --- | --- |
| `plugins/second-brain/lib/sb/review.py` | Create: `review_body`, `review_hash`, `split_trailing_agent_blocks` |
| `plugins/second-brain/lib/sb/frontmatter.py` | Modify: `set_keys` |
| `plugins/second-brain/lib/sb/lint.py`, `lib/sb/cli.py` | `SB110`, `SB112`, `sb review` |
| `tests/fixtures/review-hash/vectors.json` | Shared vectors (source of truth) |
| `tests/python/test_sb_review.py` | Python tests |
| `second-brain-companion/manifest.json`, `package.json`, `esbuild.config.mjs`, `versions.json` | Plugin scaffold |
| `second-brain-companion/src/hash.ts` | Body split + hash |
| `second-brain-companion/src/blocks.ts` | Agent block detection and unwrap |
| `second-brain-companion/src/main.ts` | Commands, status bar |
| `second-brain-companion/styles.css` | `agent` callout |
| `second-brain-companion/test/*.test.ts`, `test/vectors.json` | Vitest; copy of the shared vectors |

---

### Task 1: Review hash and shared vectors (Python)

**Files:**
- Create: `plugins/second-brain/lib/sb/review.py`, `tests/fixtures/review-hash/vectors.json`, `tests/python/test_sb_review.py`

**Interfaces:**
- Produces: `review.split_trailing_agent_blocks(body: str) -> tuple` → `(kept: str, blocks: list[str])`; `review.review_body(text: str) -> str` (whole file in); `review.review_hash(text: str) -> str` → `"sha256:" + 16 hex`.
- `vectors.json`: `[{"name": str, "file": str, "review_body": str, "hash": str}]` with at least these names: `plain`, `crlf`, `bom`, `trailing-spaces`, `leading-trailing-blank-lines`, `trailing-agent-block`, `two-trailing-agent-blocks`, `agent-block-in-middle`, `empty-body`, `nfd-vs-nfc` (two entries with different hashes, documenting no normalisation), `frontmatter-reformatted` (same body as `plain`, different frontmatter → same hash).

> **Vectors already authored** by the companion work (16 entries): copy `~/Code/aether-labs/second-brain-companion/test/vectors.json` to `tests/fixtures/review-hash/vectors.json` instead of Step 1. Companion Tasks 3–5 are done there (commits `6e7d3ab`, `95c5584`, `9f5f284`; `trustState` takes an optional third `path` argument; `minAppVersion` 1.4.4).

- [ ] **Step 1: Write the vectors by hand** (`file` and expected `review_body`); generate `hash` with a one-off `python3 -c` using `hashlib.sha256(review_body.encode("utf-8")).hexdigest()[:16]` — the hash is the only computed field.
- [ ] **Step 2: Test** `test_vectors` iterates the file asserting `review_body(file) == review_body` and `review_hash(file) == hash`; `test_hash_format` asserts `re.fullmatch(r"sha256:[0-9a-f]{16}", ...)`.
- [ ] **Step 3: Run** `python3 -m unittest tests/python/test_sb_review.py -v` — FAIL. **Step 4: Implement** (reuse `frontmatter.parse` and `trust.AGENT_BLOCK_RE`; a trailing block is a run of lines starting at an `AGENT_BLOCK_RE` line where every following non-blank line starts with `>`, up to the end of the body). **Step 5: Run** — PASS. **Step 6: Checkpoint.**

---

### Task 2: `sb review` and lint `SB110` / `SB112`

**Files:**
- Modify: `plugins/second-brain/lib/sb/frontmatter.py`, `plugins/second-brain/lib/sb/lint.py`, `plugins/second-brain/lib/sb/cli.py`, `plugins/second-brain/skills/lint/SKILL.md`
- Test: `tests/python/test_sb_review.py`, `tests/python/test_sb_frontmatter.py`, `tests/python/test_sb_guard.py`

**Interfaces:**
- Produces: `frontmatter.set_keys(text: str, updates: dict) -> str` (replaces the line of an existing scalar key in place, appends new keys before the closing `---`, leaves every other line byte-identical); CLI `sb review NOTE [--json]` → sets `reviewed: <today>` and `reviewed_hash`, prints the hash; exit `2` if the note is missing. `lint.INFO_CODES` gains `SB112`.

- [ ] **Step 1: Tests**

```python
def test_set_keys_preserves_other_lines(self):
    text = "---\ntitle: A\ntags:\n  - x\nreviewed:\n---\nBody\n"
    self.assertEqual(set_keys(text, {"reviewed": "2026-11-05", "reviewed_hash": "sha256:0123456789abcdef"}),
                     "---\ntitle: A\ntags:\n  - x\nreviewed: 2026-11-05\nreviewed_hash: sha256:0123456789abcdef\n---\nBody\n")

def test_sb_review_then_edit_triggers_sb110(self): ...       # review -> lint clean; edit body -> SB110
def test_agent_block_after_review_is_sb112_not_sb110(self): ...
def test_reviewed_without_hash_is_not_sb110(self): ...
def test_guard_still_denies_agent_sb_review(self): ...       # regression of milestone B
```

- [ ] **Step 2: Run** — FAIL. **Step 3: Implement.** `SB110` message: `reviewed text changed since <reviewed>; review again (Obsidian: "Mark as reviewed", or sb review)`. `SB112`: `<n> agent block(s) waiting for review`. `lint` skill: list both codes and say the agent never runs `sb review`.
- [ ] **Step 4: Run** `bash tests/sb_cli_test.sh` — PASS. **Step 5: Checkpoint.**

---

### Task 3: Companion repository scaffold

**Files (new repository `~/Code/aether-labs/second-brain-companion`):**
- Create: from `obsidianmd/obsidian-sample-plugin` (shallow clone, `.git` removed, `git init`), then edit `manifest.json`, `package.json`, `README.md`, `LICENSE`; add `vitest` as a dev dependency and `"test": "vitest run"`.

- [ ] **Step 1: Scaffold** and set `manifest.json`: `"id": "second-brain-companion"`, `"name": "Second Brain Companion"`, `"description": "Review notes written by the second-brain Claude Code plugin: mark reviewed, accept agent blocks, see trust status."`, `"author": "Aether Labs"`, `"isDesktopOnly": false`, `"minAppVersion"`: the sample plugin's current value. `versions.json` maps `0.1.0` to it.
- [ ] **Step 2: Copy** `tests/fixtures/review-hash/vectors.json` from the plugins repo to `test/vectors.json`; README states the plugins repo copy is the source of truth and both must change together.
- [ ] **Step 3: Verify:** `npm install && npm run build && npm test` — Expected: build emits `main.js`; Vitest reports no test files or passes the sample.
- [ ] **Step 4: Checkpoint** (local repository only; creating `aether-labs-org/second-brain-companion` on GitHub and the first push are the user's call).

---

### Task 4: Hash, blocks and commands (TypeScript)

**Files:**
- Create: `src/hash.ts`, `src/blocks.ts`, `test/hash.test.ts`, `test/blocks.test.ts`
- Modify: `src/main.ts` (replace the sample code)

**Interfaces:**
- Produces: `splitFrontmatter(text: string): { frontmatter: string; body: string }` (same rules as Python `parse`: strip BOM, CRLF → LF, body = lines after the closing `---`); `reviewBody(text: string): string`; `reviewHash(text: string): Promise<string>` (`crypto.subtle.digest("SHA-256", new TextEncoder().encode(body))`, first 16 hex, `"sha256:"` prefix); `splitTrailingAgentBlocks(body: string): { kept: string; blocks: string[] }`; `unwrapAgentBlocks(text: string): string` (drops each trailing block's header line and the `> ` prefix of its other lines, keeps a blank line between blocks; returns `text` unchanged when there are none).
- Commands (ids prefixed by the plugin id): `mark-reviewed` — `reviewHash` of the current file, then `app.fileManager.processFrontMatter(file, fm => { fm.reviewed = <today YYYY-MM-DD>; fm.reviewed_hash = hash; })`; `accept-agent-blocks` — `app.vault.process(file, unwrapAgentBlocks)` then `mark-reviewed`; Notice `No agent blocks in this note.` when none; `toggle-protected` — flips `fm.protected` between `true` and absent.

- [ ] **Step 1: Tests**

```ts
it.each(vectors)("$name", async (v) => {
  expect(reviewBody(v.file)).toBe(v.review_body);
  expect(await reviewHash(v.file)).toBe(v.hash);
});
it("acceptAgentBlocks is a no-op without blocks", () => { expect(unwrapAgentBlocks(PLAIN)).toBe(PLAIN); });
it("unwraps two trailing blocks", () => { /* exact expected text */ });
it("marks reviewed without touching the body", async () => {
  // simulate processFrontMatter by re-serialising the frontmatter with quoted values and block lists;
  // reviewHash(before) === reviewHash(after)
});
```

- [ ] **Step 2: Run** `npm test` — FAIL. **Step 3: Implement** `hash.ts`, `blocks.ts`, then wire commands in `main.ts`. **Step 4: Run** `npm test && npm run build` — PASS. **Step 5: Checkpoint.**

---

### Task 5: Status badge and callout style

**Files:**
- Modify: `src/main.ts`, `styles.css`

**Interfaces:**
- Produces: `trustState(text: string, frontmatter: Record<string, unknown>): Promise<"unreviewed" | "reviewed" | "changed-since-review" | "agent-blocks-pending" | "none">` in `src/hash.ts` — `none` outside `wiki/` or for non-notes; `unreviewed` when `origin` is `agent`/`mixed` and `reviewed` is empty; `changed-since-review` when `reviewed_hash` is set and differs; `agent-blocks-pending` when trailing agent blocks exist; else `reviewed`.
- Status bar text: `SB: unreviewed` · `SB: reviewed` · `SB: changed since review` · `SB: agent blocks pending`; updated on `active-leaf-change` and `metadataCache.on("changed")`. On mobile Obsidian hides the status bar; there, each command's Notice reports the resulting state (e.g. `Marked as reviewed (sha256:…)`).
- `styles.css`: `.callout[data-callout="agent"] { --callout-color: <a neutral blue RGB>; --callout-icon: lucide-bot; }`.

- [ ] **Step 1: Tests** for `trustState` covering each state. **Step 2: Run** — FAIL. **Step 3: Implement.** **Step 4: Run** `npm test && npm run build` — PASS. **Step 5: Checkpoint.**

---

### Task 6: Release, manual QA, plugin-side docs

**Files:**
- Companion: `README.md` (BRAT install: add `aether-labs-org/second-brain-companion` in BRAT), `versions.json`
- Plugins repo: `plugins/second-brain/README.md`, `plugins/second-brain/templates/CLAUDE.md`, `plugins/second-brain/lib/sb/doctor.py` (recommendation text), `plugins/second-brain/.claude-plugin/plugin.json` (`0.2.3`), `tests/sb_structure_test.sh`

- [ ] **Step 1: Manual QA** in a scratch vault with the built plugin copied to `.obsidian/plugins/second-brain-companion/`, on desktop and on a phone (sync the scratch vault or install via BRAT after the user publishes): each command, each badge state, a note whose frontmatter Obsidian reformats; then `sb lint` agrees with the badge for every note (no `SB110` after "Mark as reviewed"; `SB110` after a body edit). Record results.
- [ ] **Step 2: Plugin docs:** README "Reviewing" section (Bases view → open note → "Mark as reviewed" or "Accept agent blocks"; CLI alternative `sb review` run by the human); template rule: "`reviewed`/`reviewed_hash` are set by the human through the companion or `sb review`"; doctor recommendation row for the companion.
- [ ] **Step 3: Verify** `make check`, `make validate` in the plugins repo; `npm test && npm run build` in the companion.
- [ ] **Step 4: Release (user's go-ahead required):** the user creates `aether-labs-org/second-brain-companion`; on approval push, tag `0.1.0`, and create a GitHub release with `main.js`, `manifest.json`, `styles.css`. Exit criteria (spec §7): all shared vectors equal in Python and TypeScript; manual QA passes on desktop and mobile; BRAT install works from the release.
- [ ] **Step 5: Checkpoint** — ask the user whether to commit milestone D in the plugins repo.

## Self-Review notes

- Spec §7.1 → Tasks 1–2; §7.2 → Tasks 3–6; D28 → Task 2 regression test; D31 → Global Constraints and Task 6.
- The vectors file in the plugins repo is the single source of truth; the companion keeps a copy (no cross-repo network access in tests).
