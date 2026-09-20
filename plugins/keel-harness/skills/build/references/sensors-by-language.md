# Sensors by language — what to propose, per ecosystem

The fast gate answers four questions: does it typecheck, is it styled, do the affected tests pass,
and did a credential leak. This file says which **tool** answers each question in each ecosystem,
and what the wrapper around it has to know.

> **What is actionable today.** Only the **TypeScript / Node** row is implemented end to end: the
> wrappers, the ratchet and the eval fixture all exist and are exercised. The other five rows —
> Next.js / React, Python, Go, Java, Terraform — are **documentation only** until the second plan
> implements them. Do not install a gate for those stacks from this file alone: propose what is
> here, say plainly that the wrappers for that stack are not written yet, and stop at the layers
> that are (`bootstrap`, `guides`).

---

## The table

| Language | Types | Style | Affected tests | Secrets |
| --- | --- | --- | --- | --- |
| **TypeScript / Node** | `tsc` strict | ESLint or Biome | Vitest or Jest | GitLeaks |
| Next.js / React | `tsc` strict | ESLint | Vitest or Jest | GitLeaks |
| Python | mypy | ruff | pytest | GitLeaks |
| Go | `go vet` | staticcheck | `go test` | GitLeaks |
| Java | compiler | Checkstyle | JUnit | GitLeaks |
| Terraform | `validate` | `fmt -check`, tflint | — *no unit tests* | GitLeaks |

**The table names tools, never commands.** The exact command comes from discovery in the
repository — the "never invent commands" rule. Writing `npx vitest related` here would be inventing
the invocation of a project nobody has looked at yet; the same tool is invoked through `npm`, `pnpm`,
`yarn`, a `Makefile` target or a bare binary depending on the repo, and only the repo can say which.

Two consequences of the six-language choice, both of which are the design working rather than gaps
to patch:

- **Terraform has no test sensor**, so its fast gate has **three sensors, not four**. There is no
  unit-test layer to run; do not substitute `plan` for one, which touches state and a provider.
- **In Java, compilation usually exceeds the seconds ceiling.** When it does, the ceiling rule fires
  and the compile sensor **stays out of the fast gate** — named in the proposal as left out, with the
  measured seconds and the ceiling as the reason. That is the ceiling rule doing its job, not an
  exception to it.

---

## Precedence — what wins when sources disagree

1. **Real configs in the target repo** — `eslint.config.js`, `tsconfig.json`, `pom.xml`, `ruff.toml`,
   `.golangci.yml`, the `Makefile`, `.github/workflows/*.yml`. These are the source of truth and
   always win.
2. **A company override** — `.agents/profiles/<stack>.md` in the target repo, if present. It replaces
   the recommendation below for that stack wholesale, which is how Bazel, an in-house linter or a
   custom gate gets encoded without editing this kit.
3. **This file's recommendation** — the default proposed when neither of the above exists.
4. **Unknown stack** — derive the harness only from what the repo exposes: `Makefile`, CI workflows,
   package-manager scripts, the README's "Getting started". Never invent a command.

---

## Per-ecosystem notes

Each note gives the pass signal to quote in `AGENTS.md`, the error format the wrapper parses, and
the blind spots worth naming in the guidance text.

### TypeScript / Node — *actionable*

- **Types.** `tsc --noEmit` against the project's own `tsconfig.json`. Pass signal: `Found 0 errors`.
  Error format: `path(line,col): error TSxxxx: msg`. **The first `tsc` error is the real root** of
  the chain; the rest usually cascade from it, so guidance says to fix the first and re-run.
- **Style.** ESLint (or Biome where the repo uses it). Error format:
  `file:line:col  error  msg  rule-name` — the rule name is what to cite. `heuristic` class, so it
  gets the ratchet and a `review_by`.
- **Affected tests.** Vitest (`related --run <files>`) or Jest (`--findRelatedTests`). Scoped by
  `SCOPE`; with no changed files it runs the whole suite. `correctness` class — never ratcheted.
