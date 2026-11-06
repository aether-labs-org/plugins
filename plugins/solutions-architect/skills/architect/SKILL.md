---
name: architect
description: >
  Runs the solutions-architect workflow for an AWS workload end to end - discovery, requirements,
  design decisions, draw.io views, list-price estimate, Terraform, documentation, review - keeping
  state in architecture/manifest.json and checking each gate. Use to design, architect or propose
  a solution on AWS, or to resume or check an architecture workspace; not for one-off questions.
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

0. **Size first.** A one-off question with no deliverable ("SNS or EventBridge for this?") is a
   consultation, not a project: answer it as rule R6 of
   `${CLAUDE_PLUGIN_ROOT}/skills/design/references/discussion.md` says (options, gains and
   losses, recommendation with confidence, what would change it), create no workspace, and offer
   to open one.
1. Look for `architecture/manifest.json` (or the `docs_path` the user names).
2. If it does not exist, **do not ask anything yet**. Copy
   `${CLAUDE_PLUGIN_ROOT}/skills/architect/assets/manifest.json` to `architecture/manifest.json`
   with the defaults - artifact language: the language of the conversation, Terraform directory
   `infra`, region `sa-east-1` as a placeholder - and mark them `Source: default` where the
   discovery framing or the requirements record them. The `requirements` batch confirms the
   region (and a recovery region if DR matters); the `discovery` stage asks the open questions.
3. After **every** write to the manifest, validate it:

   ```bash
   python3 ${CLAUDE_PLUGIN_ROOT}/scripts/validate_manifest.py architecture/manifest.json
   ```

   Line 1 is `manifest<TAB>correctness<TAB>pass|fail<TAB>summary`. On `fail`, fix the entries it
   lists before doing anything else.

Field reference: `references/manifest-schema.md`. Stages and gates: `references/workflow.md`.

## 2. The loop

Read `stage` from the manifest, then:

1. **Check the previous gate** in `gates`. If it is not `pass` or `skipped`, finish that stage
   first. A pre-v0.3 workspace has no `gates.discovery` at all: record it as `skipped` first
   (section 2b), then continue; it is not a reason to run `discovery`.
2. **Invoke the stage skill** with the Skill tool:

   | Stage | Skill |
   |---|---|
   | `discovery` | `solutions-architect:discovery` |
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

## 2b. Workspaces from before v0.3

A manifest with no `gates.discovery` whose `stage` is later than `discovery` was made by v0.2.
Record `gates.discovery = {"status": "skipped", "at": "<YYYY-MM-DD>", "notes": "workspace
created before v0.3"}`, validate, and carry on from the current `stage`. **Never send it back to
`discovery`**; the `review` lists the skipped gate as a risk. Offer discovery only if the user
asks for it.

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
