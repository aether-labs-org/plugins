#!/usr/bin/env bash
# discover.sh - read-only facts about a repository, for the keel harness skill.
# Usage: bash discover.sh [dir]        (default: the current directory)
# Prints key<TAB>value[<TAB>detail] lines on stdout and writes nothing: no file in the repository is created,
# changed or deleted. It reads the tree with git (tracked files plus untracked files that are not ignored).
#
# Keys: language, runtime, package-manager, test-runner, linter, formatter, type-checker, arch-tool, githook-manager,
#       instructions, agent-hooks, commit-convention, branch-pattern, ci (informational), agents-dir, keel.
set -uo pipefail

dir="${1:-.}"
cd "$dir" 2>/dev/null || { echo "discover: cannot enter $dir" >&2; exit 1; }

emit() {
  printf '%s\t%s' "$1" "$2"
  [ -n "${3:-}" ] && printf '\t%s' "$3"
  printf '\n'
}

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  ALL="$(git ls-files -z --cached --others --exclude-standard 2>/dev/null | tr '\0' '\n')"
  is_git=1
else
  ALL="$(find . -type f -not -path './.git/*' -not -path '*/node_modules/*' 2>/dev/null | sed 's|^\./||')"
  is_git=0
fi

# have REGEX: a file whose path matches REGEX exists
have() { printf '%s\n' "$ALL" | grep -Eq -- "$1"; }
# first REGEX: the first path that matches
first() { printf '%s\n' "$ALL" | grep -E -m 1 -- "$1" || true; }
# count REGEX
count() { printf '%s\n' "$ALL" | grep -Ec -- "$1" || true; }
# mentions REGEX FILE-REGEX: some file matching FILE-REGEX contains REGEX (case-sensitive)
mentions() {
  local f
  while IFS= read -r f; do
    [ -f "$f" ] && grep -Eq -- "$1" "$f" 2>/dev/null && return 0
  done < <(printf '%s\n' "$ALL" | grep -E -- "$2")
  return 1
}
# in_pyproject REGEX: pyproject.toml (at any depth) mentions REGEX
in_pyproject() { mentions "$1" '(^|/)pyproject\.toml$'; }
in_package_json() { mentions "$1" '(^|/)package\.json$'; }
in_jvm_build() { mentions "$1" '(^|/)(pom\.xml|build\.gradle|build\.gradle\.kts)$'; }

# ---------------------------------------------------------------- language
lang() { # lang NAME EXT-REGEX
  local n
  n="$(count "\\.($2)\$")"
  [ "$n" -gt 0 ] && emit language "$1" "$n files"
}
lang typescript 'ts|tsx|mts|cts'
lang javascript 'js|jsx|mjs|cjs'
lang python 'py'
lang java 'java'
lang kotlin 'kt|kts'
lang go 'go'
lang rust 'rs'
lang ruby 'rb'
lang csharp 'cs'
lang php 'php'

# ---------------------------------------------------------------- runtime (Node: some tools exclude odd versions in their engines)
if have '(^|/)package\.json$'; then
  nv="not installed"
  command -v node >/dev/null 2>&1 && nv="$(node --version 2>/dev/null || echo unknown)"
  pin="no pin"
  if have '(^|/)\.nvmrc$|(^|/)\.node-version$'; then pin="$(first '(^|/)(\.nvmrc|\.node-version)$')"
  elif in_package_json '"engines"'; then pin="package.json engines"
  fi
  emit runtime node "$nv, $pin"
fi

# ---------------------------------------------------------------- package manager
have '(^|/)pnpm-lock\.yaml$' && emit package-manager pnpm "$(first '(^|/)pnpm-lock\.yaml$')"
have '(^|/)yarn\.lock$' && emit package-manager yarn "$(first '(^|/)yarn\.lock$')"
have '(^|/)package-lock\.json$' && emit package-manager npm "$(first '(^|/)package-lock\.json$')"
have '(^|/)bun\.lockb?$' && emit package-manager bun "$(first '(^|/)bun\.lockb?$')"
if have '(^|/)package\.json$' && ! have '(^|/)(pnpm-lock\.yaml|yarn\.lock|package-lock\.json|bun\.lockb?)$'; then
  emit package-manager npm "no lockfile"
