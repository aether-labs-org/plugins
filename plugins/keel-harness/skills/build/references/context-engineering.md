# Context Engineering — keep AGENTS.md a lean, agent-readable index

Context Engineering is about *how* you hand context to the agent so it succeeds. The model has a
finite context window, and frontier models reliably follow only ~150–200 instructions. Giant generic
manuals become "non-guidance": the agent drowns in secondary rules and loses the real goal. Worse,
large instruction files rot — humans stop maintaining what can't be mechanically verified.

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
irrelevant rules, leaving less for the actual task. Target ~100 lines; hard cap ~120. If it grows,
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
