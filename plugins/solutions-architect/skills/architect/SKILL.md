---
name: architect
description: >
  Runs the solutions-architect workflow for an AWS workload end to end - requirements, design
  decisions, draw.io views, list-price estimate, Terraform, documentation, review - keeping state
  in architecture/manifest.json and checking each stage's gate. Use when someone asks to design,
  architect or propose a solution on AWS, or to resume or check an architecture workspace.
allowed-tools: Bash(python3 ${CLAUDE_PLUGIN_ROOT}/scripts/validate_manifest.py *)
---

# Architect

You run the method; the stage skills produce the content. **Never skip a gate silently** and
**never apply anything to a cloud account** - this plugin is read-only (decision D13); a hook
denies mutating commands, and the answer to "deploy it" is the exact command for a human or a
pipeline to run. The hook is a best-effort layer, not the guarantee (that is the read-only IAM
role) - never try to work around a denied command by wrapping, piping or scripting it differently;
hand the command to the user instead.

## 1. Find or create the workspace

1. Look for `architecture/manifest.json` (or the `docs_path` the user names).
2. If it does not exist, ask only what you cannot infer, in one message: primary region (and a
   secondary one if DR matters), artifact language (default `pt-BR`), Terraform directory
   (default `infra`). Then copy `${CLAUDE_PLUGIN_ROOT}/skills/architect/assets/manifest.json`
   to `architecture/manifest.json` and fill those fields.
3. After **every** write to the manifest, validate it:

   ```bash
   python3 ${CLAUDE_PLUGIN_ROOT}/scripts/validate_manifest.py architecture/manifest.json
   ```

   Line 1 is `manifest<TAB>correctness<TAB>pass|fail<TAB>summary`. On `fail`, fix the entries it
   lists before doing anything else.

Field reference: `references/manifest-schema.md`. Stages and gates: `references/workflow.md`.

## 2. The loop

Read `stage` from the manifest, then:

1. **Check the previous gate** in `gates`. If it is not `pass`, finish that stage first.
2. **Invoke the stage skill** with the Skill tool:

   | Stage | Skill |
   |---|---|
   | `requirements` | `solutions-architect:requirements` |
   | `design` | `solutions-architect:design` |
   | `diagram` | `solutions-architect:diagram` |
   | `finops-compare`, `finops-estimate` | `solutions-architect:finops` |
   | `iac` | `solutions-architect:iac` |
   | `docs` | `solutions-architect:docs` |
   | `review` | `solutions-architect:review` |

3. **Check the exit gate** exactly as `references/workflow.md` states it for that stage. A gate
   is `pass` only when every condition in its row is true - not when the skill says it is done.
4. **Record** `gates.<stage> = {"status": "pass|fail|skipped", "at": "<YYYY-MM-DD>", "notes": "..."}`,
   advance `stage` to the next one, validate the manifest, and tell the user in two lines what
   was produced and what comes next.

## 3. Entering mid-way

The user may start anywhere ("just estimate this Terraform"). Run the requested stage. For each
earlier stage without a `pass` gate, record it as `skipped` with a note, and list those skips in
your reply - they are warnings, not blockers.

## 4. Status

When asked for status, print one table: stage, gate status, date, artifact path. Then the output
of `validate_manifest.py` (its warnings list NFRs no accepted ADR covers yet).

## 5. Dependencies

The stage skills delegate AWS service knowledge to the `aws-core` plugin and its AWS MCP Server
(`aws___search_documentation`, `aws___get_regional_availability`). If those tools are missing,
say so once and continue; never answer a service-availability question from memory.
