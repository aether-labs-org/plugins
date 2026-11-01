import { describe, expect, it } from "vitest";
import { reviewBody, reviewHash, splitFrontmatter } from "../src/hash";
import { vectors } from "./vectors";

describe("shared review-hash vectors", () => {
	it.each(vectors)("$name", async (v) => {
		expect(reviewBody(v.file)).toBe(v.review_body);
		expect(await reviewHash(v.file)).toBe(v.hash);
	});

	it("covers every required vector name", () => {
		const names = vectors.map((v) => v.name);
		for (const required of [
			"plain",
			"crlf",
			"bom",
			"trailing-spaces",
			"leading-trailing-blank-lines",
			"trailing-agent-block",
			"two-trailing-agent-blocks",
			"agent-block-in-middle",
			"empty-body",
			"frontmatter-reformatted",
		]) {
			expect(names).toContain(required);
		}
	});

	it("documents that Unicode is not normalised", () => {
		const byName = Object.fromEntries(vectors.map((v) => [v.name, v]));
		expect(byName["nfd-vs-nfc-nfc"]!.hash).not.toBe(byName["nfd-vs-nfc-nfd"]!.hash);
	});
});

describe("reviewHash", () => {
	it("has the format sha256:<16 lowercase hex>", async () => {
		expect(await reviewHash("---\na: b\n---\nx\n")).toMatch(/^sha256:[0-9a-f]{16}$/);
	});

	it("marks reviewed without touching the body", async () => {
		const body = "# Title\n\nSome text.\n\n> [!agent] 2026-11-02 · src-001\n> Pending.\n";
		const before = `---\ntitle: A\ntags: [x, y]\norigin: agent\nreviewed:\n---\n${body}`;
		// What Obsidian's processFrontMatter may produce: quoted values, block lists, other key order.
		const after =
			`---\norigin: agent\ntitle: "A"\ntags:\n  - x\n  - y\nreviewed: 2026-11-05\n` +
			`reviewed_hash: "sha256:0123456789abcdef"\n---\n${body}`;
		expect(await reviewHash(after)).toBe(await reviewHash(before));
	});
});

describe("splitFrontmatter", () => {
	it("mirrors Python parse: BOM, CRLF, body after the closing ---", () => {
		const r = splitFrontmatter("﻿---\r\na: 1\r\n---\r\nBody\r\nmore\r\n");
		expect(r.frontmatter).toBe("a: 1");
		expect(r.body).toBe("Body\nmore\n");
	});

	it("returns the whole text as body without frontmatter", () => {
		expect(splitFrontmatter("just text\n")).toEqual({ frontmatter: "", body: "just text\n" });
	});

	it("returns the whole text as body when the frontmatter is not closed", () => {
		expect(splitFrontmatter("---\na: 1\nbody\n").body).toBe("---\na: 1\nbody\n");
	});
});
