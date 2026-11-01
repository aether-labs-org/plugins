import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

export interface Vector {
	name: string;
	file: string;
	review_body: string;
	hash: string;
}

// Single source of truth, shared with the Python tests: <repo>/tests/fixtures/review-hash/vectors.json
const path = fileURLToPath(new URL("../../../../tests/fixtures/review-hash/vectors.json", import.meta.url));

export const vectors: Vector[] = JSON.parse(readFileSync(path, "utf8")) as Vector[];
