# Kanban & Agent Orchestration

A GitHub Project v2 board turns BMAD planning into trackable work that a human
orchestrator hands off to Claude sessions or local models — solo, or across a
team without agents stepping on each other. It is `gh`-CLI driven: no API keys,
no secrets, no Claude-in-CI. Claude acts through your interactive session and
`gh`, exactly as it does now.

## The board

Created per repo by `scripts/bootstrap-project.sh` — run automatically (best-effort)
by `scripts/setup-day0.sh` on container start once `gh` has the `project` scope; the
command below is the manual fallback.

| Surface | Values | Meaning |
|---------|--------|---------|
| **Status** (columns) | Backlog → Todo → Ready → In Progress → In Review → Done | The at-a-glance overview and delivery stage |
| **BMAD Stage** (field) | Discovery … Security & Release | Which planning stage a card came from (mostly on epics) |
| **Route** (field) | Human · Claude · Local | Who should work the card — derived from `scripts/route-model.sh` |
| `agent-ready` (label) | — | Card is triaged and may be claimed by an agent session |
| `wip` (label) + assignee | — | Card is claimed; a claim lock — **do not touch** |

**Route** is the orchestration surface. It is populated from the same routing
policy as CLAUDE.md via `scripts/suggest-route.sh`, so the board never disagrees
with how work is actually routed:

- `Human` — complex/high-risk (architecture, security, deep-debug, cross-cutting, risk=high).
- `Local` — simple work the local model handles (`scripts/ask-local.sh`).
- `Claude` — agentic work for a Claude session.

## One-time setup (day 0)

`scripts/setup-day0.sh` runs this automatically once `gh` is authenticated with the
`project` scope (re-run it after auth, or it fires on the next container start). To do
it by hand — or to grant the scope, which is interactive:

```bash
gh auth refresh -s project              # grant Projects scope to your CLI (interactive)
APPLY=true bash scripts/bootstrap-project.sh   # create board, fields, labels
```

`bootstrap-project.sh` is idempotent — re-run it any time; it reconciles rather
than duplicates. It writes `.ai/project.env`, which `scripts/board.sh` sources.

## Solo flow

1. **Plan** with `/bmad` through the Task Decomposition stage.
2. **Populate the board**: `/bmad-to-board` creates the epic + story issues,
   adds them to the board, and sets BMAD Stage + a suggested Route on each.
3. **Triage**: review each card, adjust Route, move the ones you want worked to
   **Ready**, and add `agent-ready`. Leave complex cards as `Route=Human`.
4. **Build**: `/next-issue` claims the top ready card, branches, implements, and
   opens a PR that closes the issue (card → In Review). Merge → move to Done.

## Team flow at scale

Everyone runs their own Claude Code session against the **shared per-repo board**.
Coordination is by construction:

- **Claim protocol.** `scripts/board.sh claim <n>` (used by `/next-issue`)
  self-assigns, adds `wip`, sets In Progress, then **re-reads** to confirm it is
  the sole assignee. If two sessions race, the loser releases and picks another
  card. A card is claimed exactly once.
- **The golden rule.** Never touch a card that is already assigned or In
  Progress. The assignee + `wip` + column tell you who is on what.
- **One branch per issue** (`issue-<n>-slug`) and **one PR per story** keep
  parallel work isolated; PRs use `Closes #<n>`.
- **Epic ownership.** `/run-epic <n>` claims the *epic* first, so two people
  don't fan out the same one. It then claims and distributes the child stories.
- **Parallel subagents** launched by `/run-epic` use git **worktrees**
  (`isolation: "worktree"`) so concurrent agents on one machine never clobber
  each other's files.

## The board CLI

`scripts/board.sh` is the single gh-native entry point (skills call it; you can
too):

```bash
bash scripts/board.sh add <n>                       # add issue, Status=Backlog
bash scripts/board.sh set-field <n> Route Claude    # set a field
bash scripts/board.sh move <n> in-review            # move a card
bash scripts/board.sh next                          # top Ready+agent-ready+unassigned
bash scripts/board.sh claim <n>                     # collision-safe claim
bash scripts/board.sh release <n>                   # undo a claim
```

## Why no CI automation?

Board writes are session-driven on purpose: it keeps the setup to two commands
with **zero stored secrets** and nothing to leak. The trade-off is that cards
move when you or a teammate act (or run `board.sh`), not automatically on GitHub
events. `/next-issue` and PR steps move the cards at the right moments.

## Related

- `docs/BMAD_WORKFLOW.md` — planning stages that feed the board.
- `docs/AI_ROUTING_POLICY.md` + `scripts/route-model.sh` — the routing policy the
  Route field mirrors.
- Commands: `/bmad-to-board`, `/next-issue`, `/run-epic`.
