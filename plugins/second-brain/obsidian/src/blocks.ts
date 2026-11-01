import { bodyStartLine } from "./frontmatter";

const AGENT_HEADER_RE = /^> \[!agent\]/i;

function isBlank(line: string): boolean {
	return line.trim() === "";
}

function dropTrailingBlank(lines: string[]): string[] {
	let end = lines.length;
	while (end > 0 && isBlank(lines[end - 1] ?? "")) end--;
	return lines.slice(0, end);
}

/**
 * Splits trailing `> [!agent]` callouts off a body (LF line endings). A trailing block is a run
 * starting at a header line where every following non-blank line starts with ">", up to the end
 * of the body. `kept` is everything before the first trailing block; each entry of `blocks` is one
 * callout (header line included, trailing blank lines removed).
 */
export function splitTrailingAgentBlocks(body: string): { kept: string; blocks: string[] } {
	const lines = body.split("\n");
	let start = lines.length;
	while (start > 0) {
		const prev = lines[start - 1] ?? "";
		if (!isBlank(prev) && !prev.startsWith(">")) break;
		start--;
	}
	let first = -1;
	for (let i = start; i < lines.length; i++) {
		if (AGENT_HEADER_RE.test(lines[i] ?? "")) {
			first = i;
			break;
		}
	}
	if (first < 0) return { kept: body, blocks: [] };

	const blocks: string[][] = [];
	for (let i = first; i < lines.length; i++) {
		const line = lines[i] ?? "";
		if (AGENT_HEADER_RE.test(line)) blocks.push([line]);
		else blocks[blocks.length - 1]?.push(line);
	}
	return {
		kept: lines.slice(0, first).join("\n"),
		blocks: blocks.map((b) => dropTrailingBlank(b).join("\n")),
	};
}

/**
 * Turns the trailing agent callouts of a whole note into plain text: drops each header line and
 * the "> " prefix of the other lines, with a blank line between blocks. Frontmatter, BOM and the
 * line-ending style are preserved. Returns `text` unchanged when there are no trailing blocks.
 */
export function unwrapAgentBlocks(text: string): string {
	const crlf = text.includes("\r\n");
	const bom = /^\uFEFF*/.exec(text)?.[0] ?? "";
	const lines = text.slice(bom.length).replace(/\r\n/g, "\n").split("\n");
	const start = bodyStartLine(lines);
	const prefix = lines.slice(0, start).join("\n") + (start > 0 ? "\n" : "");
	const body = lines.slice(start).join("\n");

	const { kept, blocks } = splitTrailingAgentBlocks(body);
	if (blocks.length === 0) return text;

	const unwrapped = blocks
		.map((b) =>
			b
				.split("\n")
				.slice(1)
				.map((l) => l.replace(/^> ?/, ""))
				.join("\n"),
		)
		.filter((b) => b.trim() !== "");
	const parts = [dropTrailingBlank(kept.split("\n")).join("\n"), ...unwrapped].filter((p) => p !== "");
	let out = prefix + parts.join("\n\n") + (body.endsWith("\n") ? "\n" : "");
	if (crlf) out = out.replace(/\n/g, "\r\n");
	return bom + out;
}
