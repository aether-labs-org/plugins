import { isBlank, splitTrailingAgentBlocks } from "./blocks";
import { bodyStartLine } from "./frontmatter";

/**
 * Same rules as lib/sb/frontmatter.py `parse` in the second-brain plugin: strip a leading BOM,
 * CRLF to LF, body = the lines after the closing "---" joined with "\n". Without a closed
 * frontmatter block the whole text is the body.
 */
export function splitFrontmatter(text: string): { frontmatter: string; body: string } {
	const normalised = text.replace(/^\uFEFF+/, "").replace(/\r\n/g, "\n");
	const lines = normalised.split("\n");
	const start = bodyStartLine(lines);
	if (start === 0) return { frontmatter: "", body: normalised };
	return { frontmatter: lines.slice(1, start - 1).join("\n"), body: lines.slice(start).join("\n") };
}

/**
 * The text a review covers (spec 7.1): body minus trailing agent callouts, trailing spaces and
 * tabs removed per line, leading and trailing blank lines removed. No Unicode normalisation.
 */
export function reviewBody(text: string): string {
	const { kept } = splitTrailingAgentBlocks(splitFrontmatter(text).body);
	const lines = kept.split("\n").map((l) => l.replace(/[ \t]+$/, ""));
	let start = 0;
	let end = lines.length;
	while (start < end && isBlank(lines[start] ?? "")) start++;
	while (end > start && isBlank(lines[end - 1] ?? "")) end--;
	return lines.slice(start, end).join("\n");
}

/** `sha256:` plus the first 16 lowercase hex digits of SHA-256 over the UTF-8 review body. */
export async function reviewHash(text: string): Promise<string> {
	const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(reviewBody(text)));
	const hex = Array.from(new Uint8Array(digest).slice(0, 8), (b) => b.toString(16).padStart(2, "0")).join("");
	return "sha256:" + hex;
}

export type TrustState = "unreviewed" | "reviewed" | "changed-since-review" | "agent-blocks-pending" | "none";

/** True for markdown notes under a `wiki/` folder, excluding `_*` and `.*` path parts below it. */
export function isWikiNote(path: string): boolean {
	if (!path.endsWith(".md")) return false;
	const parts = path.split("/");
	const wiki = parts.indexOf("wiki");
	if (wiki < 0 || wiki === parts.length - 1) return false;
	return parts.slice(wiki + 1).every((p) => !p.startsWith("_") && !p.startsWith("."));
}

/** Missing, null, `[]` and a blank string all mean "not set", as in lib/sb/trust.py. */
function isEmpty(value: unknown): boolean {
	return (
		value === undefined ||
		value === null ||
		(Array.isArray(value) && value.length === 0) ||
		(typeof value === "string" && value.trim() === "")
	);
}

/**
 * Trust state of a note (spec 5.3, 7.2). `none` when `path` is given and is not a wiki note.
 * Order: unreviewed, changed-since-review, agent-blocks-pending, reviewed. A review done without
 * `reviewed_hash` (set by hand) stays valid.
 */
export async function trustState(
	text: string,
	frontmatter: Record<string, unknown>,
	path?: string,
): Promise<TrustState> {
	if (path !== undefined && !isWikiNote(path)) return "none";
	const origin = frontmatter["origin"];
	if ((origin === "agent" || origin === "mixed") && isEmpty(frontmatter["reviewed"])) return "unreviewed";
	const stored = frontmatter["reviewed_hash"];
	if (typeof stored === "string" && stored.trim() !== "" && stored.trim() !== (await reviewHash(text))) {
		return "changed-since-review";
	}
	if (splitTrailingAgentBlocks(splitFrontmatter(text).body).blocks.length > 0) return "agent-blocks-pending";
	return "reviewed";
}
