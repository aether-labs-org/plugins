# Catalog - Documentation and decisions

The agent guides, the topic files and architecture decision records. `kh check` reports drift; ADRs are immutable once accepted.

Each topic is a section with the same six labels: **Questions** (what to ask), **Measure** (how to read the as-is state), **Default** (how the proposal is derived), **Why** (the reason and its source), **Class and gate** (what enforces it and where), **Opinion** (where the default is judgement). Brownfield: derive the default from the measured distribution (the next round number at or above p90 and not below p75) and say so; greenfield: use the catalog default and say so. The tools per stack are in `stack-typescript.md`, `stack-python.md` and `stack-jvm.md`, one row per topic id. After setup the project's `.agents/keel.yml` is the truth, not this catalog.

## agents-md

**Questions**: What does an agent need that it cannot discover from the code (commands it cannot guess, non-standard conventions)?
**Measure**: `kh check` reports `agents-size` (over 100 lines), `agents-not-loaded` and `stale-command`.
**Default**: An index of at most 100 lines carrying only what the agent cannot discover: setup, commands, working rules, boundaries, "before you finish", pointers. Every line is confirmed by the human.
**Why**: Gloaguen et al. found that generated context files can lower success and raise cost, while tool instructions and non-standard conventions are followed and repository overviews do not help (https://arxiv.org/abs/2602.11988). `AGENTS.md` is the shared format (https://agents.md/).
**Class and gate**: none (guide); `kh check` for size and stale commands
**Opinion**: Every line: the default is to leave it out.

## topic-files

**Questions**: Which rules need more than one line (architecture, conventions, testing)? Are they linked from `AGENTS.md`?
**Measure**: `kh check` reports `dangling-pointer` and `guide-unlisted`.
**Default**: One file per topic under `docs/`, each rule a section with the rule, why, an example and what to do when it fails; every topic file listed in `guides:` so it is protected.
**Why**: Small files read on demand keep the always-loaded index short; the section anchor is a stable target for pointers. Listing the file in `guides:` makes a silent edit impossible.
**Class and gate**: none (guide); `kh check`
**Opinion**: How to split topics.

## adr

**Questions**: Which decisions need a record (a trade-off between options, a rule that breaks, a recommendation the user overrides)?
**Measure**: `kh guard` reports edits to accepted ADRs and loosenings with no ADR naming them.
**Default**: MADR files in `adr_dir`, numbered; accepted ADRs are never edited, a new ADR supersedes and only the old status line changes; an ADR that loosens the harness names `.agents/keel.yml#<script>` or the file.
**Why**: MADR is a lean, widely used format (https://adr.github.io/madr/). Immutability keeps the record trustworthy; naming the loosened script ties the decision to the change.
**Class and gate**: security; every gate through `guard`
**Opinion**: What is worth an ADR.
