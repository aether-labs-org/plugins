npx depcruise src --config .dependency-cruiser.cjs --output-type err
tool version: dependency-cruiser 17.4.3 with typescript 5.9.3
2026-11-04
^\s*(?P<severity>error|warn|info) (?P<rule>[a-z0-9-]+): (?P<file>\S+) → (?P<message>\S+)$
