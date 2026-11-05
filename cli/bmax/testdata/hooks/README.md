# Hook payloads

Payloads for the hook contract tests (`internal/hook`), built from the documented shapes (spec
section 9.1), not recorded from the agents: recording needs headless model runs (`claude -p`,
`copilot -p`), which were not authorised for this build. `__ROOT__` is replaced by the test
repository's root.

- `claude/`: Claude Code's PreToolUse and Stop payloads (`hook_event_name`, `tool_name`, `tool_input`,
  `permission_mode`, `cwd`, `stop_hook_active`).
- `copilot/`: Copilot CLI, which sends the same Claude-format shape for PascalCase events registered
  in `.claude/settings.json`, plus its native camelCase shape (`toolName`, `toolArgs` as a JSON string)
  that bmax also accepts.

When the owner validates the live behaviour (spec V30), replace or add recorded payloads here.
