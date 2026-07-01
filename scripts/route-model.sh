#!/usr/bin/env bash
# Routing decision script — outputs provider:model:reason to stdout and appends a JSON log entry.
# Used by:
#   - CLAUDE.md Task Routing Protocol (Claude Code reads the output and calls ask-local.sh accordingly)
#   - CI scripts and automation that need risk-based routing logic
# Not called automatically by Claude Code — Claude must invoke it explicitly per CLAUDE.md instructions.
set -euo pipefail

TASK_TYPE="${1:-unknown}"
RISK_LEVEL="${2:-low}"
CHANGED_FILES="${3:-1}"

LOCAL_MODEL_ENABLED="${LOCAL_MODEL_ENABLED:-false}"
LOCAL_MODEL_ENDPOINT="${LOCAL_MODEL_ENDPOINT:-http://host.docker.internal:11434}"
LOCAL_MODEL_MODEL="${LOCAL_MODEL_MODEL:-local-default}"
LOCAL_MODEL_FAST_MODEL="${LOCAL_MODEL_FAST_MODEL:-qwen2.5-coder:1.5b-base}"
LOCAL_MODEL_FAST_TASK_TYPES="${LOCAL_MODEL_FAST_TASK_TYPES:-format,docs,tiny-refactor,rename,simple-test}"
CLAUDE_MODEL="${CLAUDE_MODEL:-claude-default}"
FORCE_CLAUDE="${FORCE_CLAUDE:-false}"
FORCE_LOCAL="${FORCE_LOCAL:-false}"
MODEL_ROUTE_LOG="${MODEL_ROUTE_LOG:-.ai/route-log.jsonl}"

mkdir -p "$(dirname "$MODEL_ROUTE_LOG")"

choose_local=false
reason=""
prefer_fast_local=false

if [[ "$RISK_LEVEL" == "low" && "$CHANGED_FILES" =~ ^[0-9]+$ ]] && (( CHANGED_FILES <= 2 )); then
  prefer_fast_local=true
fi

IFS=',' read -r -a FAST_TASKS <<< "$LOCAL_MODEL_FAST_TASK_TYPES"
for t in "${FAST_TASKS[@]}"; do
  if [[ "$TASK_TYPE" == "$t" ]]; then
    prefer_fast_local=true
    break
  fi
done

# Classify risk/complexity/size before local availability so the `reason` is
# meaningful regardless of whether local routing is on. This keeps `high_risk`
# and `complex_task` visible to consumers (e.g. suggest-route.sh) — all of these
# branches route to Claude anyway, exactly as `local_disabled` would.
if [[ "$FORCE_CLAUDE" == "true" ]]; then
  choose_local=false
  reason="force_claude"
elif [[ "$FORCE_LOCAL" == "true" ]]; then
  choose_local=true
  reason="force_local"
elif [[ "$RISK_LEVEL" == "high" ]]; then
  choose_local=false
  reason="high_risk"
elif [[ "$TASK_TYPE" =~ ^(architecture|security|deep-debug|cross-cutting)$ ]]; then
  choose_local=false
  reason="complex_task"
elif [[ "$CHANGED_FILES" =~ ^[0-9]+$ ]] && (( CHANGED_FILES > 8 )); then
  choose_local=false
  reason="large_change_set"
elif [[ "$LOCAL_MODEL_ENABLED" != "true" ]]; then
  choose_local=false
  reason="local_disabled"
else
  choose_local=true
  reason="simple_task"
fi

if [[ "$choose_local" == "true" ]]; then
  if curl --silent --fail --connect-timeout 2 "$LOCAL_MODEL_ENDPOINT" >/dev/null 2>&1; then
    provider="local"
    if [[ "$prefer_fast_local" == "true" ]]; then
      model="$LOCAL_MODEL_FAST_MODEL"
      reason="${reason}_fast_path"
    else
      model="$LOCAL_MODEL_MODEL"
    fi
  else
    provider="claude"
    model="$CLAUDE_MODEL"
    reason="local_unreachable_fallback"
  fi
else
  provider="claude"
  model="$CLAUDE_MODEL"
fi

printf '{"provider":"%s","model":"%s","reason":"%s","task_type":"%s","risk":"%s","changed_files":"%s"}\n' \
  "$provider" "$model" "$reason" "$TASK_TYPE" "$RISK_LEVEL" "$CHANGED_FILES" >> "$MODEL_ROUTE_LOG"

printf '%s\n' "$provider:$model:$reason"
