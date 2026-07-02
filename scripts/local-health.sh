#!/usr/bin/env bash
# Local model health probe — answers "can the local model take work right now?"
# Checks: endpoint reachable, model present, context window size, generation speed.
# Results are cached (LOCAL_HEALTH_TTL) so routine delegation pays zero probe cost.
#
# Used by delegate-local.sh as a preflight gate; safe to run standalone.
#
# Usage: local-health.sh [--refresh] [<model>]
#   --refresh  ignore the cache and re-probe
#   <model>    model to check (default: $LOCAL_MODEL_MODEL)
# Output: one JSON object on stdout:
#   {"ts":..,"healthy":..,"reachable":..,"model":..,"model_present":..,
#    "context_length":..,"tps":..,"reason":".."}
# Exit: 0 healthy, 1 not healthy (reason field says why).
set -euo pipefail

LOCAL_MODEL_ENDPOINT="${LOCAL_MODEL_ENDPOINT:-http://host.docker.internal:11434}"
LOCAL_MODEL_MODEL="${LOCAL_MODEL_MODEL:-qwen2.5-coder:7b}"
LOCAL_HEALTH_CACHE="${LOCAL_HEALTH_CACHE:-.ai/local-health.json}"
LOCAL_HEALTH_TTL="${LOCAL_HEALTH_TTL:-300}"           # seconds a probe result stays valid
LOCAL_MODEL_MIN_TPS="${LOCAL_MODEL_MIN_TPS:-5}"       # below this tokens/sec the model is "too slow"
LOCAL_MODEL_PROBE_TIMEOUT="${LOCAL_MODEL_PROBE_TIMEOUT:-45}"  # max seconds for the speed probe

REFRESH=false
MODEL="$LOCAL_MODEL_MODEL"
for arg in "$@"; do
  case "$arg" in
    --refresh) REFRESH=true ;;
    *) MODEL="$arg" ;;
  esac
done

mkdir -p "$(dirname "$LOCAL_HEALTH_CACHE")"

emit() { # healthy reachable model_present context_length tps reason
  jq -n --argjson ts "$(date +%s)" \
        --argjson healthy "$1" --argjson reachable "$2" \
        --arg model "$MODEL" --argjson model_present "$3" \
        --argjson context_length "$4" --argjson tps "$5" --arg reason "$6" \
        '{ts:$ts,healthy:$healthy,reachable:$reachable,model:$model,
          model_present:$model_present,context_length:$context_length,
          tps:$tps,reason:$reason}' | tee "$LOCAL_HEALTH_CACHE"
  [[ "$1" == "true" ]] && exit 0 || exit 1
}

# Serve from cache when fresh and for the same model.
if [[ "$REFRESH" != "true" && -f "$LOCAL_HEALTH_CACHE" ]]; then
  now="$(date +%s)"
  cached_ts="$(jq -r '.ts // 0' "$LOCAL_HEALTH_CACHE" 2>/dev/null || echo 0)"
  cached_model="$(jq -r '.model // ""' "$LOCAL_HEALTH_CACHE" 2>/dev/null || echo "")"
  if [[ "$cached_model" == "$MODEL" ]] && (( now - cached_ts < LOCAL_HEALTH_TTL )); then
    cat "$LOCAL_HEALTH_CACHE"
    [[ "$(jq -r '.healthy' "$LOCAL_HEALTH_CACHE")" == "true" ]] && exit 0 || exit 1
  fi
fi

# 1. Reachable?
if ! tags="$(curl -sfS --connect-timeout 2 --max-time 5 "$LOCAL_MODEL_ENDPOINT/api/tags" 2>/dev/null)"; then
  emit false false false 0 0 "unreachable"
fi

# 2. Model present? Exact match, or ":latest" resolution when no tag was given.
if ! jq -e --arg m "$MODEL" \
     '.models[]? | select(.name == $m or .name == ($m + ":latest")
        or (($m | contains(":") | not) and (.name | split(":")[0]) == $m))' \
     <<<"$tags" >/dev/null; then
  emit false true false 0 0 "model_missing"
fi

# 3. Context window (any *context_length key in model_info; 0 if unknown).
show="$(curl -sfS --max-time 10 "$LOCAL_MODEL_ENDPOINT/api/show" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg m "$MODEL" '{model:$m}')" 2>/dev/null || echo '{}')"
context_length="$(jq -r '[.model_info // {} | to_entries[]
  | select(.key | endswith("context_length")) | .value] | first // 0' <<<"$show")"

# 4. Speed probe: tiny bounded generation; tokens/sec from eval stats.
probe="$(curl -sfS --max-time "$LOCAL_MODEL_PROBE_TIMEOUT" "$LOCAL_MODEL_ENDPOINT/api/generate" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg m "$MODEL" \
      '{model:$m, prompt:"Reply with the single word: ready", stream:false,
        options:{num_predict:16}}')" 2>/dev/null)" || \
  emit false true true "$context_length" 0 "probe_timeout"

tps="$(jq -r 'if (.eval_duration // 0) > 0
  then ((.eval_count // 0) * 1000000000 / .eval_duration | floor)
  else 0 end' <<<"$probe")"

if (( tps < LOCAL_MODEL_MIN_TPS )); then
  emit false true true "$context_length" "$tps" "too_slow"
fi

emit true true true "$context_length" "$tps" "ok"
