#!/usr/bin/env bash
# Delegation lifecycle wrapper — the safe way to hand a subtask to the local model.
#
# Runs the full ladder: route decision -> health preflight -> context-fit check
# -> bounded generation -> output sanity checks. Any rung failing escalates to
# Claude (exit 3) with a machine-readable reason, so the orchestrator never
# blocks on a dead/slow/undersized local model and never accepts junk output.
#
# Usage:
#   delegate-local.sh <task_type> <risk_level> <changed_file_count> "<prompt>"
#   delegate-local.sh <task_type> <risk_level> <changed_file_count> -   # prompt on stdin
# Output:
#   exit 0 -> local model's response on stdout
#   exit 3 -> ESCALATE; "escalate:<reason>" on stderr (caller redoes task on Claude)
#   exit 1 -> usage error
# Every attempt (success or escalation) is appended to $MODEL_ROUTE_LOG.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TASK_TYPE="${1:-}"
RISK_LEVEL="${2:-}"
CHANGED_FILES="${3:-}"
if [[ -z "$TASK_TYPE" || -z "$RISK_LEVEL" || -z "$CHANGED_FILES" || $# -lt 4 ]]; then
  echo "Usage: delegate-local.sh <task_type> <risk_level> <changed_file_count> <prompt|-> " >&2
  exit 1
fi
shift 3

if [[ "$1" == "-" ]]; then
  PROMPT="$(cat)"
else
  PROMPT="$*"
fi

LOCAL_MODEL_ENDPOINT="${LOCAL_MODEL_ENDPOINT:-http://host.docker.internal:11434}"
LOCAL_MODEL_TIMEOUT="${LOCAL_MODEL_TIMEOUT:-120}"        # hard wall-clock cap per generation
LOCAL_MODEL_MAX_OUTPUT="${LOCAL_MODEL_MAX_OUTPUT:-2048}" # num_predict cap (tokens)
LOCAL_MODEL_MIN_TPS="${LOCAL_MODEL_MIN_TPS:-5}"
LOCAL_HEALTH_CACHE="${LOCAL_HEALTH_CACHE:-.ai/local-health.json}"
MODEL_ROUTE_LOG="${MODEL_ROUTE_LOG:-.ai/route-log.jsonl}"
mkdir -p "$(dirname "$MODEL_ROUTE_LOG")"

log_outcome() { # outcome reason model duration_ms tps
  jq -cn --arg event "delegation" --arg outcome "$1" --arg reason "$2" \
         --arg model "$3" --arg task_type "$TASK_TYPE" --arg risk "$RISK_LEVEL" \
         --arg changed_files "$CHANGED_FILES" \
         --argjson duration_ms "$4" --argjson tps "$5" \
         --argjson prompt_bytes "${#PROMPT}" \
    '{event:$event,outcome:$outcome,reason:$reason,model:$model,
      task_type:$task_type,risk:$risk,changed_files:$changed_files,
      duration_ms:$duration_ms,tps:$tps,prompt_bytes:$prompt_bytes}' \
    >> "$MODEL_ROUTE_LOG"
}

escalate() { # reason model
  log_outcome "escalate" "$1" "${2:-none}" 0 0
  echo "escalate:$1" >&2
  exit 3
}

# ── Rung 1: route decision (risk / task-type / size / force flags) ──────────
route="$(bash "$HERE/route-model.sh" "$TASK_TYPE" "$RISK_LEVEL" "$CHANGED_FILES")"
provider="${route%%:*}"
rest="${route#*:}"
model="${rest%%:*}"
route_reason="${rest#*:}"
if [[ "$provider" != "local" ]]; then
  escalate "route:$route_reason"
fi

# ── Rung 2: health preflight (exists? model pulled? fast enough lately?) ────
if ! health="$(bash "$HERE/local-health.sh" "$model")"; then
  escalate "health:$(jq -r '.reason' <<<"$health" 2>/dev/null || echo unknown)" "$model"
fi

# ── Rung 3: context-window fit (never send a prompt the model can't hold) ───
context_length="$(jq -r '.context_length // 0' <<<"$health")"
est_prompt_tokens=$(( ${#PROMPT} / 3 ))   # conservative ~3 chars/token for code
need_tokens=$(( est_prompt_tokens + LOCAL_MODEL_MAX_OUTPUT ))
if (( context_length > 0 && need_tokens > context_length )); then
  escalate "context_overflow:need=${need_tokens},have=${context_length}" "$model"
fi
num_ctx=$(( need_tokens < 4096 ? 4096 : need_tokens ))
if (( context_length > 0 && num_ctx > context_length )); then
  num_ctx=$context_length
fi

# ── Rung 4: bounded generation (hard timeout, capped output) ────────────────
start_ms="$(date +%s%3N)"
if ! resp="$(curl -sfS --max-time "$LOCAL_MODEL_TIMEOUT" "$LOCAL_MODEL_ENDPOINT/api/generate" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg model "$model" --arg prompt "$PROMPT" \
        --argjson num_predict "$LOCAL_MODEL_MAX_OUTPUT" --argjson num_ctx "$num_ctx" \
        '{model:$model, prompt:$prompt, stream:false,
          options:{num_predict:$num_predict, num_ctx:$num_ctx}}')" 2>/dev/null)"; then
  # A timeout here also poisons the health cache so the next call skips straight to Claude.
  jq -n --argjson ts "$(date +%s)" --arg model "$model" \
    '{ts:$ts,healthy:false,reachable:true,model:$model,model_present:true,
      context_length:0,tps:0,reason:"generate_timeout"}' > "$LOCAL_HEALTH_CACHE"
  escalate "generate_timeout_or_error" "$model"
fi
duration_ms=$(( $(date +%s%3N) - start_ms ))

output="$(jq -r '.response // ""' <<<"$resp")"
tps="$(jq -r 'if (.eval_duration // 0) > 0
  then ((.eval_count // 0) * 1000000000 / .eval_duration | floor)
  else 0 end' <<<"$resp")"

# ── Rung 5: output sanity (cheap junk detection before any token is spent
#            reviewing it; semantic review stays with the orchestrator) ──────
trimmed="$(tr -d '[:space:]' <<<"$output")"
if [[ -z "$trimmed" ]]; then
  escalate "empty_output" "$model"
fi
if (( ${#output} > 200 )); then
  unique_words="$(tr -s '[:space:]' '\n' <<<"$output" | sort -u | wc -l)"
  if (( unique_words < 5 )); then
    escalate "degenerate_output:unique_words=${unique_words}" "$model"
  fi
fi
if (( tps > 0 && tps < LOCAL_MODEL_MIN_TPS )); then
  # Output accepted, but mark the model degraded so the NEXT task escalates
  # immediately instead of waiting on a slow generation again.
  jq -n --argjson ts "$(date +%s)" --arg model "$model" --argjson tps "$tps" \
    '{ts:$ts,healthy:false,reachable:true,model:$model,model_present:true,
      context_length:0,tps:$tps,reason:"too_slow"}' > "$LOCAL_HEALTH_CACHE"
fi

log_outcome "success" "$route_reason" "$model" "$duration_ms" "$tps"
printf '%s\n' "$output"
