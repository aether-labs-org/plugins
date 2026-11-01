import { describe, expect, it } from "vitest";
import { splitTrailingAgentBlocks, unwrapAgentBlocks } from "../src/blocks";

const FM = "---\ntitle: Note\n---\n";

describe("splitTrailingAgentBlocks", () => {
	it("returns the body unchanged when there are no blocks", () => {
		expect(splitTrailingAgentBlocks("Text\n")).toEqual({ kept: "Text\n", blocks: [] });
	});

	it("splits two trailing blocks", () => {
		const body = "Text\n\n> [!agent] d · a\n> one\n\n> [!agent] d · b\n> two\n";
		const r = splitTrailingAgentBlocks(body);
		expect(r.kept).toBe("Text\n");
		expect(r.blocks).toEqual(["> [!agent] d · a\n> one", "> [!agent] d · b\n> two"]);
	});

	it("does not treat a block followed by plain text as trailing", () => {
		const body = "> [!agent] d · a\n> one\nplain\n";
		expect(splitTrailingAgentBlocks(body)).toEqual({ kept: body, blocks: [] });
	});

	it("matches the header case-insensitively", () => {
		expect(splitTrailingAgentBlocks("T\n\n> [!Agent] d · a\n> x").blocks).toHaveLength(1);
	});

	it("keeps a plain blockquote before the first block", () => {
		const r = splitTrailingAgentBlocks("T\n\n> quote\n\n> [!agent] d · a\n> x\n");
		expect(r.kept).toBe("T\n\n> quote\n");
		expect(r.blocks).toHaveLength(1);
	});
});

describe("unwrapAgentBlocks", () => {
	it("is a no-op without blocks", () => {
		const plain = FM + "# T\n\nText.\n";
		expect(unwrapAgentBlocks(plain)).toBe(plain);
	});

	it("is a no-op for a block in the middle", () => {
		const mid = FM + "> [!agent] d · a\n> x\n\nafter\n";
		expect(unwrapAgentBlocks(mid)).toBe(mid);
	});

	it("unwraps one block", () => {
		const text = FM + "# T\n\nText.\n\n> [!agent] 2026-11-02 · src-001\n> Added fact.\n> Second line.\n";
		expect(unwrapAgentBlocks(text)).toBe(FM + "# T\n\nText.\n\nAdded fact.\nSecond line.\n");
	});

	it("unwraps two trailing blocks, keeping a blank line between them", () => {
		const text =
			FM +
			"# T\n\nText.\n\n> [!agent] 2026-11-02 · a\n> One.\n>\n> More one.\n\n> [!agent] 2026-11-03 · b\n> Two.\n";
		expect(unwrapAgentBlocks(text)).toBe(FM + "# T\n\nText.\n\nOne.\n\nMore one.\n\nTwo.\n");
	});

	it("preserves a CRLF file and its BOM", () => {
		const text = ("\uFEFF" + FM + "T\n\n> [!agent] d · a\n> One.\n").replace(/\n/g, "\r\n");
		expect(unwrapAgentBlocks(text)).toBe(("\uFEFF" + FM + "T\n\nOne.\n").replace(/\n/g, "\r\n"));
	});

	it("works on a note without frontmatter", () => {
		expect(unwrapAgentBlocks("T\n\n> [!agent] d · a\n> One.\n")).toBe("T\n\nOne.\n");
	});
});
