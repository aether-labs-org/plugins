# bmax wrapper - Windows (Git Bash) and proxy diagnostics

Status: active
Scope: .agents/bin/bmax, .agents/bmax.lock, plugins/baymax/bmax/bin/bmax, plugins/baymax/bmax/bmax.lock, .gitattributes, tests/bmax_wrapper*.sh, docs/adr/0003-*.md, docs/architecture.md, plugins/baymax/README.md, .agents/plans/bmax-windows-wrapper.md

Problem: the wrapper refuses any OS that is not Linux/macOS (`MINGW*`/`MSYS*` from Git Bash end in `unsupported operating system`),
there is no `windows-amd64` build in `bmax.lock`, and download failures hide the cause (`curl -fsSL`), which hurts behind proxies.

Protected files are in Scope (`.agents/bin/`, `bmax.lock`, ADR): each edit waits for the human's confirmation.

## Phases

1. **Decide** (ADR 0003): native Windows via Git Bash (needs a `bmax-windows-amd64.exe` release) vs keep "Windows through WSL" and only
   improve the message. Recommended: native Git Bash, amd64 only.
2. **Binary**: build and publish `bmax-windows-amd64.exe` in the `cli/bmax/v<version>` release; add `windows-amd64=<sha256>` to both locks
   (written by Baymax, not by hand).
3. **Wrapper OS detection** (both copies, kept identical): map `mingw*|msys*|cygwin*` to `windows`; binary name `bmax.exe`;
   cache under `${LOCALAPPDATA:-$HOME/AppData/Local}/bmax/<version>` (via `cygpath -u` when present); URL suffix `.exe`;
   `chmod` is a no-op there; `exec` the `.exe`.
4. **Line endings**: `.gitattributes` forces `eol=lf` for `.agents/bin/bmax`, `plugins/baymax/bmax/bin/bmax`, `*.lock` and `*.sh`
   (CRLF would break `set -eu`).
5. **Proxy / private network**:
   - keep honouring `HTTPS_PROXY`/`ALL_PROXY`/`NO_PROXY` (curl) and export the lowercase variants for wget;
   - show the real cause on failure: drop `-s`, keep `-S`, and add a hint for exit codes 5/6/7 (proxy/DNS/connect), 35/60 (TLS/CA)
     and HTTP 407 (proxy auth), naming `HTTPS_PROXY`, `CURL_CA_BUNDLE` and `BMAX_RELEASE_URL`;
   - document the mirror (`BMAX_RELEASE_URL`) for networks without GitHub access; the sha256 check stays mandatory.
6. **Tests** (bash suite): stub `uname` (`MINGW64_NT-10.0`) and `curl`; cover OS mapping, `.exe` URL and cache path, CRLF lock file,
   proxy hints per curl exit code, and that Linux/macOS behaviour is unchanged.
7. **Docs**: update the OS line in the wrapper header, `docs/architecture.md` and the baymax README.

## Acceptance

- [ ] ADR 0003 records the decision (native Git Bash vs WSL only).
- [ ] On a stubbed `MINGW64_NT` host the wrapper resolves `windows-amd64`, downloads `bmax-windows-amd64.exe` and verifies its sha256.
- [ ] An unsupported OS still fails with exit 3 and a message that names the supported ones.
- [ ] The two wrapper copies are identical.
- [ ] A download through `HTTPS_PROXY` works; a proxy/TLS/407 failure prints a specific hint instead of only `cannot download`.
- [ ] `.gitattributes` keeps the wrapper and locks in LF.
- [ ] Linux and macOS paths unchanged (existing wrapper tests green).
- [ ] Fast and slow gates green; `make validate` green.
