# Catalog - Security

Secrets, known-vulnerable dependencies and static analysis. Security scripts have class `security`: they never take a baseline, and a skipped one fails the gate.

Each topic is a section with the same six labels: **Questions** (what to ask), **Measure** (how to read the as-is state), **Default** (how the proposal is derived), **Why** (the reason and its source), **Class and gate** (what enforces it and where), **Opinion** (where the default is judgement). Brownfield: derive the default from the measured distribution (the next round number at or above p90 and not below p75) and say so; greenfield: use the catalog default and say so. The tools per stack are in `stack-typescript.md`, `stack-python.md` and `stack-jvm.md`, one row per topic id. After setup the project's `.agents/bmax.yml` is the truth, not this catalog.

## secrets

**Questions**: Is a secret scanner already part of the workflow? Are there fake keys in fixtures that need an allow-list?
**Measure**: Run the scanner once over the working tree and count leaks.
**Default**: gitleaks over the working tree in the fast and commit gates; `--redact` so the report holds no secret; `.gitleaks.toml` (from `templates/gitleaks.toml.tmpl`) extends the default rules and allow-lists the repository's git-ignored directories.
**Why**: A secret in the repository is a leak the moment it is pushed; scanning before the commit is the cheap place to stop it (https://github.com/gitleaks/gitleaks). `requires:` makes a missing scanner a `skip`, and a skipped security script fails the gate. Pitfall seen in a real run (gitleaks 8.30.1): `gitleaks detect --no-git` and `gitleaks dir` scan every file under the path, git-ignored ones included, and have no option to honour `.gitignore`; ten false positives came from test fixtures inside local worktrees under `.claude/worktrees/`. Remedy: the `ignored-dir` lines of `discover.sh` become one `[[allowlists]]` path regex each in `.gitleaks.toml` (verified: a fake secret in an allow-listed ignored directory is not reported, the same secret in a tracked file is). `[extend] useDefault = true` is required: without it the default rules are dropped and the scan reports nothing. The script lists the file in `config:`, so editing the allowlist later is a loosening that needs an ADR.
**Class and gate**: security; fast and commit gates; format sarif; no baseline
**Opinion**: Which paths are allow-listed (ignored directories only; never a directory that holds tracked files).

## sca

**Questions**: Which ecosystems have manifests or lockfiles? Is a vulnerability scanner already in CI?
**Measure**: Run the scanner once and count advisories by severity.
**Default**: osv-scanner over the lockfiles, in the slow gate (it queries the OSV database; use its offline mode with a downloaded database if the gate must not use the network).
**Why**: OSV aggregates advisories across ecosystems (https://osv.dev/); osv-scanner reads lockfiles and emits SARIF (https://google.github.io/osv-scanner/). The network exception is why it is a slow-gate script.
**Class and gate**: security; slow gate; format sarif; no baseline
**Opinion**: The severity that blocks, and how long a known advisory may be accepted (use `exceptions:` with a deadline).

## sast

**Questions**: Is a static analyser already part of the build? Are there frameworks with known sink patterns?
**Measure**: Run the analyser with a committed rules file and count findings.
**Default**: semgrep with a committed rules file in the slow gate (`--metrics=off`, no login); extend the file with the project's own sinks.
**Why**: Semgrep rules are code patterns checked offline (https://semgrep.dev/docs/); `--config auto` needs the network and a login, so commit the rules instead. SpotBugs is the JVM-native alternative (https://spotbugs.github.io/).
**Class and gate**: security; slow gate; format sarif; no baseline
**Opinion**: Which rule packs and which severities block.
