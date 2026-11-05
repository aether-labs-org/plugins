# Architecture

## Plugin isolation

The repository holds independent plugins under `plugins/`: `keel-harness`, `second-brain` and `solutions-architect`. Each is
installed on its own through the marketplace in `.claude-plugin/marketplace.json`, so it must work without the others.

**Rule:** files of one plugin never reference another plugin, by a path containing `plugins/<other>` or by `../<other>`.

- Enforced by the scripts `isolation-keel-harness`, `isolation-second-brain` and `isolation-solutions-architect` in
  `.agents/keel.yml` (gate `fast`). Evidence when adopted: 0 cross-plugin references.
- Out of scope of the scripts: `evals/` directories (fixtures may name any path), `node_modules` and `dist`.
- Shared repository files (`tests/`, `Makefile`, `.claude-plugin/`, `README.md`) may name every plugin.
- A deliberate exception needs an ADR naming `.agents/keel.yml#isolation-<plugin>`.
