# /route-task — Explicit Model Routing

Invoke the CLAUDE.md Task Routing Protocol explicitly. Use this when you want to consciously decide whether a task should use the local model or Claude.

## Instructions

1. If the user hasn't described the task yet, ask: "What task do you want to route?"

2. Classify the task using these dimensions:
   - **task_type**: one of `format`, `docs`, `tiny-refactor`, `rename`, `simple-test`, `architecture`, `security`, `deep-debug`, `cross-cutting`
   - **risk_level**: `low`, `medium`, or `high`
   - **changed_file_count**: estimated number of files that will change

3. Run the routing decision via Bash:
   ```bash
   bash scripts/route-model.sh "<task_type>" "<risk_level>" "<changed_file_count>"
   ```

4. Parse the output (`provider:model:reason`) and explain the decision:
   - Show which provider was chosen and why
   - If `local_unreachable_fallback`: note that Ollama is not running and Claude is being used as a fallback

5. Execute based on the routing:
   - **If `provider=local`**: Call `bash scripts/ask-local.sh "<full task prompt>"` and return the result
   - **If `provider=claude`**: Proceed in this session normally, applying the task

6. After completing the task, show the routing log entry from `.ai/route-log.jsonl` so the user can see the decision was recorded.

## Hard escalation overrides (from CLAUDE.md)

Always route to Claude regardless of classification if:
- Task touches auth, secrets, or firewall/networking
- Change spans more than 8 files
- Local endpoint is unavailable
- Test failures persist after one local attempt
