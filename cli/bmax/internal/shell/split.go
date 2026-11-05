// Package shell splits a shell command into segments and answers four
// questions about each: which paths it writes, whether it does something bmax
// forbids, and what its command signature is. It only splits and reads; it
// never rewrites a command, and it is guidance with friction, not a security
// boundary.
package shell

import (
	"os"
	"regexp"
	"strings"
)

// Segment is one simple command.
type Segment struct {
	Assign    []string // leading NAME=value words
	Words     []string // the command and its arguments, unquoted
	Redirects []string // targets of output redirections (>, >>, >|, &>)
	Heredoc   string   // body of a here-document fed to the command
}

const maxDepth = 3

var assignRE = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_]*=`)

// Split splits cmd on &&, ||, ;, |, & and newlines (quotes respected). Commands
// nested in bash -c, sh -c, eval, $(...) and backticks are split too and
// appended after the segments of the outer command. ok=false means the command
// could not be split completely (an unbalanced quote): the segments found so
// far are still returned.
func Split(cmd string) ([]Segment, bool) { return split(cmd, 0) }

type parser struct {
	src []rune
	pos int

	segs   []Segment
	cur    Segment
	word   strings.Builder
	inWord bool

	redirPending bool   // the next word is the target of a write redirection
	skipNext     bool   // the next word is consumed and ignored (input redirection, here-string)
	heredocDelim string // delimiter waiting for its body
	heredocDash  bool
	heredocSeg   int // index into segs of the segment the body belongs to (-1: cur)
	nested       []string
	ok           bool
}

func split(cmd string, depth int) ([]Segment, bool) {
	p := &parser{src: []rune(cmd), ok: true, heredocSeg: -1}
	p.run()
	p.endSegment()
	segs := make([]Segment, 0, len(p.segs))
	for _, sg := range p.segs {
		segs = append(segs, Unwrap(sg))
	}
	if depth < maxDepth {
		for _, inner := range p.nested {
			s, ok := split(inner, depth+1)
			segs = append(segs, s...)
			p.ok = p.ok && ok
		}
		// bash -c STR, sh -c STR, eval STR, and here-documents fed to a shell
		n := len(segs)
		for i := 0; i < n; i++ {
			for _, code := range shellCode(segs[i]) {
				s, ok := split(code, depth+1)
				segs = append(segs, s...)
				p.ok = p.ok && ok
			}
		}
	}
	return segs, p.ok
}

var shellNames = map[string]bool{"bash": true, "sh": true, "zsh": true, "dash": true, "ksh": true}

// shellCode returns the command strings a segment hands to a shell.
func shellCode(s Segment) []string {
	if len(s.Words) == 0 {
		return nil
	}
	head := baseName(s.Words[0])
	var out []string
	switch {
	case head == "eval":
		out = append(out, strings.Join(s.Words[1:], " "))
	case shellNames[head]:
		for i := 1; i < len(s.Words)-1; i++ {
			a := s.Words[i]
			if a == "-c" || (strings.HasPrefix(a, "-") && !strings.HasPrefix(a, "--") && strings.Contains(a, "c")) {
				out = append(out, s.Words[i+1])
				break
			}
		}
		if s.Heredoc != "" {
			out = append(out, s.Heredoc)
		}
	}
	return out
}

func baseName(p string) string {
	if i := strings.LastIndexByte(p, '/'); i >= 0 {
		return p[i+1:]
	}
	return p
}

func (p *parser) peek(off int) rune {
	if p.pos+off < len(p.src) {
		return p.src[p.pos+off]
	}
	return 0
}

func (p *parser) endWord() {
	if !p.inWord {
		return
	}
	w := p.word.String()
	p.word.Reset()
	p.inWord = false
	switch {
	case p.skipNext:
		p.skipNext = false
	case p.redirPending:
		p.redirPending = false
		p.cur.Redirects = append(p.cur.Redirects, w)
	case len(p.cur.Words) == 0 && assignRE.MatchString(w):
		p.cur.Assign = append(p.cur.Assign, w)
	default:
		p.cur.Words = append(p.cur.Words, w)
	}
}

func (p *parser) endSegment() {
	p.endWord()
	p.redirPending, p.skipNext = false, false
	if len(p.cur.Words) > 0 || len(p.cur.Redirects) > 0 || len(p.cur.Assign) > 0 {
		p.segs = append(p.segs, p.cur)
		if p.heredocDelim != "" && p.heredocSeg < 0 {
			p.heredocSeg = len(p.segs) - 1
		}
	}
	p.cur = Segment{}
}

func (p *parser) run() {
	for p.pos < len(p.src) {
		c := p.src[p.pos]
		switch {
		case c == '\n':
			p.pos++
			p.endSegment()
			if p.heredocDelim != "" {
				p.readHeredoc()
			}
		case c == ' ' || c == '\t' || c == '\r':
			p.endWord()
			p.pos++
		case c == '\\':
			if p.peek(1) == '\n' {
				p.pos += 2
				continue
			}
			p.inWord = true
			if p.pos+1 < len(p.src) {
				p.word.WriteRune(p.src[p.pos+1])
			}
			p.pos += 2
		case c == '\'':
			p.inWord = true
			p.pos++
			end := p.pos
			for end < len(p.src) && p.src[end] != '\'' {
				end++
			}
			if end >= len(p.src) {
				p.ok = false
				p.word.WriteString(string(p.src[p.pos:]))
				p.pos = len(p.src)
				continue
			}
			p.word.WriteString(string(p.src[p.pos:end]))
			p.pos = end + 1
		case c == '"':
			p.inWord = true
			p.pos++
			p.doubleQuoted()
		case c == '`':
			p.inWord = true
			p.backtick()
		case c == '$' && p.peek(1) == '(':
			p.inWord = true
			p.dollarParen()
		case c == '#' && !p.inWord:
			for p.pos < len(p.src) && p.src[p.pos] != '\n' {
				p.pos++
			}
		case c == ';':
			p.pos++
			p.endSegment()
		case c == '&' && p.peek(1) == '&':
			p.pos += 2
			p.endSegment()
		case c == '&' && p.peek(1) == '>':
			p.endWord()
			p.pos += 2
			if p.peek(0) == '>' {
				p.pos++
			}
			p.redirPending = true
		case c == '&':
			p.pos++
			p.endSegment()
		case c == '|' && p.peek(1) == '|':
			p.pos += 2
			p.endSegment()
		case c == '|':
			p.pos++
			if p.peek(0) == '&' {
				p.pos++
			}
			p.endSegment()
		case c == '(' || c == ')':
			p.pos++
			p.endSegment()
		case c == '~' && !p.inWord && p.tildeAlone():
			p.inWord = true
			p.word.WriteString(homeDir())
			p.pos++
		case c == '$' && !p.inWord && p.homeVarLen() > 0:
			p.inWord = true
			p.word.WriteString(homeDir())
			p.pos += p.homeVarLen()
		case c == '>':
			p.redirect()
		case c == '<':
			p.input()
		default:
			p.inWord = true
			p.word.WriteRune(c)
			p.pos++
		}
	}
	if p.heredocDelim != "" {
		p.heredocDelim = ""
	}
}

