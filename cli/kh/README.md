# kh — the keel harness CLI

`kh` runs a repository's keel gates from `.agents/keel.yaml` and keeps the sensor contract of
`plugins/keel-harness/skills/build/references/sensor-contract.md` byte for byte. Design:
`docs/specs/2026-10-24-keel-cli-design.md`; plan: `docs/plans/2026-10-24-keel-cli-plan.md`.
The binary is `kh`, not `keel`, so it never collides with the plugin's own `scripts/keel` (v0.3 D34).

Not wired into the plugin until phase F4: installed repositories still run the bash engine.

| Command | Does | Exit |
| --- | --- | --- |
| `kh gate [fast\|slow]` | runs a gate; report and `.agents/last-run*.log` as `scripts/gate.sh` | 0 pass, 1 fail |
| `kh gate --sensor <id>` | runs one sensor with `SCOPE` as given; prints its contract output | the sensor's 0/1/2 |
| `kh measure <id>` | the same with `KEEL_MEASURE=1` | the sensor's |
| `kh guard` | the native guard sensor (D32, extended to keel.yaml) | 0/1 |
| `kh validate` | keel.yaml, keel.lock and the pin | 0, or 3 |
| `kh import [--force] [--sums FILE]` | keel.yaml (and keel.lock) from a bash-engine install | 0, or 3 |

Every configuration or pin problem exits 3 and is never a pass; bad usage exits 64.

    make build   # dist/kh and dist/SHA256SUMS for this machine
    make dist    # dist/engine/<os>-<arch>/kh and SHA256SUMS, byte-reproducible
    make test    # go vet + go test
    make -C ../.. check-cli   # unit tests, then the whole suite on the bash and the kh engine
