package guard

import (
	"regexp"
	"strings"
)

// ADRStatus is the lower-case first word of an ADR's status ("accepted",
// "proposed", "superseded", ...); "" when the ADR has none.
type ADRStatus string

var (
	statusLine = regexp.MustCompile(`(?i)^(?:\* |- )?status: *(\w+)`)
	frontKey   = regexp.MustCompile(`(?i)^status: *["']?(\w+)`)
)

// StatusOf reads the status from the YAML front matter ("status: accepted") or
// from a line "Status: accepted" (optionally after "* "). CRLF is tolerated.
func StatusOf(content string) ADRStatus {
	content = strings.ReplaceAll(content, "\r\n", "\n")
	lines := strings.Split(content, "\n")
	if len(lines) > 0 && strings.TrimSpace(lines[0]) == "---" {
		for _, l := range lines[1:] {
			if strings.TrimSpace(l) == "---" {
				break
			}
			if m := frontKey.FindStringSubmatch(l); m != nil {
				return ADRStatus(strings.ToLower(m[1]))
			}
		}
	}
	for _, l := range lines {
		if m := statusLine.FindStringSubmatch(l); m != nil {
			return ADRStatus(strings.ToLower(m[1]))
		}
	}
	return ""
}

var (
	statusAny = regexp.MustCompile(`(?im)^((?:\* |- )?status: *).*$`)
	superRef  = regexp.MustCompile(`(?i)^superseded by [^\n]*\d{4}`)
)

func normalizeADR(s string) string {
	s = strings.ReplaceAll(s, "\r\n", "\n")
	s = statusAny.ReplaceAllString(s, "${1}<status>")
	// front matter status
	s = regexp.MustCompile(`(?im)^status: *.*$`).ReplaceAllString(s, "status: <status>")
	return strings.TrimRight(s, "\n ")
}

// statusValue is the full text after "status:" ("Superseded by 0007").
func statusValue(content string) string {
	content = strings.ReplaceAll(content, "\r\n", "\n")
	for _, l := range strings.Split(content, "\n") {
		if m := regexp.MustCompile(`(?i)^(?:\* |- )?status: *(.*)$`).FindStringSubmatch(l); m != nil {
			return strings.Trim(strings.TrimSpace(m[1]), `"'`)
		}
	}
	return ""
}

// adrEdited reports whether an accepted ADR was edited: any change but the
// status line becoming "Superseded by NNNN".
func adrEdited(base, cur string) bool {
	b, c := strings.ReplaceAll(base, "\r\n", "\n"), strings.ReplaceAll(cur, "\r\n", "\n")
	if strings.TrimRight(b, "\n ") == strings.TrimRight(c, "\n ") {
		return false
	}
	if normalizeADR(base) == normalizeADR(cur) && StatusOf(cur) == "superseded" && superRef.MatchString(statusValue(cur)) {
		return false
	}
	return true
}
