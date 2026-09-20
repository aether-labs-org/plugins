# AGENTS.md template (100 lines)

Fill the template below. Replace `{{...}}` with **real, confirmed** values from the stack profile
and repo discovery. Omit any section for which you found nothing — blank sections waste context
budget. Use `→ docs/X.md` for anything needing more than one sentence. Keep the whole file to
100 lines.

---

```markdown
# AGENTS.md — {{project-name}}
> Map/index for AI coding agents. Source of truth: `docs/`. Stack: {{stack}}. Last updated: {{YYYY-MM-DD}}.

## Project Identity
- **Stack**: {{primary language/runtime, major frameworks}}
- **Package manager / build**: {{pnpm | Maven | uv | go | cargo | dotnet ...}}
- **Entry points**: {{main files / services / packages}}
- **Key constraint**: {{one-line critical rule, e.g. "no direct DB calls outside the repository layer"}}

---

## Computational Guides — feedforward you can rely on

### Build & run
```bash
{{build command}}   # → {{output / artifact path}}
{{run command}}     # → {{e.g. http://localhost:PORT}}
```

### File map
| Path       | Purpose              |
| ---------- | -------------------- |
| `{{path}}` | {{one-line purpose}} |
| `{{path}}` | {{one-line purpose}} |

### Schemas & contracts
- API spec: `{{path/to/openapi.yaml}}` or → `docs/api.md`
- DB schema: `{{path/to/schema.sql}}` or → `docs/data-model.md`
- Config: `{{path/to/.env.example}}`

---

## Inferential Guides — read before coding (one-liners only; details in docs/)
- **Architecture**: {{one sentence on the main pattern}} → `docs/architecture.md`
- **Conventions**: {{one sentence on the key coding rule}} → `docs/conventions.md`
- **Anti-patterns**: {{one thing NOT to do}} → `docs/conventions.md#anti-patterns`
- **Domain glossary**: → `docs/glossary.md`

---

## Computational Sensors — run these to verify your work
Each sensor has a command and the signal to look for in its output.

| Sensor               | Command                    | Pass signal                    |
| -------------------- | -------------------------- | ------------------------------ |
| Type check           | `{{typecheck command}}`    | `{{e.g. Found 0 errors}}`      |
| Lint                 | `{{lint command}}`         | `{{exit 0, no output}}`        |
| Format               | `{{format check command}}` | `{{all matched}}`              |
| Tests                | `{{test command}}`         | `{{N passed, 0 failed}}`       |
| Architecture fitness | `{{fitness command}}`      | `{{BUILD/tests pass}}`         |
| Build                | `{{build command}}`        | `{{Build succeeded / exit 0}}` |

### Reading sensor output
- **Test failures**: first `FAIL`/`Error` line is the root; below it is cascade — fix top-down.
- **Lint errors**: `{{file:line:col rule}}` — jump directly to that location.
- **Type errors**: the first error in a chain is the real mismatch; the rest are consequences.
- {{stack-specific tip from the profile, e.g. JUnit stacktrace / clippy note}}

---

## Quality Gates — Shift Quality Left
Run gates **early and at every step**, not only at the end. Treat failures as design signals.

**Per step** (after each small block, fast):
```bash
{{typecheck command}} && {{lint command}} && {{affected-tests command}}
```
**Before declaring done** (slower, global):
```bash
{{full test suite}} && {{architecture-fitness command}}
```
Loop: generate a block → run per-step gates → fix at the first signal → only then continue.

---

## Inferential Sensors — signals that need interpretation
- **PR checklist**: → `docs/contributing.md#pr-checklist`
- **Definition of done**: → `docs/definition-of-done.md`
- **Architecture fitness review**: → `docs/adr/` (read the latest 3 ADRs before proposing new patterns)

---

## Context Engineering Notes
- **Log format**: `{{timestamp}} [{{level}}] {{service}} — {{message}}`; ignore `DEBUG` unless tracing {{subsystem}}.
- **Root cause**: search backward from the first `ERROR` for the originating `WARN`.
- **Metrics**: key metric `{{name}}`, alert at `{{threshold}}` → `docs/observability.md`
- {{UI tip if applicable: prefer data-testid / accessibility tree over CSS classes}}

---

## Docs Index
| Topic                   | File                    |
| ----------------------- | ----------------------- |
| Architecture            | `docs/architecture.md`  |
| Coding conventions      | `docs/conventions.md`   |
| API reference           | `docs/api.md`           |
| Data model              | `docs/data-model.md`    |
| Contributing / PR guide | `docs/contributing.md`  |
| Observability           | `docs/observability.md` |
| ADRs                    | `docs/adr/`             |
| Glossary                | `docs/glossary.md`      |
```
