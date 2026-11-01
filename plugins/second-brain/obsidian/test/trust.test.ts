import { describe, expect, it } from "vitest";
import { isWikiNote, reviewHash, trustState } from "../src/hash";

const BODY = "# T\n\nText.\n";
const BLOCK = "\n> [!agent] 2026-11-02 · src-001\n> Added.\n";
const note = (fm: string, body = BODY) => `---\n${fm}\n---\n${body}`;

describe("trustState", () => {
	it("unreviewed: agent origin and no reviewed date", async () => {
		expect(await trustState(note("origin: agent"), { origin: "agent" })).toBe("unreviewed");
		expect(await trustState(note("origin: mixed"), { origin: "mixed", reviewed: "" })).toBe("unreviewed");
		expect(await trustState(note("origin: agent"), { origin: "agent", reviewed: null })).toBe("unreviewed");
	});

	it("reviewed: hash matches", async () => {
		const hash = await reviewHash(note("origin: agent"));
		const fm = { origin: "agent", reviewed: "2026-11-05", reviewed_hash: hash };
		expect(await trustState(note("origin: agent"), fm)).toBe("reviewed");
	});

	it("reviewed: human note without origin", async () => {
		expect(await trustState(note("title: A"), { title: "A" })).toBe("reviewed");
	});

	it("reviewed: reviewed set by hand without a hash stays valid", async () => {
		expect(await trustState(note("origin: agent"), { origin: "agent", reviewed: "2026-11-05" })).toBe("reviewed");
	});

	it("changed-since-review: hash differs", async () => {
		const hash = await reviewHash(note("origin: agent"));
		const fm = { origin: "agent", reviewed: "2026-11-05", reviewed_hash: hash };
		expect(await trustState(note("origin: agent", BODY + "Edited.\n"), fm)).toBe("changed-since-review");
	});

	it("agent-blocks-pending: trailing block after a review does not change the hash", async () => {
		const hash = await reviewHash(note("origin: agent"));
		const fm = { origin: "agent", reviewed: "2026-11-05", reviewed_hash: hash };
		expect(await trustState(note("origin: agent", BODY + BLOCK), fm)).toBe("agent-blocks-pending");
	});

	it("agent-blocks-pending: human note with a block", async () => {
		expect(await trustState(note("title: A", BODY + BLOCK), { title: "A" })).toBe("agent-blocks-pending");
	});

	it("changed-since-review wins over pending blocks", async () => {
		const fm = { origin: "agent", reviewed: "2026-11-05", reviewed_hash: "sha256:0000000000000000" };
		expect(await trustState(note("origin: agent", BODY + BLOCK), fm)).toBe("changed-since-review");
	});

	it("none: outside wiki/ or not a note", async () => {
		expect(await trustState(note("origin: agent"), { origin: "agent" }, "inbox/a.md")).toBe("none");
		expect(await trustState(note("origin: agent"), { origin: "agent" }, "wiki/a.png")).toBe("none");
		expect(await trustState(note("origin: agent"), { origin: "agent" }, "wiki/a.md")).toBe("unreviewed");
	});
});

describe("isWikiNote", () => {
	it("accepts markdown notes under wiki/", () => {
		expect(isWikiNote("wiki/concepts/a.md")).toBe(true);
		expect(isWikiNote("vault/wiki/a.md")).toBe(true);
	});
	it("rejects other paths, non-markdown and _/. files", () => {
		expect(isWikiNote("raw/a.md")).toBe(false);
		expect(isWikiNote("wiki/a.png")).toBe(false);
		expect(isWikiNote("wiki/concepts/_about.md")).toBe(false);
		expect(isWikiNote("wiki/.trash/a.md")).toBe(false);
	});
});