fi
have '(^|/)uv\.lock$' && emit package-manager uv "$(first '(^|/)uv\.lock$')"
have '(^|/)poetry\.lock$' && emit package-manager poetry "$(first '(^|/)poetry\.lock$')"
have '(^|/)Pipfile(\.lock)?$' && emit package-manager pipenv "$(first '(^|/)Pipfile(\.lock)?$')"
if have '(^|/)requirements[^/]*\.txt$' && ! have '(^|/)(uv|poetry)\.lock$'; then emit package-manager pip "$(first '(^|/)requirements[^/]*\.txt$')"; fi
have '(^|/)pom\.xml$' && emit package-manager maven "$(first '(^|/)pom\.xml$')"
if have '(^|/)build\.gradle(\.kts)?$'; then
  if have '(^|/)gradlew$'; then emit package-manager gradle "wrapper"; else emit package-manager gradle "no wrapper"; fi
fi
have '(^|/)go\.mod$' && emit package-manager go "$(first '(^|/)go\.mod$')"

# ---------------------------------------------------------------- test runner
if have '(^|/)vitest\.config\.[a-z]+$' || in_package_json '"vitest"'; then emit test-runner vitest "$(first '(^|/)vitest\.config\.[a-z]+$')"; fi
if have '(^|/)jest\.config\.[a-z]+$' || in_package_json '"jest"'; then emit test-runner jest "$(first '(^|/)jest\.config\.[a-z]+$')"; fi
if have '(^|/)playwright\.config\.[a-z]+$' || in_package_json '"@playwright/test"'; then emit test-runner playwright "$(first '(^|/)playwright\.config\.[a-z]+$')"; fi
if have '(^|/)cypress\.config\.[a-z]+$'; then emit test-runner cypress "$(first '(^|/)cypress\.config\.[a-z]+$')"; fi
if have '(^|/)mocha(rc)?(\.[a-z]+)?$|(^|/)\.mocharc'; then emit test-runner mocha ""; fi
if have '(^|/)(pytest\.ini|conftest\.py)$' || in_pyproject 'pytest' || mentions 'pytest' '(^|/)requirements[^/]*\.txt$'; then emit test-runner pytest "$(first '(^|/)(pytest\.ini|conftest\.py)$')"; fi
if in_jvm_build 'junit'; then emit test-runner junit ""; fi
if in_jvm_build 'testng'; then emit test-runner testng ""; fi
if in_jvm_build 'kotest'; then emit test-runner kotest ""; fi

# ---------------------------------------------------------------- linter
if have '(^|/)(eslint\.config\.[a-z]+|\.eslintrc(\.[a-z]+)?)$'; then emit linter eslint "$(first '(^|/)(eslint\.config\.[a-z]+|\.eslintrc(\.[a-z]+)?)$')"; fi
if have '(^|/)biome\.jsonc?$'; then emit linter biome "$(first '(^|/)biome\.jsonc?$')"; fi
if have '(^|/)\.?ruff\.toml$' || in_pyproject '^\[tool\.ruff'; then emit linter ruff "$(first '(^|/)\.?ruff\.toml$')"; fi
if have '(^|/)(\.pylintrc|pylintrc)$' || in_pyproject '^\[tool\.pylint'; then emit linter pylint ""; fi
if have '(^|/)(\.flake8)$'; then emit linter flake8 ".flake8"; fi
if have '(^|/)config/checkstyle/' || in_jvm_build 'checkstyle'; then emit linter checkstyle "$(first '(^|/)config/checkstyle/[^/]+\.xml$')"; fi
if have '(^|/)detekt[^/]*\.ya?ml$' || in_jvm_build 'detekt'; then emit linter detekt "$(first '(^|/)detekt[^/]*\.ya?ml$')"; fi
if in_jvm_build 'pmd'; then emit linter pmd ""; fi
if in_jvm_build 'spotbugs'; then emit linter spotbugs ""; fi

