# Topic file: docs/testing.md

Copy this skeleton to `docs/testing.md` when it does not exist. It holds the `testing-strategy`
section: test types per layer, frameworks, naming and location, thresholds, and the commands for
suites keel does not run (integration, e2e).

```markdown
# Testing

{{One or two lines: the shape of the suite and where it runs.}}

<a id="testing-strategy"></a>
### Behaviour changes ship with tests; the slow gate checks their strength

**Rule.** {{Every changed main file has a test at its mapped path; before a pull request
`make gate-slow` shows a mutation score of at least 60 % and diff coverage of at least 80 %.}}
**Why.** {{Agents write tests that pass; mutation testing checks that they check something.}}
**✓ / ✗.** {{✓ `FooTest` asserts the fee amount. ✗ `FooTest` only calls `foo()`.}}
**When it fails.** {{Add the missing assertion at the mapped path; never lower a threshold.}}
**Decision.** [ADR 0004](decisions/0004-testing-strategy.md)
```
