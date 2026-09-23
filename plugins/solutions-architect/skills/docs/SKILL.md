---
name: docs
description: >
  Assembles the architecture documentation of a solutions-architect workspace in Markdown -
  arc42-lite solution architecture document, one-page executive summary, risk register and
  roadmap - linking the artifacts instead of copying them, in the manifest language. Use when
  asked to document or write up an AWS architecture for stakeholders.
---

# Docs

Documentation **points at** the artifacts - requirements, ADRs, diagrams, estimate, IaC - and
never duplicates them, so it cannot drift from them. Everything is Markdown in the workspace
(`docs_path`, default `architecture/`), written in the manifest `language`; where the user
publishes it afterwards is their choice.

## Procedure

1. Read the manifest, `requirements.md`, the accepted ADRs, `diagrams/`, `finops/estimate.md` and
   `reports/iac-gate.json`. Note any stage whose gate is not `pass` - the documents must say so.
2. Write `architecture/README.md` from `assets/sad-arc42-lite.md`. Each section is a short
   paragraph plus links: requirements by id, decisions by ADR id, views by file (embed the
   exported SVG when it exists, otherwise link the `.drawio`), cost by the estimate.
3. Write `architecture/executive-summary.md` from `assets/executive-summary.md`: one page,
   no jargon, the monthly list price and the cost per business unit, the top three risks, the
   decisions that need a stakeholder's approval.
4. Write `architecture/risks.md` from `assets/risks.md`. Sources: ADR negative consequences,
   `not-estimated` cost lines, checkov suppressions, NFRs marked `TBD`, skipped gates.
5. When the solution ships in phases, add a roadmap section to `README.md`: phase, components
   (by manifest id), exit criterion.
6. Check every relative link resolves:

   ```bash
   python3 -c "import re,sys,os; d='architecture'; bad=[(f,l) for f in ('README.md','executive-summary.md','risks.md') for l in re.findall(r'\]\(([^)#]+)', open(os.path.join(d,f)).read()) if not l.startswith('http') and not os.path.exists(os.path.join(d,l))]; print(bad or 'links ok'); sys.exit(1 if bad else 0)"
   ```

## Exit gate

Every relative link resolves and the documents are in the manifest language.
