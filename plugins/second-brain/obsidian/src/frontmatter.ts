/**
 * Index of the first body line of `lines` (already LF-split, BOM removed), or 0 when the text has
 * no closed frontmatter. Mirrors lib/sb/frontmatter.py `parse` in the second-brain plugin.
 */
export function bodyStartLine(lines: string[]): number {
	if ((lines[0] ?? "").trim() !== "---") return 0;
	for (let i = 1; i < lines.length; i++) {
		if ((lines[i] ?? "").trim() === "---") return i + 1;
	}
	return 0;
}
