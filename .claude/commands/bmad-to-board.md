# /bmad-to-board — Turn a BMAD decomposition into board issues

Bridge BMAD planning to the Kanban board: read the latest Task-Decomposition
artifact and create an epic plus its stories as GitHub issues on the project board.

## Preconditions

- The board exists (`.ai/project.env` present). If not, tell the user to run
  `APPLY=true bash scripts/bootstrap-project.sh` first.
- A BMAD Task-Decomposition artifact exists (e.g. under `.ai/`). If the user has
  not produced one, suggest running `/bmad` through the Task Decomposition stage.

## Instructions

1. Locate the decomposition. Ask the user for the path if it is ambiguous;
   otherwise use the most recent decomposition artifact in `.ai/`.

2. Parse it into one **epic** (the overall goal) and N **stories** (the discrete
   tasks). For each story, capture: title, the As-a/I-need/So-that framing when
   available, acceptance criteria, and a rough `task_type` / `risk_level` /
   `changed_file_count` estimate.

3. Create the epic issue:
   `gh issue create --label epic --title "[Epic] <goal>" --body "<summary + outcome>"`
   Note its number `E`.

4. For each story, in order:
   - Suggest a Route: `route=$(bash scripts/suggest-route.sh <task_type> <risk> <files>)`
   - Create it:
     `gh issue create --label story --title "[Story] <title>" --body "<story + gherkin AC + Parent epic: #E>"`
   - Add it to the board and set its fields:
     ```
     bash scripts/board.sh add <n>
     bash scripts/board.sh set-field <n> "BMAD Stage" "Task Decomposition"
     bash scripts/board.sh set-field <n> Route "$route"
     ```
   - Do NOT add `agent-ready` automatically — leave triage to the human. Mention
     which stories you would mark ready.

5. Update the epic body's child-story checklist with the created `#numbers`
   (`gh issue edit E --body ...`), and add the epic to the board with
   `bash scripts/board.sh add E` and `set-field E "BMAD Stage" "Task Decomposition"`.

6. Report a summary table: issue #, title, suggested Route. Remind the user that
   marking a card **Ready + `agent-ready`** is what makes it claimable via
   `/next-issue`, and complex cards should keep `Route=Human`.

See `docs/KANBAN_WORKFLOW.md` for the full flow.
