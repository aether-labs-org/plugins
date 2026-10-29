# keel-harness v0.3 — F3c-2 Mandatory rules (D43): Implementation Plan

> **For agentic workers:** read `docs/plans/2026-10-29-keel-harness-v0.3-agent-rules.md` first. Phase id: `f3c2`. Free; no eval. Starts after F3c-1, F2d and F3b are merged. F3d-1 and F6 run in parallel with you. Add your `harness-check` checks as new functions placed just before `# --- review-due`, and their calls just before `check_review_due`.

**Goal:** spec D43, §2.3 and §5.3. Non-negotiable rules are a property of the rule, `ENFORCEMENT_LEVEL=mandatory`, enforced by sensors. There is no `constitution.md`.

## The behaviour

1. **`ENFORCEMENT_LEVEL=mandatory|ratchet`** in every rule env file; default `ratchet` when absent. Document it in `contracts/rule-env.md`. It is distinct from the existing `ENFORCEMENT=` key, which names the sensor or `inferential`; keep both.
2. **A mandatory rule needs a computational sensor.**
   - New `harness-check` check `mandatory-unsensored`: `ENFORCEMENT_LEVEL=mandatory` with `ENFORCEMENT=inferential`, or naming a sensor file that does not exist under `scripts/sensors/`.
3. **Legacy violations of a mandatory rule exist only as an exception list with deadlines that can only shrink.**
   - `EXCEPTIONS` is a multi-line quoted value, one `<path> <YYYY-MM-DD>` per line. A mandatory rule has **no TSV baseline**.
   - The rule's sensor skips listed paths until their deadline, then fails them. Implement it in the rule sensors that support baselines (`file-size`, `folder-layout`, `test-presence`, `code-language`, `architecture-grep`), through a shared helper in `assets/core/lib/baseline.sh`.
   - New `harness-check` check `exception-expired`: an exception past its date.
4. **`guard` rejects any loosening of a mandatory rule, even with an ADR naming the file**, except a **superseding** ADR. That is an ADR added in the change that names the file and has a line `Supersedes: <adr path>` pointing at an existing ADR in `adr_dir`. The approval itself comes from CODEOWNERS plus branch protection; document that keel cannot check it locally. Loosening, for a mandatory rule, means:
   - everything that is loosening today;
   - any `EXCEPTIONS` line added, or any deadline moved later;
   - a TSV baseline appearing for it;
   - `ENFORCEMENT_LEVEL` going `mandatory` → `ratchet`, or the key being deleted.

   The guidance names the superseding-ADR route.
5. **Protected paths:** a mandatory rule's env file is covered by the `harness` category from F3c-1. Check it, and add a test that the protect hook denies editing one.
6. **CI:** the `keel` workflow already runs the gate. `skills/build/references/enforcement.md` tells the user to make the `keel` check required when any rule is mandatory.
7. **`AGENTS.md` lists mandatory rules first,** in a `## Rules` section, before the ratchet rules. Update `skills/rules/references/nested-agents-md-template.md`, the root template's rules part and `rules`' write phase.
8. **Spec Kit.** When `.specify/memory/constitution.md` exists, `rules` reads it in the inventory phase and links each principle:
   - to a rule (its `DOC`), or
   - to a line in `docs/architecture.md` `## Principles` with `→ review:<owner>`, when no sensor can check it.

   `rules` never writes a `constitution.md`.

## Tasks

- [ ] **Task 1 — tests first** for behaviours 2–5:
  - in `tests/keel_guard_test.sh`: mandatory loosening fails even with an ADR; passes with a superseding ADR; `EXCEPTIONS` growth fails; a later deadline fails; mandatory → ratchet fails;
  - in `tests/keel_rule_sensors_test.sh`: an exception before its deadline is skipped, after it fails;
  - in `tests/keel_harness_check_test.sh`: `mandatory-unsensored` and `exception-expired`, warn and clean;
  - in `tests/keel_protect_test.sh`: a mandatory env file is denied.
- [ ] **Task 2 — implementation** in `guard.sh`, `lib/baseline.sh`, the five rule sensors and `harness-check.sh`. Keep the repo-specific markers intact, and keep the sensor contract. Commit `feat(keel-harness): mandatory rules - exceptions only shrink, guard needs a superseding ADR (D43)`.
- [ ] **Task 3 — skills and contracts:**
  - `contracts/rule-env.md`;
  - `rules` (proposals ask "mandatory or ratchet?" with the trade-off; mandatory first in `AGENTS.md`; Spec Kit reading);
  - `skills/rules/references/adr-template.md` (the `Supersedes:` line);
  - `enforcement.md` (required check);
  - the checks table and its count.

  Commit `feat(keel-harness): rules proposes mandatory or ratchet; reads a Spec Kit constitution (D43)`.
- [ ] **Task 4 — master plan:** tick the F3c `mandatory` items and the D43 items moved from F2c. Mark F3c ✅. Commit `docs(keel-harness): F3c done`.

## Acceptance

- Every behaviour above has a red-then-green test.
- `guard` output for a blocked mandatory loosening names the superseding-ADR route.
- `rules` never writes `constitution.md`; `AGENTS.md` puts mandatory rules first.
- `./tests/run.sh` exits 0; `validate --strict` passes; `shellcheck` is clean; the size limits hold.