// redirect handles > >> >| and >&.
func (p *parser) redirect() {
	// a word made only of digits right before > is a file descriptor
	if p.inWord && isDigits(p.word.String()) {
		p.word.Reset()
		p.inWord = false
	} else {
		p.endWord()
	}
	p.pos++ // >
	switch p.peek(0) {
	case '>', '|':
		p.pos++
	case '&':
		p.pos++
		// >&2 and >&- duplicate or close a descriptor; >&file writes a file
		if r := p.peek(0); r == '-' || (r >= '0' && r <= '9') {
			for p.pos < len(p.src) && (p.src[p.pos] == '-' || (p.src[p.pos] >= '0' && p.src[p.pos] <= '9')) {
				p.pos++
			}
			return
		}
	}
	p.redirPending = true
}

func isDigits(s string) bool {
	if s == "" {
		return false
	}
	for _, r := range s {
		if r < '0' || r > '9' {
			return false
		}
	}
	return true
}

// input handles < <<  <<- <<< : the next word is data or a delimiter, not a write.
func (p *parser) input() {
	if p.inWord && isDigits(p.word.String()) {
		p.word.Reset()
		p.inWord = false
	} else {
		p.endWord()
	}
	p.pos++ // <
	switch {
	case p.peek(0) == '<' && p.peek(1) == '<':
		p.pos += 2
		p.skipNext = true // here-string
	case p.peek(0) == '<':
		p.pos++
		dash := false
		if p.peek(0) == '-' {
			dash = true
			p.pos++
		}
		// read the delimiter word now
		for p.peek(0) == ' ' || p.peek(0) == '\t' {
			p.pos++
		}
		var d strings.Builder
		for p.pos < len(p.src) {
			r := p.src[p.pos]
			if r == ' ' || r == '\t' || r == '\n' || r == ';' || r == '|' || r == '&' || r == '<' || r == '>' {
				break
			}
			if r != '\'' && r != '"' && r != '\\' {
				d.WriteRune(r)
			}
			p.pos++
		}
		p.heredocDelim, p.heredocDash, p.heredocSeg = d.String(), dash, -1
	case p.peek(0) == '(':
		// process substitution <(...): leave it to the word reader
		p.inWord = true
		p.word.WriteRune('<')
	default:
		p.skipNext = true
	}
}

