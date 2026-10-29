# Conventions

<a id="no-console"></a>
### No console output in source

**Rule.** Code under `src/` does not call `console.log`; it uses the logger in `src/log.ts`.
**Why.** Console output is unstructured and cannot be filtered or traced.
**✓ / ✗.** ✓ `log.info("total", { items })`. ✗ `console.log("total", items)`.
**When it fails.** Replace the call with the logger; do not delete the information it carried.

<a id="file-size"></a>
### Source files stay under 300 lines

**Rule.** Source files under `src/` have at most 300 lines.
**Why.** Large files hide several responsibilities.
**✓ / ✗.** ✓ 140 lines. ✗ 600 lines.
**When it fails.** Split the file by responsibility.
