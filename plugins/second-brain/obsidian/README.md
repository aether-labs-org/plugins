# Second Brain Companion

Obsidian plugin (desktop and mobile) for vaults managed by the
second-brain Claude Code plugin (this folder lives inside it, `plugins/second-brain/obsidian/`). It lets the human
review what the agent wrote, and records that review so `sb lint` can verify it.

## Commands

- **Mark as reviewed**: writes `reviewed` (today) and `reviewed_hash` to the note's frontmatter.
- **Accept agent blocks**: unwraps the trailing `> [!agent]` callouts into plain text, then marks the note reviewed.
- **Toggle protected**: sets or removes `protected: true`.

The status bar (desktop) shows the active note's state: `SB: unreviewed`, `SB: reviewed`,
`SB: changed since review` or `SB: agent blocks pending`. On mobile, where the status bar is hidden,
each command reports the resulting state in a notice.

## The review hash

`reviewed_hash: sha256:<first 16 hex>` of the **review body**: the text after the frontmatter
(BOM stripped, CRLF read as LF), without trailing `> [!agent]` callouts, with trailing whitespace
removed from each line and leading/trailing blank lines removed. No Unicode normalisation.

The same definition is implemented in Python in the second-brain plugin (`sb review`, `sb lint`).
The tests read `tests/fixtures/review-hash/vectors.json` at the repository root, the single set of
vectors shared with the Python tests; **change `src/hash.ts`, `src/blocks.ts` and
`lib/sb/review.py` together.**

## Install

The built plugin (`dist/`) is bundled in the second-brain plugin. `sb init` and
`sb init --upgrade --yes` copy it into `<vault>/.obsidian/plugins/second-brain-companion/`. Enable it
once in Obsidian: Settings → Community plugins → turn off Restricted mode → enable
"Second Brain Companion". Nothing enables it for you.

## Development

```bash
npm ci
npm test        # vitest
npm run build   # type-check + bundle to dist/ (main.js, manifest.json, styles.css)
```

`dist/` is committed (it is what ships); `tests/sb_companion_test.sh` fails when it is stale.
After changing the version, update `manifest.json` and `versions.json` by hand: `sb init --upgrade`
only replaces an installed copy when the bundled version is newer.

## License

Apache-2.0, Aether Labs.
