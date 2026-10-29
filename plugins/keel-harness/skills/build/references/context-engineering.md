# Context Engineering — keep AGENTS.md a lean, agent-readable index

Context Engineering is about *how* you hand context to the agent so it succeeds. The model has a
finite context window. Giant generic manuals become "non-guidance": the agent drowns in secondary
rules and loses the real goal. Worse, large instruction files rot — humans stop maintaining what
can't be mechanically verified.

**Evidence.** Gloaguen et al., ICLR 2026 (arXiv 2602.11988): LLM-generated context files changed
the success rate by about -0.5 % to -2 % at +20-23 % cost, developer-written ones did better, and
repository overviews did not help; tool instructions were followed. So: repository overviews do not
help, commands and non-standard conventions do. Lulla et al. (arXiv 2601.20404) measured a lower
median runtime with an `AGENTS.md` present.

Based on AI Hero, *A Complete Guide to AGENTS.md — Progressive Disclosure*.

---

## Progressive disclosure

Put **only essentials** in the root AGENTS.md; push everything else into `docs/` that loads **only
when relevant**. AGENTS.md is a map: it says *where to look* and *how to verify*, never the full
content.

**Belongs in AGENTS.md:**
- One-sentence project identity (role-anchoring context).
- Package manager / non-standard build & run commands.
- Computational sensors (commands + pass signals) and Shift-Left gates.
- One-line pointers (`→ docs/X.md`) to deeper guidance.

**Does NOT belong in AGENTS.md (move to `docs/`):**
- Language-specific coding rules → `docs/<LANG>.md`.
- Full architecture explanations → `docs/architecture.md`.
- API conventions, data model → `docs/api.md`, `docs/data-model.md`.
- Obvious advice ("write clean code"), filesystem dumps, anything the model already knows.

## Token budget

Every token loads on every request. A bloated AGENTS.md spends the agent's instruction budget on
irrelevant rules, leaving less for the actual task. Hard cap: 100 lines, root and nested files alike. If it grows,
extract sections to `docs/` and replace with pointers.

---

## Agent-readable observational formats (the Context Engineering section of AGENTS.md)

This is what makes the file agent-friendly rather than human-friendly. Tell the agent how to parse
the data it will observe without drowning in noise. Always include at least the log format and the
first-error-is-root-cause tip.

### Logs
- **Format**: state the real shape, e.g. `{timestamp} [{level}] {service} — {message}`
  (e.g. `2024-01-15 ERROR auth — JWT expired`).
- **Signal vs noise**: ignore `DEBUG` unless tracing a specific subsystem (auth/DB).
- **Root cause**: search backward from the first `ERROR` for the originating `WARN`.

### Structured logs (profile L, experimental)

For an agent that runs for hours, a log it can filter beats a log it must read. Tell it, in the
`Context Engineering` section of `AGENTS.md` or in `docs/observability.md`, that the service writes
**one JSON object per line**, with these keys on every line:

```json
{"ts":"2026-10-29T14:03:11.482Z","level":"error","service":"checkout","msg":"payment declined","trace_id":"a1b2c3","route":"POST /orders","err":"card_declined"}
```

- **Why one object per line.** `grep '"level":"error"' app.log` and `grep a1b2c3 app.log` work without a
  parser, a stack trace stays inside one line (`"stack":"..."`) instead of splitting into lines that
  match nothing, and the same line is machine-readable when a tool, not a person, reads it.
- **Why fixed keys.** `ts`, `level`, `service` and `msg` are what an agent filters on; extra keys (`route`,
  `err`, ids) carry the context. A key that changes name between services forces a guess.
- **Why a `trace_id`.** One request crosses several lines, and several services. The agent follows it with one
  `grep` instead of reading around timestamps.
- **No secrets and no personal data in a line**: the agent will read it, and so will whatever stores the log.
- **Pair it with the journey sensor.** When a Playwright journey fails (`slow/journey.sh`), the
  trace names the step and the `trace_id` ties that step to the server's lines. State the log file or the command
  that prints it (`docker compose logs app`) in `AGENTS.md`; never assume the agent can guess it.

