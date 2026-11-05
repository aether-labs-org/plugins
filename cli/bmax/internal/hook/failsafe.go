package hook

import (
	"io"
)

// FailSafe answers when bmax cannot do its job (invalid config, pin mismatch, no
// repository): the agents treat a failing or timed-out hook as non-blocking, so
// protection must not silently disappear (spec section 9.5).
//
//	pre-tool-use: ask for the call, or deny under bypassPermissions/dontAsk
//	stop:         never blocks; tells the human the gates did not run
func FailSafe(event string, stdin io.Reader, w io.Writer, reason string) {
	switch event {
	case "stop", "Stop":
		writeSystemMessage(w, "bmax unavailable: the gates did not run - "+reason)
	default:
		p, _ := Parse(stdin)
		kind := "ask"
		if bypassMode(p.PermissionMode) {
			kind = "deny"
		}
		WritePreToolUse(w, Decision{Kind: kind, Reason: "bmax unavailable: " + reason})
	}
}