# ---------------------------------------------------------------- formatter
if have '(^|/)(\.prettierrc(\.[a-z]+)?|prettier\.config\.[a-z]+)$' || in_package_json '"prettier"'; then emit formatter prettier "$(first '(^|/)(\.prettierrc(\.[a-z]+)?|prettier\.config\.[a-z]+)$')"; fi
if in_pyproject '^\[tool\.black'; then emit formatter black ""; fi
if in_pyproject '^\[tool\.ruff\.format'; then emit formatter ruff-format ""; fi
if in_jvm_build 'spotless'; then emit formatter spotless ""; fi
if in_jvm_build 'ktlint'; then emit formatter ktlint ""; fi

# ---------------------------------------------------------------- type checker
if have '(^|/)tsconfig[^/]*\.json$'; then
  ts="$(first '(^|/)tsconfig\.json$')"
  [ -n "$ts" ] || ts="$(first '(^|/)tsconfig[^/]*\.json$')"
  strict=""
  [ -f "$ts" ] && grep -Eq '"strict"[[:space:]]*:[[:space:]]*true' "$ts" 2>/dev/null && strict="strict"
  emit type-checker tsc "$ts${strict:+ ($strict)}"
fi
if have '(^|/)(mypy\.ini|\.mypy\.ini)$' || in_pyproject '^\[tool\.mypy' || mentions '^\[mypy\]' '(^|/)setup\.cfg$'; then emit type-checker mypy "$(first '(^|/)(mypy\.ini|\.mypy\.ini)$')"; fi
if have '(^|/)pyrightconfig\.json$' || in_pyproject '^\[tool\.pyright'; then emit type-checker pyright "$(first '(^|/)pyrightconfig\.json$')"; fi

# ---------------------------------------------------------------- architecture tools
if have '(^|/)\.dependency-cruiser\.(js|cjs|mjs|json)$'; then emit arch-tool dependency-cruiser "$(first '(^|/)\.dependency-cruiser\.(js|cjs|mjs|json)$')"; fi
if have '(^|/)\.importlinter$' || in_pyproject '^\[tool\.importlinter'; then emit arch-tool import-linter "$(first '(^|/)\.importlinter$')"; fi
if in_jvm_build 'archunit'; then emit arch-tool archunit ""; fi

# ---------------------------------------------------------------- git hook managers
have '(^|/)\.husky/' && emit githook-manager husky ".husky"
have '(^|/)(\.?lefthook(-local)?\.ya?ml)$' && emit githook-manager lefthook "$(first '(^|/)\.?lefthook(-local)?\.ya?ml$')"
have '(^|/)\.pre-commit-config\.yaml$' && emit githook-manager pre-commit ".pre-commit-config.yaml"
in_package_json '"simple-git-hooks"' && emit githook-manager simple-git-hooks "package.json"
if [ "$is_git" = 1 ]; then
  hp="$(git config --get core.hooksPath 2>/dev/null || true)"
  [ -n "$hp" ] && emit githook-manager native "core.hooksPath=$hp"
fi