// readHeredoc consumes lines up to the delimiter and attaches the body to the
// segment that started the here-document.
func (p *parser) readHeredoc() {
	var body []string
	for p.pos < len(p.src) {
		end := p.pos
		for end < len(p.src) && p.src[end] != '\n' {
			end++
		}
		line := string(p.src[p.pos:end])
		if end < len(p.src) {
			end++
		}
		p.pos = end
		cmp := line
		if p.heredocDash {
			cmp = strings.TrimLeft(line, "\t")
		}
		if cmp == p.heredocDelim {
			break
		}
		body = append(body, line)
	}
	idx := p.heredocSeg
	if idx < 0 || idx >= len(p.segs) {
		idx = len(p.segs) - 1
	}
	if idx >= 0 {
		p.segs[idx].Heredoc = strings.Join(body, "\n")
	}
	p.heredocDelim = ""
}

func (p *parser) doubleQuoted() {
	for p.pos < len(p.src) {
		c := p.src[p.pos]
		switch {
		case c == '"':
			p.pos++
			return
		case c == '\\' && p.pos+1 < len(p.src):
			n := p.src[p.pos+1]
			if n == '"' || n == '\\' || n == '$' || n == '`' {
				p.word.WriteRune(n)
			} else if n == '\n' {
				// line continuation
			} else {
				p.word.WriteRune(c)
				p.word.WriteRune(n)
			}
			p.pos += 2
		case c == '$' && p.word.Len() == 0 && p.homeVarLen() > 0:
			p.word.WriteString(homeDir())
			p.pos += p.homeVarLen()
		case c == '$' && p.peek(1) == '(':
			p.dollarParen()
		case c == '`':
			p.backtick()
		default:
			p.word.WriteRune(c)
			p.pos++
		}
	}
	p.ok = false // no closing quote
}

// dollarParen reads $( ... ) with nesting; the text stays in the word and is
// also split as a command of its own.
func (p *parser) dollarParen() {
	start := p.pos
	p.pos += 2
	depth := 1
	inner := p.pos
	var q rune
	for p.pos < len(p.src) && depth > 0 {
		c := p.src[p.pos]
		switch {
		case q != 0:
			if c == q {
				q = 0
			} else if c == '\\' && q == '"' {
				p.pos++
			}
		case c == '\'' || c == '"':
			q = c
		case c == '(':
			depth++
		case c == ')':
			depth--
		}
		p.pos++
	}
	if depth > 0 {
		p.ok = false
		p.word.WriteString(string(p.src[start:]))
		return
	}
	p.nested = append(p.nested, string(p.src[inner:p.pos-1]))
	p.word.WriteString(string(p.src[start:p.pos]))
}

func (p *parser) backtick() {
	start := p.pos
	p.pos++
	inner := p.pos
	for p.pos < len(p.src) && p.src[p.pos] != '`' {
		if p.src[p.pos] == '\\' {
			p.pos++
		}
		p.pos++
	}
	if p.pos >= len(p.src) {
		p.ok = false
		p.word.WriteString(string(p.src[start:]))
		p.pos = len(p.src)
		return
	}
	p.nested = append(p.nested, string(p.src[inner:p.pos]))
	p.pos++
	p.word.WriteString(string(p.src[start:p.pos]))
}

// homeDir is the user's home directory ("" when unknown: nothing is expanded).
func homeDir() string {
	h, err := os.UserHomeDir()
	if err != nil {
		return ""
	}
	return h
}

// tildeAlone: the "~" at the current position is a bare tilde (followed by a
// slash or the end of the word), which the shell expands to $HOME. ~user is not.
func (p *parser) tildeAlone() bool {
	if homeDir() == "" {
		return false
	}
	switch p.peek(1) {
	case 0, '/', ' ', '\t', '\n', ';', '|', '&', '<', '>', ')':
		return true
	}
	return false
}

// homeVarLen is the length of $HOME or ${HOME} at the current position when it
// is a whole variable reference, else 0.
func (p *parser) homeVarLen() int {
	if homeDir() == "" {
		return 0
	}
	rest := string(p.src[p.pos:min(len(p.src), p.pos+8)])
	if strings.HasPrefix(rest, "${HOME}") {
		return len("${HOME}")
	}
	if strings.HasPrefix(rest, "$HOME") {
		if n := p.peek(5); n == '_' || (n >= 'a' && n <= 'z') || (n >= 'A' && n <= 'Z') || (n >= '0' && n <= '9') {
			return 0
		}
		return len("$HOME")
	}
	return 0
}
