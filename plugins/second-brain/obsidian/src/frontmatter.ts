/** A fence line: `---` with only spaces, tabs and CR around it (never `trim()`, which differs from Python). */
const FENCE_RE = /^[ \t\r]*---[ \t\r]*$/;

/**
 * Index of the first body line of `lines` (already LF-split, BOM removed), or 0 when the text has
 * no closed frontmatter. Mirrors lib/sb/frontmatter.py `parse` in the second-brain plugin.
 */
export function bodyStartLine(lines: string[]): number {
	if (!FENCE_RE.test(lines[0] ?? "")) return 0;
	for (let i = 1; i < lines.length; i++) {
		if (FENCE_RE.test(lines[i] ?? "")) return i + 1;
	}
	return 0;
}