# ---------------------------------------------------------------- instruction files and agent hooks
inst() { # inst PATH
  [ -f "$1" ] && emit instructions "$1" "$(wc -l < "$1" | tr -d ' ') lines"
}
inst AGENTS.md
inst CLAUDE.md
inst .github/copilot-instructions.md
inst GEMINI.md
if [ -d .devin ]; then
  for f in .devin/*; do [ -e "$f" ] && emit instructions "$f" ""; done
fi
nested="$(count '(^|/)AGENTS\.md$')"
[ "$nested" -gt 1 ] && emit instructions "nested AGENTS.md" "$((nested - 1)) below the root"

hooks_in() { # hooks_in FILE -> names of the events with a hook
  grep -Eo '"(PreToolUse|PostToolUse|Stop|SessionStart|UserPromptSubmit|SubagentStop|preToolUse|postToolUse|agentStop|sessionStart)"' "$1" 2>/dev/null | tr -d '"' | sort -u | tr '\n' ',' | sed 's/,$//'
}
for f in .claude/settings.json .claude/settings.local.json; do
  if [ -f "$f" ] && grep -q '"hooks"' "$f" 2>/dev/null; then emit agent-hooks "$f" "$(hooks_in "$f")"; fi
done
for f in .github/hooks/*.json .devin/hooks*.json; do
  [ -f "$f" ] && emit agent-hooks "$f" "$(hooks_in "$f")"
done

# ---------------------------------------------------------------- conventions in the history
if [ "$is_git" = 1 ] && git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  total=0; conv=0
  while IFS= read -r s; do
    total=$((total + 1))
    case "$s" in
      feat:* | fix:* | docs:* | style:* | refactor:* | perf:* | test:* | build:* | ci:* | chore:* | revert:* | \
      feat\(*\):* | fix\(*\):* | docs\(*\):* | style\(*\):* | refactor\(*\):* | perf\(*\):* | test\(*\):* | build\(*\):* | ci\(*\):* | chore\(*\):* | revert\(*\):* | \
      feat!:* | fix!:* | feat\(*\)!:* | fix\(*\)!:* | refactor!:* | refactor\(*\)!:*)
        conv=$((conv + 1)) ;;
    esac
  done < <(git log -100 --format=%s 2>/dev/null)
  if [ "$total" -gt 0 ] && [ "$conv" -gt 0 ]; then
    emit commit-convention "conventional $((conv * 100 / total))%" "$conv of $total subjects"
  else
    emit commit-convention none "$total subjects"
  fi
  # branch names: the prefix before the first slash, with the remote name dropped
  branches="$(git for-each-ref --format='%(refname:short)' refs/heads refs/remotes 2>/dev/null |
    grep -v '/HEAD$' | sed 's|^origin/||' | sort -u |
    awk -F/ 'NF > 1 { c[$1]++ } END { for (p in c) printf "%d\t%s\n", c[p], p }' | sort -t "$(printf '\t')" -k1,1nr -k2,2)"
  if [ -n "$branches" ]; then
    while IFS="$(printf '\t')" read -r n p; do emit branch-pattern "$p/*" "$n branches"; done <<EOF_BRANCHES
$branches
EOF_BRANCHES
  else
    emit branch-pattern none ""
  fi
else
  emit commit-convention none "no commits"
  emit branch-pattern none ""
fi

# ---------------------------------------------------------------- CI (informational)
wf="$(count '^\.github/workflows/[^/]+\.ya?ml$')"
[ "$wf" -gt 0 ] && emit ci github-actions "$wf workflows"
have '(^|/)\.gitlab-ci\.yml$' && emit ci gitlab-ci ".gitlab-ci.yml"
have '(^|/)Jenkinsfile$' && emit ci jenkins "Jenkinsfile"
have '(^|/)\.circleci/config\.yml$' && emit ci circleci ".circleci/config.yml"
have '(^|/)azure-pipelines\.yml$' && emit ci azure-pipelines "azure-pipelines.yml"
have '(^|/)bitbucket-pipelines\.yml$' && emit ci bitbucket-pipelines "bitbucket-pipelines.yml"

# ---------------------------------------------------------------- what is under .agents/, and keel
if [ -d .agents ]; then
  listed=0
  for e in .agents/*; do
    [ -e "$e" ] || continue
    listed=1
    emit agents-dir "$(basename "$e")" "$([ -d "$e" ] && echo dir || echo file)"
  done
  [ "$listed" = 0 ] && emit agents-dir empty ""
else
  emit agents-dir absent ""
fi
if [ -f .agents/keel.yml ]; then
  v="$(sed -n 's/^version=//p' .agents/keel.lock 2>/dev/null | head -n 1 | tr -d '\r')"
  if [ -n "$v" ]; then emit keel "installed $v" ".agents/keel.lock"; else emit keel "installed unpinned" ".agents/keel.yml"; fi
else
  emit keel absent ""
fi
