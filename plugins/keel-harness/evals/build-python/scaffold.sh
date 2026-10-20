#!/usr/bin/env bash
# Host prerequisites: python3 with venv and network access (pip installs mypy, ruff and pytest into .venv).
# A small mature Python repository: pyproject.toml, a .venv with the tools, a source package and a
# test. No AGENTS.md, no docs/, no CI.
set -euo pipefail

mkdir -p ledger tests
cat > pyproject.toml <<'TOML'
[project]
name = "ledger"
version = "1.0.0"
requires-python = ">=3.10"

[tool.mypy]
strict = true

[tool.ruff]
line-length = 100

[tool.pytest.ini_options]
testpaths = ["tests"]
TOML
cat > requirements-dev.txt <<'TXT'
mypy==1.11.2
ruff==0.6.9
pytest==8.3.3
TXT
cat > ledger/__init__.py <<'PY'
PY
cat > ledger/posting.py <<'PY'
def apply_fee(cents: int) -> int:
    return round(cents * 0.98)
PY
cat > tests/test_posting.py <<'PY'
from ledger.posting import apply_fee


def test_applies_the_fee() -> None:
    assert apply_fee(1224) == 1200
PY
cat > .gitignore <<'GITIGNORE'
.venv/
__pycache__/
.mypy_cache/
.ruff_cache/
.pytest_cache/
GITIGNORE
python3 -m venv .venv
.venv/bin/pip install --quiet -r requirements-dev.txt
git init -q && git add -A && git -c user.email=eval@local -c user.name=eval commit -qm "initial"
