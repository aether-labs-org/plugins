# Discovery commands

The read-only discovery `build` runs before proposing anything, when `assess` has not already produced
its report table in the session. Every command in a proposal, in `AGENTS.md` or in a sensor must be
one these commands (or the files they list) showed.

```bash
cat package.json 2>/dev/null | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('scripts',{}))" 2>/dev/null
grep -E "^[a-zA-Z_-]+:" Makefile 2>/dev/null | head -30
ls mvnw gradlew pnpm-lock.yaml yarn.lock package-lock.json uv.lock poetry.lock 2>/dev/null
find docs/ -maxdepth 2 -name "*.md" 2>/dev/null | sort; ls src/ lib/ app/ packages/ services/ 2>/dev/null
ls .eslintrc* eslint.config* tsconfig.json ruff.toml mypy.ini .pre-commit-config.yaml .github/workflows/ 2>/dev/null
ls AGENTS.md CLAUDE.md .claude/CLAUDE.md .agents/state.yml 2>/dev/null
```
