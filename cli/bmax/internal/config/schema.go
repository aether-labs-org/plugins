package config

import "embed"

//go:embed schema/*.json
var schemas embed.FS

// Schema returns an embedded JSON Schema: "config", "result" or "memory".
func Schema(name string) ([]byte, bool) {
	switch name {
	case "config", "result", "memory":
	default:
		return nil, false
	}
	b, err := schemas.ReadFile("schema/" + name + ".json")
	if err != nil {
		return nil, false
	}
	return b, true
}
