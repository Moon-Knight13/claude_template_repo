# /run-epic — Orchestrate an epic's stories across subagents

Take ownership of an epic and drive its child stories to completion, fanning work
out to subagents without collisions. This is the "human picks up an epic and
manages subagents" flow.

## Usage

`/run-epic <epic-issue#>`

## Instructions

1. Take epic ownership (so two people don't fan out the same epic):
   `bash scripts/board.sh claim <epic#>` on the epic issue. If it returns exit
   code 3, someone already owns it — stop and report who.

2. Read the epic (`gh issue view <epic#>`) and collect its child stories from the
   checklist / linked issues. For each child, read its board **Route** and skip
   any that are already assigned, `wip`, or not `Ready` + `agent-ready`.

3. Decide concurrency:
   - **Parallel** (default when stories are independent): launch one subagent per
     ready story using the Agent tool with `isolation: "worktree"` so each works
     in its own git worktree and they cannot clobber each other's files. Give
     each subagent the story number and instruct it to follow the `/next-issue`
     steps for that specific issue (claim → branch → implement → PR → move to
     In Review).
   - **Sequential**: if stories share files or have ordering dependencies, hand
     back the claimed list and work them one at a time via `/next-issue`.

4. Respect Route per story: `Route=Human` stories are surfaced to the user rather
   than auto-run; `Route=Local` stories are run via the `local-worker` agent
   (subagent type `local-worker`), which delegates through
   `scripts/delegate-local.sh` and reports `VERDICT: OK` or `VERDICT: ESCALATE`.
   On ESCALATE, re-run that story with a normal Claude subagent — the escalation
   reason is already logged to `.ai/route-log.jsonl`; don't retry locally.

5. As stories reach In Review, keep the epic's checklist updated. When all
   children are Done, move the epic: `bash scripts/board.sh move <epic#> done`
   (or In Review if it needs a final integration PR), and report status.

6. If you claimed the epic but cannot proceed, `bash scripts/board.sh release
   <epic#>` so someone else can take it.

**Golden rule:** each story is claimed exactly once; never touch an assigned or
In-Progress card. The board is the single source of who's on what.
