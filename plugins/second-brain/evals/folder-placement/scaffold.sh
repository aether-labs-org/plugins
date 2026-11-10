#!/usr/bin/env bash
# Seeds a clean pt-BR vault with Decisions and Meetings folders and one inbox clip that records a decision.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sb="$here/../../bin/sb"
"$sb" init --vault . --language pt-BR --folders - >/dev/null <<'FOLDERS'
[
  {"path": "Projects", "description": "Active efforts with a goal and an end date.",
   "conventions": "One note per project; link the notes that feed it. Move it to Archive/ when it ends."},
  {"path": "Areas", "description": "Ongoing responsibilities with no end date, such as health or finances.",
   "conventions": "One subfolder per area; notes describe the standard to maintain, not a task list."},
  {"path": "Resources", "description": "Concepts, entities and references reused across projects.",
   "conventions": "Atomic notes with one idea each; the file name is the concept."},
  {"path": "Decisions", "description": "One note per decision: context, options, choice, consequences.",
   "conventions": "Name the note after the decision; state the date and who decided; link the notes that informed it."},
  {"path": "Meetings", "description": "One note per meeting: date, attendees, what was discussed and agreed.",
   "conventions": "Name notes YYYY-MM-DD plus topic; link to decisions made instead of restating them."},
  {"path": "Archive", "description": "Inactive notes kept for reference.",
   "conventions": "Move notes here instead of deleting them."}
]
FOLDERS
cp "$here/../_fixtures/inbox-decision/"*.md _inbox/
