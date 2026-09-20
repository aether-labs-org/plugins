# Harness Model — the 2x2 grid, the three categories, and Shift Quality Left

The **harness** is everything that shapes the agent's behaviour *except the model itself*: the
guides that steer it before it acts and the sensors that verify its work afterward. A good harness
makes the agent (a) get it right the first time and (b) self-correct when it drifts.

Based on Martin Fowler / Birgitta Böckeler, *Harness engineering for coding agent users*.

---

## The 2x2 grid

|                                                | **Computational** (deterministic, fast, runnable)                           | **Inferential** (semantic, LLM-readable, interpreted)            |
| ---------------------------------------------- | --------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| **Guide** (feedforward — steers before acting) | commands, file maps, schemas, codemods, language servers, bootstrap scripts | conventions, architecture intent, anti-patterns, how-to docs     |
| **Sensor** (feedback — verifies after acting)  | linters, type checkers, test runners, fitness tests + **expected output**   | code-review criteria, "definition of done", ADRs, manual testing |

- **Computational** = you can run it and get a binary pass/fail in milliseconds–seconds. Put the
  command and its **pass signal** in AGENTS.md.
- **Inferential** = it needs judgment. Put a one-liner and a `→ docs/X.md` pointer in AGENTS.md.

A sensor without a pass signal is useless — the agent will not know whether it passed. Always record
what success looks like (`Found 0 errors`, `N passed, 0 failed`, exit 0).

## The three harness categories

Every guide/sensor also belongs to a category (from *Estruturando Agentes*):

- **Maintainability harness** — keeps the code stable, refactorable, and clean over time
  (linters, formatters, complexity checks, code-review skills).
- **Architecture fitness harness** — keeps the codebase faithful to the intended design; stops
  architectural drift (ArchUnit, import-linter, dependency-cruiser, ADR review).
- **Behaviour harness** — confirms the product still does what it should (test suites, mutation
  testing, manual/E2E checks, security checks).

When proposing a harness, check all three categories — a repo with great tests but no
architecture-fitness will still rot structurally.

## Examples by category

| Category             | Computational sensor                            | Inferential sensor              |
| -------------------- | ----------------------------------------------- | ------------------------------- |
| Maintainability      | ESLint, ruff, Checkstyle, cyclomatic complexity | code-review agent, style guide  |
| Architecture fitness | ArchUnit, import-linter, dependency-cruiser     | architecture-review skill, ADRs |
| Behaviour            | unit/integration tests, mutation testing        | manual QA, acceptance criteria  |

## Harnessability (ambient affordances)

Not every codebase is equally governable. Structural properties determine how strong a harness can
be:

- **Strongly typed languages** make type-checking a powerful sensor.
- **Clear module boundaries** afford architecture-fitness rules.
- **Opinionated frameworks** (Spring, Django) reduce agent freedom → higher first-try success.
- **Legacy / high-debt systems** are hardest to harness; scope sensors to changed files first.

Assess harnessability before choosing how aggressive the gates should be (see
`reasoning-framework.md` Step 1).

---

## Shift Quality Left

**Principle:** push quality gates as early as possible — and run them at *every step*, not only at
the end / in CI. Quality "shifts left" when the agent treats compiler errors, type errors, and test
failures as **design signals at the moment of writing**, rather than obstacles to work around later.

**Why it matters for agents:** AI agents reliably produce *functionally correct* code that quietly
introduces technical debt — duplicating existing functionality, working around the type system
(empty strings instead of optionals), adding unjustified complexity, ignoring repo conventions
(Doernenburg/Fowler, *Assessing internal quality while coding with an agent*). These defects are
invisible to "does it run?" checks and only surface as architectural decay much later. Running gates
late lets the debt pile up; running them per step catches it while it is cheap to fix.

**How AGENTS.md materializes it** — instruct the loop, not just list commands:

```
generate a small block
  → run the fast sensors (compile/typecheck → lint → affected tests)
  → if a sensor fails, fix at the first signal before continuing
  → only then move to the next block
run the slow gates (full suite + architecture-fitness) before declaring "done"
```

**Per-step vs end-of-run** (decide in `reasoning-framework.md` Step 5):

| Run at every step (fast, localized) | Run at the end (slow, global)         |
| ----------------------------------- | ------------------------------------- |
| compile / type check                | full test suite                       |
| lint / format                       | architecture-fitness suite            |
| affected unit tests                 | mutation testing, E2E, security scans |

This pairs feedforward **guides** (prevent the mistake) with fast **sensors** (catch it immediately),
which is exactly what keeps agent-written code from collapsing under its own volume over time.
