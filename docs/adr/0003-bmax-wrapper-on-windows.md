# 0003. bmax wrapper on Windows

Status: proposed
Date: 2026-11-18

## Context and problem statement

The wrapper (`.agents/bin/bmax`, copy in `plugins/baymax/bmax/bin/bmax`) accepts only Linux and macOS. From Git Bash,
`uname -s` is `MINGW64_NT-*` and the wrapper ends with `unsupported operating system (... Windows through WSL)`.
`bmax.lock` has no `windows-*` entry and the releases have no `.exe`. Download failures also hide their cause
(`curl -fsSL`), which is hard to diagnose behind a corporate proxy.

## Considered options

### Native Git Bash with a `windows-amd64` build (recommended)

- Good: works where Windows developers already run git hooks.
- Good: no WSL setup; the repository can stay on `C:`.
- Bad: one more binary to build, publish and pin in both locks.
- Bad: wrapper gains an OS branch (cache path, `.exe`, LF line endings).

### Keep "Windows through WSL" and only improve the message

- Good: no new binary or wrapper branch.
- Bad: git hooks run by Git for Windows still fail; the repository should live in the WSL file system.

## Decision outcome

Pending the human's confirmation. Recommended: native Git Bash, `windows-amd64` only. Loosened, if accepted:

- `.agents/bin/bmax` and `plugins/baymax/bmax/bin/bmax` (OS case, cache path, `.exe`)
- `.agents/bmax.lock` and `plugins/baymax/bmax/bmax.lock` (`windows-amd64=`)

Proxy behaviour (`HTTPS_PROXY`, `ALL_PROXY`, `NO_PROXY`, `BMAX_RELEASE_URL` mirror) is kept; only the error hints change.

## Consequences

- Release process gains a Windows build; the sha256 check stays mandatory.
- Wrapper tests stub `uname` and `curl`.

## Evidence

- `.agents/bin/bmax` lines 97-101 (OS case), 157-167 (download).
- Plan: `.agents/plans/bmax-windows-wrapper.md`.
