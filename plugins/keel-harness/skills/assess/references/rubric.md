# The rubric, and the right to say "I don't know"

Six axes, three states each, mandatory evidence. No third-party diagnosis tool — this is a
deterministic internal scan.

| Axis | Present | Partial | Absent |
| --- | --- | --- | --- |
| **Bootstrap** | Lockfile, and a single target that installs and builds — and it runs | Lockfile without a single target, or a target that exists and fails | Neither |
| **Guides** | `AGENTS.md` at root ≤ 100 lines, and `docs/` with content | One of the two, or `AGENTS.md` over the ceiling | Neither |
| **Fast sensors** | Types and style configured *and* runnable | Configured, but one does not run | No configuration |
| **Slow sensors** | A suite that runs, and coverage configuration | Suite without coverage, or a suite that fails | No suite |
| **Enforcement** | `.pre-commit-config.yaml` and a CI workflow running the same commands | One of the two, or divergent local/CI commands | Neither |
| **Context** | Pointers to the other tools, and `.mcp.json` declared (even empty) | Missing pointers, or connectors without declaration | Nothing |

## There is no aggregate score

This is a decision, not an oversight. A score suggests the ruler measures quality; it measures
presence of evidence. Summing axes would require weights no source justifies. Report each axis on
its own; never a total, never an overall grade.

## Two cost units, and only two

- **setup minutes** — how long `build` takes to close that gap, confirmations included.
- **seconds added to the gate** — how much that sensor adds to every edit, measured by running the
  tool once on the real repository, never estimated.

Both units are **measured**, never estimated. Run the tool once when it is installed and read the
real number. When the tool is not installed and cannot be measured, the cost is reported as
**not measured** — never as a guess.

## The third inference outcome

The rule "never an open question, always a confirmation of an inference" needs an exit for when
the inference fails. Three confidence levels, not two:

| Confidence | The kit does | Example |
| --- | --- | --- |
| **High** — consistent evidence | States the inference and asks for acceptance | "I see `api/`, `domain/` and `db/`, and `domain/` never imports `db/`. Is that the rule?" |
| **Low** — partial or contradictory | Narrow question with the options seen — never an open one | "I found two plausible layerings. Is it (a) or (b)? Or neither?" |
| **None** | Declares it could not infer, **does not install the layer**, records the reason in `.agents/state.yml` | "I could not identify module boundaries here. Without them a fitness function would be an invented rule — leaving it out." |

The `none` outcome exists to prevent the most expensive failure mode of this category of tool:
installing a rule the kit invented and presenting it as the project's. A layer left out costs one
line of explanation; an invented rule costs trust in every other rule.
