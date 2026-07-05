# Claude Workflow Contract

## Mission
Deliver secure, maintainable software with deterministic quality gates.

## Priority Order
1. Security
2. Correctness
3. Maintainability
4. Delivery speed
5. Token efficiency

## Model Routing
Use local model by default for low-risk tasks:
- formatting
- boilerplate
- straightforward docs updates
- low-risk single-purpose refactors

Use Claude for high-risk or ambiguous tasks:
- architecture or cross-cutting design
- security and auth changes
- infra or network configuration changes
- unclear root-cause debugging
- broad refactors across many files

## Task Routing Protocol

Before starting a task, determine the routing:

1. Classify: `task_type` (format|docs|tiny-refactor|rename|simple-test|architecture|security|deep-debug|cross-cutting), `risk_level` (low|medium|high), `changed_file_count`.
2. Delegate via the lifecycle wrapper (runs `route-model.sh`, then health preflight → context-fit → bounded generation → output sanity):
   `bash scripts/delegate-local.sh "<task_type>" "<risk_level>" "<changed_file_count>" "<prompt>"` (or `-` with the prompt on stdin).
3. Exit 0: stdout is the local model's result — validate before applying.
4. Exit 3: stderr has `escalate:<reason>` — proceed in this session (Claude) normally. Never retry `route:*` escalations locally.
5. When orchestrating subagents, run `Route=Local` subtasks through the `local-worker` agent (`.claude/agents/local-worker.md`); on `VERDICT: ESCALATE` redo the subtask with a Claude subagent.

Routing decisions and delegation outcomes (success/escalate, reason, duration, tokens/sec) are logged to `.ai/route-log.jsonl`. Local model health is cached in `.ai/local-health.json` (`scripts/local-health.sh`, TTL `LOCAL_HEALTH_TTL`).

## Hard Escalation Triggers
Escalate to Claude if any condition is true:
1. Task risk is high.
2. Change touches auth, secrets, or firewall/networking.
3. Change spans more than 8 files.
4. Local endpoint is unavailable.
5. Test failures persist after one local attempt.

## Kanban / Board
Work is tracked on a per-repo GitHub Project board (see `docs/KANBAN_WORKFLOW.md`).
- The board **Route** field (Human / Claude / Local) is the routing protocol made
  visible; it is derived from `scripts/route-model.sh` via `scripts/suggest-route.sh`. Keep them consistent.
- Agents pick up work with `/next-issue`, which claims a card collision-safely
  (`scripts/board.sh claim`: self-assign + `wip` + In Progress + re-check).
- Golden rule: never touch a card that is already assigned or In Progress. One
  branch and one PR (`Closes #<n>`) per story. Orchestrate epics with `/run-epic`.
- All board writes go through `scripts/board.sh` (gh-CLI, no secrets).

## Guardrails
- Never place credentials or tokens in repository files.
- Keep Claude auth in mounted user config outside workspace files.
- Run quality checks before merge: pre-commit, semgrep, gitleaks, CI checks.
- Respect repository protections and required checks.
- Keep `docs/explainer/index.html` in sync with `README.md` and `docs/`. It is a
  hand-authored visual briefing (the README is the source of truth); when the
  architecture, routing, security gates, or component set change, update the explainer in
  the same PR. It is self-contained — no external requests, works offline and via Pages.

## Style
Default response style should be concise and precise.