### Reading sensor / tool output
- **Test failures**: the first `FAIL`/`Error` line is the root; lines below are cascade — fix
  top-down.
- **Lint errors**: format is usually `file:line:col rule-name` — jump straight to that location.
- **Type errors**: the first error in a chain is the real type mismatch; the rest are consequences.
- **Build errors**: ignore warnings on the first pass; fix errors in dependency order.

(Stack-specific output formats live in each profile's "Reading sensor output" section.)

### Metrics / dashboards
- Name the key metric and its alert threshold; point to `→ docs/observability.md` for the rest.

### DOM / UI snapshots (if applicable)
- Prefer `data-testid` and the accessibility tree (`role`, `aria-label`) over generated CSS class
  names — they are far more stable for agent navigation.

---

## Hierarchy & scope

- The agent obeys the **closest** AGENTS.md to the file it edits; a human prompt overrides all of
  them.
- Monorepos: root file handles navigation and shared tooling; each package gets its own AGENTS.md
  for its stack and conventions. Keep each level scoped — don't overload any single file.

---

## Code intelligence (LSP) plugins — one proposal per stack (D42)

A language server gives the agent live diagnostics after each edit and navigation by symbol. `build`
proposes the stack's official plugin in its guides phase, as its own accept-or-decline item. The
plugin is installed by the user inside Claude Code (`/plugin install <plugin>@claude-plugins-official`);
`build` writes no file for it. A declined proposal is recorded under `not_installed` as
`lsp: "declined: <plugin>"`.

**Source.** Names come only from Claude Code's official documentation, read on 2026-10-29:

- `https://code.claude.com/docs/en/discover-plugins` ("Install and manage plugins"): gives the install
  syntax `/plugin install <plugin>@claude-plugins-official` and says Claude Code registers that
  marketplace on first interactive start. It names no LSP plugin itself.
- `https://code.claude.com/docs/en/plugins-reference` (served as "Plugin manifest reference"): defines
  `lspServers` / `.lsp.json` and says "For the language servers Anthropic publishes as plugins ...
  see Code intelligence". It names no plugin itself.
- `https://code.claude.com/docs/en/plugins/code-intelligence.md` ("Code intelligence plugins", the
  page the reference links to): the table below is copied from it. It says Anthropic maintains every
  plugin in its table except `liquid-lsp`, and that a plugin "doesn't include the language server":
  install the binary first, then the plugin.

| Stack | Official plugin | Language server binary to install first | Install the plugin |
| --- | --- | --- | --- |
| TypeScript, JavaScript | `typescript-lsp` | `typescript-language-server` (`npm install -g typescript-language-server typescript`, as the page says) | `/plugin install typescript-lsp@claude-plugins-official` |
| Python | `pyright-lsp` | `pyright-langserver` | `/plugin install pyright-lsp@claude-plugins-official` |
| Java | `jdtls-lsp` | `jdtls` | `/plugin install jdtls-lsp@claude-plugins-official` |
| Kotlin | `kotlin-lsp` | `kotlin-lsp` | `/plugin install kotlin-lsp@claude-plugins-official` |
| Go | `gopls-lsp` | `gopls` | `/plugin install gopls-lsp@claude-plugins-official` |
| Rust | `rust-analyzer-lsp` | `rust-analyzer` | `/plugin install rust-analyzer-lsp@claude-plugins-official` |
| .NET (C#) | `csharp-lsp` | `csharp-ls` | `/plugin install csharp-lsp@claude-plugins-official` |

For any other stack write "no official LSP plugin found (2026-10-29)" and do not propose a name. The
page also says how to connect a server that has no official plugin (an `.lsp.json` in a plugin of your
own); that is out of scope here. The binary install command for rows other than TypeScript is in the
plugin's README (linked from the page), not on the page: read it, do not guess it.

**Limits to state in the proposal.** The page says code intelligence plugins work in terminal sessions,
not in cloud sessions (Claude Code does not start plugin language servers there), and that the plugin
needs its binary on the `PATH` of the shell that starts `claude`. A monorepo with several stacks gets
one item per stack.
