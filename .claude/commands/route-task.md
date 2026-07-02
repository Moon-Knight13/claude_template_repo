# /route-task — Explicit Model Routing

Invoke the CLAUDE.md Task Routing Protocol explicitly. Use this when you want to consciously decide whether a task should use the local model or Claude.

## Instructions

1. If the user hasn't described the task yet, ask: "What task do you want to route?"

2. Classify the task using these dimensions:
   - **task_type**: one of `format`, `docs`, `tiny-refactor`, `rename`, `simple-test`, `architecture`, `security`, `deep-debug`, `cross-cutting`
   - **risk_level**: `low`, `medium`, or `high`
   - **changed_file_count**: estimated number of files that will change

3. Delegate through the lifecycle wrapper (it runs `route-model.sh` internally,
   then health preflight → context-fit check → bounded generation → output
   sanity):
   ```bash
   bash scripts/delegate-local.sh "<task_type>" "<risk_level>" "<changed_file_count>" - <<'PROMPT'
   <full task prompt>
   PROMPT
   ```

4. Act on the exit code:
   - **Exit 0**: stdout is the local model's output — validate it, then apply it.
   - **Exit 3**: stderr has `escalate:<reason>` — do the task in this session
     (Claude) and tell the user why it escalated. Common reasons:
     `route:high_risk`, `route:local_unreachable_fallback`,
     `health:model_missing`, `health:too_slow`, `context_overflow`,
     `generate_timeout_or_error`, `empty_output`, `degenerate_output`.
   - Never retry a `route:*` escalation locally — that class is a policy
     decision, not a transient failure.

5. For multi-step work, prefer spawning the `local-worker` agent
   (`.claude/agents/local-worker.md`) per subtask instead of calling the script
   inline — it validates, applies, runs checks, and reports OK/ESCALATE.

6. After completing the task, show the routing log entry from `.ai/route-log.jsonl` so the user can see the decision was recorded.

## Hard escalation overrides (from CLAUDE.md)

Always route to Claude regardless of classification if:
- Task touches auth, secrets, or firewall/networking
- Change spans more than 8 files
- Local endpoint is unavailable
- Test failures persist after one local attempt