- **Secrets.** GitLeaks over the changed files. `security` class: no snapshot, no threshold,
  fails on the first finding. If GitLeaks is not installed, the wrapper **skips** (exit 2) and says
  so — a secret sensor that silently passes is worse than none.
- **Blind spots for guidance:** widening a type to `any` instead of modelling absence with
  `undefined` or a union; encoding "missing" as `""` or `-1`; reaching across layers directly.
- **Architecture fitness (out of the v0.1 fast gate):** `dependency-cruiser`, or
  `eslint-plugin-boundaries`, or Nx module boundaries. Pass signal: `no dependency violations found`.

### Next.js / React — *documentation only*

Same four tools as TypeScript, plus the framework's own lint config, which usually already wraps
ESLint — discover it rather than adding a second linter beside it. Server/client component boundary
violations surface through the framework build, which is normally too slow for the fast gate; when
it is, the ceiling rule applies as it does for Java.

### Python — *documentation only*

- **Types:** mypy. Pass signal: `Success: no issues found in N source files`.
- **Style:** ruff. Format: `path:line:col: CODE msg`; many codes are auto-fixable with `--fix`.
- **Tests:** pytest. The **first** `FAIL` is the root — later ones often cascade from a fixture.
- **Blind spots:** annotate public functions; avoid `Any`; use `Optional` / `| None` rather than
  sentinel values; keep the layering (in a hexagonal layout the domain does not import infra).
- **Architecture fitness:** `import-linter`, driven by an `.importlinter` contract file. Pass signal:
  `Contracts: N kept, 0 broken`.

### Go — *documentation only*

- **Types:** `go vet` (the compiler already rejects most of what a typechecker would catch).
- **Style:** staticcheck, or golangci-lint where the repo already configures it. Format:
  `path:line:col: msg (linter-name)` — the linter name says which rule fired.
- **Tests:** `go test` over the packages containing the changed files.
- **Blind spots:** handle every error explicitly and wrap it (`fmt.Errorf("...: %w", err)`); never
  discard `err`; accept interfaces, return structs; do not add a framework where stdlib suffices.
- **Architecture fitness:** golangci-lint with `depguard` (bans forbidden imports), or
  `go-arch-lint`. `internal/` already enforces one boundary at compile time.

### Java — *documentation only*

- **Types:** the compiler itself. **Usually over the ceiling** — see the consequence above; when the
  measured compile exceeds `gate.fast.ceiling_seconds`, it is not installed in the fast gate and the
  proposal says which sensor was left out, its measured seconds, and the ceiling it blew.
- **Style:** Checkstyle. **Tests:** JUnit, scoped to the affected modules.
- **Reading a failure:** in a JUnit stack trace, go to the **first frame belonging to the project**
  and skip the framework frames above it.
- **Blind spots:** do not return `null` from a public API — use `Optional<T>`; constructor injection
  rather than field injection; thin controllers.
- **Architecture fitness:** ArchUnit tests run by the normal test goal; alternatives are Maven
  Enforcer and Spring Modulith.

### Terraform — *documentation only*

- **Types:** `terraform validate`. **Style:** `terraform fmt -check` plus tflint.
- **Tests:** none — three sensors, as stated above.
- **Secrets:** GitLeaks matters more here than anywhere else, since credentials in `.tfvars` and
  provider blocks are the common leak.
- **Blind spot:** never run anything that touches remote state or a provider inside the fast gate.

### An unknown stack

Derive everything from what the repo exposes and propose only what was found. If the ecosystem has
an obvious fitness tool, name it as a suggestion; if it does not, say the axis is uncovered rather
than inventing a check. Languages outside these six (Rust, .NET and the rest) fall here in v0.1 —
this kit has no wrappers for them.

---

## Monorepos

Detect every stack present (e.g. TypeScript plus Go). Apply the matching row per stack. The root
`AGENTS.md` carries navigation and shared tooling; each package with a different stack gets its own
nested `AGENTS.md`. The rule is: **the file closest to the edited file wins.** One gate can still
cover them all if each sensor is scoped by `SCOPE` to the files that changed.
