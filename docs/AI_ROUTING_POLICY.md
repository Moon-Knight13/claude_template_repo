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

### Path A — Shell script (used by Claude Code and CI automation)

`scripts/route-model.sh <task_type> <risk_level> <changed_file_count>`

Returns a colon-separated string: `provider:model:reason`

If `provider=local`, call the local model directly:
```bash
bash scripts/ask-local.sh "<prompt>"
```

`scripts/ask-local.sh` wraps the Ollama API at `$LOCAL_MODEL_ENDPOINT/api/generate`. It respects `LOCAL_MODEL_MODEL` and `LOCAL_MODEL_ENDPOINT` environment variables.

### Path B — MCP tool (optional, for tool-based routing)

Copy `.claude/settings.json.example` to `.claude/settings.json` to register the local Ollama MCP server. Claude Code will then have a `local_llm` tool available and can call the local model as a native tool without shell script invocation.

See `.claude/settings.json.example` for configuration details.

## Confidence and Fallback
If local output is low confidence or local endpoint is unavailable, route to Claude. The shell script automatically falls back to `claude:...:local_unreachable_fallback` if the endpoint check fails.

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
