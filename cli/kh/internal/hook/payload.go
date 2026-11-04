// Package hook implements the agent and git hooks of kh: kh hook pre-tool-use,
// stop and commit-msg. One hook file (.claude/settings.json) serves Claude
// Code, Copilot CLI and Devin CLI; the answer is one JSON valid for both
// Claude and Copilot (spec section 9.1).
package hook

import (
	"encoding/json"
	"io"
	"strings"
)

// Payload is what an agent sends to a hook, reduced to what kh reads.
type Payload struct {
	Event, Tool, PermissionMode, Cwd string
	FilePath                         string // tool_input.file_path | notebook_path | Copilot toolArgs path
	Command                          string // Bash tool_input.command
	StopHookActive                   bool
}

type rawPayload struct {
	Event           string          `json:"hook_event_name"`
	EventCamel      string          `json:"hookEventName"`
	Tool            string          `json:"tool_name"`
	ToolCamel       string          `json:"toolName"`
	PermissionMode  string          `json:"permission_mode"`
	Cwd             string          `json:"cwd"`
	ToolInput       json.RawMessage `json:"tool_input"`
	ToolArgs        json.RawMessage `json:"toolArgs"`
	ToolInputCamel  json.RawMessage `json:"toolInput"`
	StopActive      bool            `json:"stop_hook_active"`
	StopActiveCamel bool            `json:"stopHookActive"`
}

type toolInput struct {
	FilePath     string `json:"file_path"`
	FilePathCml  string `json:"filePath"`
	Path         string `json:"path"`
	NotebookPath string `json:"notebook_path"`
	Command      string `json:"command"`
}

// toolAliases maps the tool names of Copilot's native shape to Claude's.
var toolAliases = map[string]string{
	"create": "Write", "write": "Write", "edit": "Edit", "str_replace": "Edit", "str_replace_editor": "Edit",
	"str_replace_based_edit_tool": "Edit", "insert": "Edit", "multiedit": "MultiEdit", "notebookedit": "NotebookEdit",
	"bash": "Bash", "shell": "Bash", "powershell": "Bash",
}

func normalizeTool(name string) string {
	switch name {
	case "Write", "Edit", "MultiEdit", "NotebookEdit", "Bash":
		return name
	}
	if a, ok := toolAliases[strings.ToLower(name)]; ok {
		return a
	}
	return name
}

// decodeInput reads tool_input / toolArgs, which is an object or a JSON string
// holding an object.
func decodeInput(raw json.RawMessage) toolInput {
	var in toolInput
	if len(raw) == 0 {
		return in
	}
	if json.Unmarshal(raw, &in) == nil {
		return in
	}
	var s string
	if json.Unmarshal(raw, &s) == nil {
		_ = json.Unmarshal([]byte(s), &in)
	}
	return in
}

// Parse reads a hook payload: the Claude shape, Copilot's Claude-format shape
// and Copilot's native shape (toolName, toolArgs).
func Parse(r io.Reader) (Payload, error) {
	b, err := io.ReadAll(io.LimitReader(r, 8<<20))
	if err != nil {
		return Payload{}, err
	}
	var raw rawPayload
	if err := json.Unmarshal(b, &raw); err != nil {
		return Payload{}, err
	}
	p := Payload{Event: raw.Event, Tool: raw.Tool, PermissionMode: raw.PermissionMode, Cwd: raw.Cwd, StopHookActive: raw.StopActive || raw.StopActiveCamel}
	if p.Event == "" {
		p.Event = raw.EventCamel
	}
	if p.Tool == "" {
		p.Tool = raw.ToolCamel
	}
	p.Tool = normalizeTool(p.Tool)
	in := decodeInput(raw.ToolInput)
	if in == (toolInput{}) {
		in = decodeInput(raw.ToolArgs)
	}
	if in == (toolInput{}) {
		in = decodeInput(raw.ToolInputCamel)
	}
	for _, v := range []string{in.FilePath, in.FilePathCml, in.NotebookPath, in.Path} {
		if v != "" {
			p.FilePath = v
			break
		}
	}
	p.Command = in.Command
	return p, nil
}

// bypassMode: in these permission modes "ask" is not guaranteed to prompt.
func bypassMode(mode string) bool {
	return mode == "bypassPermissions" || mode == "dontAsk"
}
