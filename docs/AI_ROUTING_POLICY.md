# AI Routing Policy

## Purpose
Reduce paid-token usage safely by routing simple tasks to local models while preserving quality and security.

## Default Routing Matrix
- local model:
  - formatting
  - boilerplate generation
  - straightforward documentation edits
  - simple test scaffolding
  - low-risk refactors
- Claude model:
  - architecture and design decisions
  - security, auth, and policy changes
  - firewall and infrastructure updates
  - ambiguous debugging
  - cross-cutting refactors

## Invocation Paths

Routing posture is injected at session start by
`.claude/hooks/session-route-context.sh`, so it no longer depends on the model
recalling a paragraph mid-session. `scripts/route-model.sh` still records at line
6 that it "must be invoked explicitly" — that remains true of the per-task call
below, and the hook is what guarantees the policy is in context to make it. This
matters because a boundary stated only in the transcript can be lost to context
compaction; the same reasoning is why credential rules are `permissions.deny`
entries rather than prose.

### Path A — Shell script (used by Claude Code and CI automation)

Preferred entry point — the delegation lifecycle wrapper:

```bash
bash scripts/delegate-local.sh <task_type> <risk_level> <changed_file_count> "<prompt>"
# or pass "-" and pipe the prompt on stdin
```

It runs the full delegation ladder, escalating to Claude (exit 3,
`escalate:<reason>` on stderr) if any rung fails:

1. **Route decision** — `scripts/route-model.sh` (risk, task type, size, force flags, liveness).
2. **Health preflight** — `scripts/local-health.sh`: endpoint reachable, model pulled, recent tokens/sec above `LOCAL_MODEL_MIN_TPS`. Cached in `.ai/local-health.json` for `LOCAL_HEALTH_TTL` seconds, so routine calls cost no probe time.
3. **Context fit** — estimated prompt tokens + `LOCAL_MODEL_MAX_OUTPUT` must fit the model's context window (read from `/api/show`).
4. **Bounded generation** — hard `LOCAL_MODEL_TIMEOUT` wall clock and `num_predict` cap; a timeout poisons the health cache so the next task short-circuits to Claude.
5. **Output sanity** — empty or degenerate (highly repetitive) output is rejected.

Exit 0 means stdout holds the local model's output; every attempt (success or
escalation, with reason, duration, and tokens/sec) is appended to
`.ai/route-log.jsonl` for analysis.

Lower-level pieces remain available: `scripts/route-model.sh` (decision only,
returns `provider:model:reason`) and `scripts/ask-local.sh` (raw Ollama
`/api/generate` wrapper, no fallback). For subagent orchestration, the
`local-worker` agent (`.claude/agents/local-worker.md`) wraps this path and
reports a structured `VERDICT: OK | ESCALATE` to the orchestrator.

The ladder is covered by deterministic tests against a mock Ollama server:
`bash scripts/tests/test-delegation.sh`.

### Path B — MCP tool (optional, for tool-based routing)

Copy `.claude/settings.json.example` to `.claude/settings.json` to register the local Ollama MCP server. Claude Code will then have a `local_llm` tool available and can call the local model as a native tool without shell script invocation.

See `.claude/settings.json.example` for configuration details.

## Confidence and Fallback
If local output is low confidence or local endpoint is unavailable, route to Claude. `route-model.sh` automatically falls back to `claude:...:local_unreachable_fallback` if the endpoint check fails, and `delegate-local.sh` escalates (exit 3) on any ladder failure: `route:*`, `health:model_missing`, `health:too_slow`, `context_overflow`, `generate_timeout_or_error`, `empty_output`, `degenerate_output`. `route:*` escalations are policy decisions and must not be retried locally. Semantic quality remains the orchestrator's job: review local output before applying; if verification (tests/lint) fails after one local retry, redo the task on Claude.

**Those rungs are quality checks, not security checks.** `empty_output` and
`degenerate_output` measure unique word count — they catch a model that has
broken down, not one that has been tampered with. Fluent, non-degenerate,
backdoored output passes every rung with `VERDICT: OK`, and `/run-epic` will fan
that across parallel subagents. Nothing in the ladder inspects what the output
actually does.

## Privacy Rules
- Do not include secrets in prompts to local or remote models.
- Redact sensitive values when discussing logs or configs.

## Operational Rules
All generated changes must pass:
- pre-commit checks
- semgrep and gitleaks
- CI required checks

## Local Endpoint
Expected endpoint from devcontainer: host gateway on TCP 11434.
Configure with `LOCAL_MODEL_ENDPOINT` environment variable.

**The endpoint is unauthenticated, and the firewall explicitly permits it.**
`init-firewall.sh` ACCEPTs TCP 11434 to the host gateway, and Ollama ships no
authentication, so anything able to reach that gateway can serve responses this
repo will treat as model output. Combined with the rung-5 limitation above, that
makes local model output **unreviewed third-party code**: read it before you
apply it, and never apply it to a file the harness guard protects. Tracked as
finding A2 in [THREAT_MODEL.md](THREAT_MODEL.md); the fix is an authenticating
gateway in front of the endpoint so the agent never reaches raw inference.
