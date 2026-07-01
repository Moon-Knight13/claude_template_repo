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
2. Run: `result=$(bash scripts/route-model.sh "<task_type>" "<risk_level>" "<changed_file_count>")`
3. Extract provider: `provider=$(echo "$result" | cut -d: -f1)`
4. If `provider=local`: complete the task by calling `bash scripts/ask-local.sh "<prompt>"` via the Bash tool and return the result.
5. If `provider=claude` or local endpoint unreachable (`local_unreachable_fallback`): proceed in this session normally.

Routing decisions are logged to `.ai/route-log.jsonl` for analysis.

## Hard Escalation Triggers
Escalate to Claude if any condition is true:
1. Task risk is high.
2. Change touches auth, secrets, or firewall/networking.
3. Change spans more than 8 files.
4. Local endpoint is unavailable.
5. Test failures persist after one local attempt.

## Guardrails
- Never place credentials or tokens in repository files.
- Keep Claude auth in mounted user config outside workspace files.
- Run quality checks before merge: pre-commit, semgrep, gitleaks, CI checks.
- Respect repository protections and required checks.

## Style
Default response style should be concise and precise.
