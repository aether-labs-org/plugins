# keel-harness v0.3 — rules for every agent executing a phase plan

Read this file, then the phase plan, then the spec sections that plan cites
(`docs/specs/2026-10-23-keel-harness-v0.3-design.md`). Where a phase plan contradicts this file, this
file wins; stop and report the contradiction.

## Git

1. `git fetch origin claude/harness-engineering-autonomous-agents-d8xhvx`.
2. Create `feat/keel-harness-v0.3-<phase>` from `origin/claude/harness-engineering-autonomous-agents-d8xhvx`
   (not from your worktree's HEAD) and push it with `-u`.
3. One commit per task, with a conventional message (`feat(keel-harness): …`, `test(keel-harness): …`,
   `docs(keel-harness): …`), pushed after each commit. Never force-push, never rewrite history, never
   push to any other branch, never open a pull request.
4. End every commit message with the two attribution lines given in your task prompt, and never put a
   model name in a commit, a file or a comment.

## Code

- Everything copied into a target repository (`assets/`) is bash 3.2 or plain YAML/Markdown: no `jq`, no
  network, no model call, no `${CLAUDE_*}` variable, no path into the plugin. It must run with the
  plugin absent. Exception: only where a phase plan explicitly allows it (F5's reviewer sensor).
- Code that runs from the plugin (`scripts/`) is bash 3.2, no `jq`, no network.
- Match the surrounding code: the `# Managed by keel-harness` header, the
  `# --- keel:repo-specific begin/end ---` markers, the sensor contract (line 1
  `id<TAB>class<TAB>status<TAB>summary`, exit 0 pass / 1 fail / 2 skip, `  guidance:` on fail), the test
  helpers in `tests/keel_helpers.sh` (`check`, `new_repo`, `install_asset`, `finish`).
- Every new behaviour gets a test in `tests/` that fails before the change and passes after it. Run the
  new test against the old code once and say in the report that it failed.
- `build/SKILL.md` and every other SKILL.md stay within their tested limits (`tests/build_test.sh`
  line counts; 20,000 bytes once F2c adds the size test). Move detail into `references/` or
  `contracts/` rather than over-running a limit.
- Never skip, disable or weaken an existing test to get green. If an existing test encodes behaviour
  the plan changes, update that test in the same commit and say so in the report.

## Checks before every commit

```bash
./tests/run.sh            # exit 0, no FAIL line
claude plugin validate ./plugins/keel-harness --strict   # if `claude` is installed
shellcheck -S warning <every .sh you changed>             # if shellcheck is installed
```

`shellcheck` is available at `/tmp/claude-0/-home-user-plugins/b93abfbe-dfde-55b9-b964-b0d0cf65ad10/scratchpad/scbin/shellcheck`
in the owner's cloud session; put that directory first on `PATH` if `command -v shellcheck` fails.
Report the final `ok` count (`./tests/run.sh | grep -c '  ok'`).

## Never

- Never run `claude plugin eval` or any other paid command. Eval cases may be written and edited; they
  are run later by the owner.
- Never weaken a sandbox, never use `sudo`, never work around a permission denial: stop and report it.
- Never delete files outside your worktree. Never write outside your worktree except temporary
  directories you create with `mktemp -d` and remove.

## Report (your final message)

1. Branch name and commit hashes, one line each.
2. `./tests/run.sh` `ok` count before and after, and the new tests' red-then-green evidence.
3. Each acceptance criterion of the plan: met / not met, with the command that shows it.
4. Every deviation from the plan, and every decision you had to make that the plan did not cover.
5. Anything you found that looks wrong but was outside your scope.
