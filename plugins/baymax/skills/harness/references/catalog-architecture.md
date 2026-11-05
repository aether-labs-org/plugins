# Catalog - Architecture

Layering and dependency rules, new dependencies, where files live, and golden samples. Architecture rules run the repository's native tool; its configuration is protected with `config:`.

Each topic is a section with the same six labels: **Questions** (what to ask), **Measure** (how to read the as-is state), **Default** (how the proposal is derived), **Why** (the reason and its source), **Class and gate** (what enforces it and where), **Opinion** (where the default is judgement). Brownfield: derive the default from the measured distribution (the next round number at or above p90 and not below p75) and say so; greenfield: use the catalog default and say so. The tools per stack are in `stack-typescript.md`, `stack-python.md` and `stack-jvm.md`, one row per topic id. After setup the project's `.agents/bmax.yml` is the truth, not this catalog.

## architecture

**Questions**: Is there a layering you intend (hexagonal, layered, clean, modular)? Which packages are the domain? Which framework imports must stay out of it?
**Measure**: `scripts/measure.sh imports <java|kotlin|python|ts> <prefix>` gives the real dependency matrix; `scripts/measure.sh framework-imports <path>` counts framework imports inside the domain.
**Default**: Brownfield: the dependency direction the matrix already shows, with violations frozen in the tool's own baseline. Greenfield: the style's template map (`templates/architecture/`).
**Why**: ArchUnit's `onionArchitecture()` is also known as hexagonal architecture, and `FreezingArchRule` records existing violations and reports only new ones (https://www.archunit.org/userguide/html/000_Index.html). dependency-cruiser has `depcruise-baseline` with `--ignore-known` (https://github.com/sverweij/dependency-cruiser). import-linter has `ignore_imports` (https://import-linter.readthedocs.io/). An ArchUnit release older than the project's JDK imports no class and every rule passes without checking anything (seen with ArchUnit 1.3.0 on Java 25 bytecode): keep the `classes_are_analysed` guard rule of the template.
**Class and gate**: correctness; fast or slow gate by cost; format errorformat (dependency-cruiser, import-linter) or junit (ArchUnit); native baseline, never a TSV baseline
**Opinion**: The style. The maps: hexagonal adapters -> application -> domain; layered web -> service -> repository; clean frameworks -> adapters -> use cases -> entities; modular one slice per module through its public API. Each of the 12 files in `templates/architecture/` was run once with the real tool (dependency-cruiser 17.4.3 with TypeScript 5.9.3, import-linter 2.15, ArchUnit 1.4.1 on JDK 25) on a scratch project with a clean layout and on one with a violating import: all pass the clean layout and catch the violation. Fill every placeholder: the layer names are paths (`src/domain`) for dependency-cruiser and package names for import-linter and ArchUnit; modular import-linter lists the modules (`<module-a>`, `<module-b>`, add more), and modular ArchUnit `<modules>` is the package that holds the modules (`<package>.<modules>.<module>`).

## dependencies

**Questions**: Who approves a new direct dependency today? Is there an allow-list or a lockfile review?
**Measure**: `bmax measure dependencies` once the builtin is declared: manifests and the number of direct dependencies in each.
**Default**: A new direct dependency needs an ADR, added in the same change, that names the manifest by path.
**Why**: Opinion, not measurement: a dependency is a long-term cost chosen in a few seconds, and a name an agent proposes may not exist or may be a look-alike. The builtin reads `package.json`, `pyproject.toml`, `pom.xml` and `build.gradle*` only.
**Class and gate**: security; commit gate (builtin dependencies, no baseline)
**Opinion**: Whether an ADR is the right gate, and whether dev-only dependencies are exempt.

## folder-layout

**Questions**: Which directories hold which kinds of files? Are there files that may live anywhere?
**Measure**: `scripts/measure.sh tree 2` shows the current directory shape.
**Default**: The layout the measured tree already shows, as `allowed` patterns; greenfield, the layout of the approved architecture style.
**Why**: A predictable layout lets an agent place a new file without searching (https://matklad.github.io/2021/02/06/ARCHITECTURE.md.html on keeping a stable codemap).
**Class and gate**: correctness, or heuristic with a TSV baseline when adopted late; fast gate (builtin folder-layout)
**Opinion**: Strictness is opinion; start permissive and tighten.

## exemplars

**Questions**: Is there a file or module that shows the right way, next to legacy code an agent should not copy?
**Measure**: Read the code with the team; there is no automatic measurement.
**Default**: Name the exemplar and the legacy zone in the script that enforces the rule (`exemplar:` and `legacy:`) and in the nested `AGENTS.md` of the directory ("follow X, not Y").
**Why**: Agents copy their neighbours; pointing at the canonical file before they do prevents spreading the old pattern. `bmax check` reports `exemplar-missing` when the named file disappears.
**Class and gate**: none (inferential); `bmax check` verifies the file exists
**Opinion**: Which file is the exemplar.
