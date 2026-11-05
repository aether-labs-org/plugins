package hook

import (
	"encoding/json"
	"io"
)

// Decision is the answer of the PreToolUse hook.
type Decision struct{ Kind, Reason string } // "allow" | "ask" | "deny"

// WritePreToolUse prints the decision as one JSON valid for Claude Code and
// Copilot CLI: Claude's hookSpecificOutput and the same two fields at top
// level (Copilot). An allowed call prints nothing.
func WritePreToolUse(w io.Writer, d Decision) {
	if d.Kind == "" || d.Kind == "allow" {
		return
	}
	out := map[string]any{
		"hookSpecificOutput": map[string]any{
			"hookEventName":            "PreToolUse",
			"permissionDecision":       d.Kind,
			"permissionDecisionReason": d.Reason,
		},
		"permissionDecision":       d.Kind,
		"permissionDecisionReason": d.Reason,
	}
	b, _ := json.Marshal(out)
	w.Write(append(b, '\n'))
}

// writeStopBlock asks the agent to continue with the gate result as the reason.
func writeStopBlock(w io.Writer, reason string) {
	b, _ := json.Marshal(map[string]any{"decision": "block", "reason": reason})
	w.Write(append(b, '\n'))
}

// writeSystemMessage shows a message to the human without blocking the agent.
func writeSystemMessage(w io.Writer, msg string) {
	b, _ := json.Marshal(map[string]any{"systemMessage": msg})
	w.Write(append(b, '\n'))
}
