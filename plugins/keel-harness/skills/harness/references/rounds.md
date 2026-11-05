# Rounds, the proposal block and the write order

## The rounds

- At most **4 questions** per round. Use the question tool when one is available: the recommended option first, each option with
  its trade-off, plus a free answer. Where there is no question tool, ask in plain text and wait.
- Every proposal carries its **measured evidence** ("p90 file size is 240 lines", "domain never imports adapters") and a **cited
  source** from the catalog. "Not measured" is an acceptable evidence line; a guess is not.
- Brownfield: derive each default from the measured distribution (the next round number at or above p90 and not below p75) and
  say so. Greenfield: use the catalog default and say so. Breaking changes are allowed when justified by data and a cited source,
  and each is named as breaking.
- Low confidence becomes a narrow question; no confidence means the layer is not installed and the reason is said (see the
  [rubric](rubric.md)). Never an open question where an inference to confirm will do.
- The user chooses the tool. Offer the recommended one and its alternatives from the stack profile and accept any tool that emits
  a supported format, or only an exit code. After setup `.agents/keel.yml` is the truth, not the catalog.
- A catalog row whose Fixture says `unverified` is proposed with that sentence: "no recorded output of this tool; kh parses its
  format but this exact command was not verified".

## Areas the rounds cover

Gates and scripts per stack; rules (architecture, layout, size, language, standards); testing strategy (unit, integration,
contract, e2e, property, regression, mutation, coverage, performance); security (secrets, SCA, SAST); observability; memory; the
Git cycle (commit and branch conventions, PR template, scope, merge check); review; the agents in use; the git-hook mode. Ask only
what the repository leaves open. The topics and their defaults are in the catalog:
[tests](catalog-tests.md), [code](catalog-code.md), [architecture](catalog-architecture.md), [security](catalog-security.md),
[observability](catalog-observability.md), [git](catalog-git.md), [docs](catalog-docs.md); the tools per stack in
[typescript](stack-typescript.md), [python](stack-python.md) and [jvm](stack-jvm.md).

## ADRs

Write an ADR (from `templates/adr.md`) when a round had a real trade-off, when a rule is breaking, or when the user overrides your
recommendation. The first one, `templates/adr-0001.md`, records the context answers. An accepted ADR is never edited; a new one
supersedes it and only the old status line changes. A change that loosens the harness is released by an ADR that names
`.agents/keel.yml#<script-id>` or the file; naming the whole `keel.yml` releases nothing.

## The single proposal block

After the rounds, show one block listing every file you will write or change, one line of reason each, in the write order below,
and wait for the answer. Nothing is written before it.

## Write order

Each write is a separate Write/Edit that the human confirms:

1. the wrapper and the lock: `.agents/bin/kh` from `kh/bin/kh` and `.agents/keel.lock` from `kh/keel.lock` of this plugin
   (copy the lock exactly; never bump the pin silently);
2. `.agents/keel.yml` from the stack template, adapted: [typescript](../templates/keel-typescript.yml),
   [python](../templates/keel-python.yml), [jvm](../templates/keel-jvm.yml) (quote any `run:` that contains `{report}` inside a
   flow mapping, or use the block form);
3. native tool configs the scripts need (the architecture tool configuration, the linter configuration), from
   `templates/architecture/` (`dependency-cruiser-<style>.cjs`, `import-linter-<style>.toml`, `archunit-<style>.java` for the styles
   `hexagonal`, `layered`, `clean`, `modular`), each placeholder replaced with the real path or package, and named in the owning
   script's `config:` so a later change is a loosening; with the secrets script also `.gitleaks.toml` from
   `templates/gitleaks.toml.tmpl`: gitleaks scans git-ignored files too and cannot read `.gitignore`, so write one allowlist entry
   per `ignored-dir` line of `discover.sh` (escape dots; skip any directory that holds tracked files) and keep
   `[extend] useDefault = true`, without which the scan finds nothing; record the allowlist in the install ADR;
4. baselines, from the output of `kh measure <script>` (a baseline is a ratchet: only heuristic scripts take one);
5. guides: `AGENTS.md` (`templates/AGENTS.md.tmpl`), `CLAUDE.md` (`templates/CLAUDE.md.tmpl`, exactly `@AGENTS.md`), topic files, nested
   `AGENTS.md` where a rule applies to one directory (`templates/nested-AGENTS.md`), every one listed in `guides:`;
6. ADRs (`templates/adr-0001.md`, `templates/adr.md`);
7. the review: `docs/review.md` (`templates/review.md`), `.claude/agents/keel-reviewer.md` (`templates/keel-reviewer.claude.md`),
   `.github/agents/keel-reviewer.agent.md` (`templates/keel-reviewer.agent.md`);
8. the PR template if adopted: `.github/pull_request_template.md` (`templates/pull_request_template.md`);
9. memory scaffolding when the user wants it: `.agents/progress.md` (`templates/progress.md`), `.agents/lessons.md`
   (`templates/lessons.md`), a first plan from `templates/plan.md` only for real work;
10. git hooks: `.agents/githooks/pre-commit`, `.agents/githooks/commit-msg`, `.agents/githooks/pre-push` from
    `templates/githooks/pre-commit`, `templates/githooks/commit-msg`, `templates/githooks/pre-push` (native mode), or the hook
    manager's config calling `sh .agents/bin/kh` (external mode). The Write tool creates the hook files without the exec bit and
    the hook of this skill denies `chmod`, by design: **never chmod the hooks**. `sh .agents/bin/kh setup` makes them executable
    and sets `core.hooksPath`, so the final report asks the human to run it once (it is also the per-clone step);
11. `.gitignore` additions from `templates/gitignore.txt` (`.agents/run/`). Check the `ignored` lines of `discover.sh` first. When
    an existing rule ignores `.claude/settings.json` or `.claude/agents/` (typically `.claude/`), propose replacing that one rule
    with `.claude/*`, `!.claude/settings.json` and `!.claude/agents/`: everything else under `.claude/` (skills, worktrees,
    local settings) stays ignored. Never replace a broad ignore rule with narrower lines unless you list every path that would
    become visible (`git status` shows them as untracked, and `git add -A` would commit them) and ask about each;
12. `.claude/settings.json` from `templates/settings.json` **last**: once it exists the repository hook also guards the rest of
    the session, and both hooks may prompt for one write (the setup-session hook of this skill and the repository's).

If a file already exists, show the difference and ask; merge, never overwrite. `AGENTS.md` carries only what the agent cannot
discover, every line confirmed (see [agents](agents.md)).
