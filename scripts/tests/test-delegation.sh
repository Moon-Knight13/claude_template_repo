#!/usr/bin/env bash
# Deterministic tests for the delegation ladder (delegate-local.sh + local-health.sh)
# against a mock Ollama server — no real model or GPU needed.
#
# Usage: bash scripts/tests/test-delegation.sh
# Exit: 0 all pass, 1 otherwise.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(dirname "$HERE")"
PORT="${MOCK_PORT:-18434}"
TMP="$(mktemp -d)"
trap 'stop_mock; rm -rf "$TMP"' EXIT

export LOCAL_MODEL_ENABLED=true
export LOCAL_MODEL_ENDPOINT="http://127.0.0.1:$PORT"
export LOCAL_MODEL_MODEL="qwen2.5-coder:7b"
export LOCAL_MODEL_FAST_MODEL="qwen2.5-coder:7b"
export MODEL_ROUTE_LOG="$TMP/route-log.jsonl"
export LOCAL_MODEL_PROBE_TIMEOUT=8

MOCK_PID=""
pass=0
fail=0

start_mock() { # mode [extra env as K=V ...]
  local mode="$1"; shift
  env MOCK_MODE="$mode" MOCK_PORT="$PORT" "$@" python3 "$HERE/mock-ollama.py" &
  MOCK_PID=$!
  for _ in $(seq 1 50); do
    curl -sf --connect-timeout 1 "http://127.0.0.1:$PORT/api/tags" >/dev/null 2>&1 && return 0
    sleep 0.1
  done
  echo "FATAL: mock server did not start" >&2
  exit 1
}

stop_mock() {
  [[ -n "$MOCK_PID" ]] && { kill "$MOCK_PID" 2>/dev/null; wait "$MOCK_PID" 2>/dev/null; }
  MOCK_PID=""
}

check() { # name expected_exit stderr_pattern actual_exit stderr_file
  local name="$1" want_exit="$2" pattern="$3" got_exit="$4" errfile="$5"
  if [[ "$got_exit" != "$want_exit" ]]; then
    echo "FAIL $name: exit $got_exit (want $want_exit); stderr: $(cat "$errfile")"
    fail=$((fail + 1))
  elif [[ -n "$pattern" ]] && ! grep -q "$pattern" "$errfile"; then
    echo "FAIL $name: stderr missing '$pattern'; got: $(cat "$errfile")"
    fail=$((fail + 1))
  else
    echo "PASS $name"
    pass=$((pass + 1))
  fi
}

delegate() { # health_cache_name args... (prompt passed by caller); echoes exit code
  local cache="$1"; shift
  LOCAL_HEALTH_CACHE="$TMP/$cache.json" \
    bash "$SCRIPTS/delegate-local.sh" "$@" >"$TMP/out" 2>"$TMP/err"
  echo $?
}

# ── 1. Route gate: high-risk task never reaches the endpoint ────────────────
rc="$(delegate route-gate security high 1 "review auth flow")"
check "route-gate-high-risk" 3 "escalate:route:" "$rc" "$TMP/err"

# ── 2. Endpoint down: route-model's liveness fallback escalates, no hang ────
rc="$(delegate ep-down docs low 1 "update readme")"
check "endpoint-down" 3 "escalate:route:local_unreachable_fallback" "$rc" "$TMP/err"

# ── 3. Model not pulled ──────────────────────────────────────────────────────
start_mock missing
rc="$(delegate model-missing docs low 1 "update readme")"
check "model-missing" 3 "escalate:health:model_missing" "$rc" "$TMP/err"
stop_mock

# ── 4. Model too slow (health probe measures ~2 tps, min is 5) ──────────────
start_mock lowtps
rc="$(delegate low-tps docs low 1 "update readme")"
check "too-slow" 3 "escalate:health:too_slow" "$rc" "$TMP/err"
stop_mock

# ── 5. Prompt exceeds model context window ───────────────────────────────────
start_mock success MOCK_CTX=512
big_prompt="$(head -c 30000 /dev/zero | tr '\0' 'x')"
rc="$(delegate ctx-overflow docs low 1 "$big_prompt")"
check "context-overflow" 3 "escalate:context_overflow" "$rc" "$TMP/err"
stop_mock

# ── 6. Empty / whitespace output rejected ────────────────────────────────────
start_mock empty
rc="$(delegate empty-out docs low 1 "update readme")"
check "empty-output" 3 "escalate:empty_output" "$rc" "$TMP/err"
stop_mock

# ── 7. Degenerate (repetitive junk) output rejected ──────────────────────────
start_mock degenerate
rc="$(delegate degen-out docs low 1 "update readme")"
check "degenerate-output" 3 "escalate:degenerate_output" "$rc" "$TMP/err"
stop_mock

# ── 8. Generation timeout escalates AND poisons the health cache ────────────
start_mock slowgen
rc="$(LOCAL_MODEL_TIMEOUT=2 delegate slow-gen docs low 1 "update readme")"
check "generate-timeout" 3 "escalate:generate_timeout" "$rc" "$TMP/err"
# Second call with the same cache must short-circuit at health, not re-hang.
t0="$(date +%s)"
rc="$(delegate slow-gen docs low 1 "update readme")"
t1="$(date +%s)"
check "timeout-poisons-cache" 3 "escalate:health:generate_timeout" "$rc" "$TMP/err"
if (( t1 - t0 > 5 )); then
  echo "FAIL timeout-poisons-cache-fast: took $((t1 - t0))s, should short-circuit"
  fail=$((fail + 1))
else
  pass=$((pass + 1)); echo "PASS timeout-poisons-cache-fast"
fi
stop_mock

# ── 9. Happy path: local output returned, success logged ────────────────────
start_mock success
rc="$(delegate happy docs low 1 "write an add function")"
check "happy-path" 0 "" "$rc" "$TMP/err"
if grep -q "def add" "$TMP/out"; then
  pass=$((pass + 1)); echo "PASS happy-path-output"
else
  fail=$((fail + 1)); echo "FAIL happy-path-output: $(cat "$TMP/out")"
fi
if jq -e 'select(.event == "delegation" and .outcome == "success")' "$MODEL_ROUTE_LOG" >/dev/null; then
  pass=$((pass + 1)); echo "PASS route-log-success-entry"
else
  fail=$((fail + 1)); echo "FAIL route-log-success-entry"
fi
stop_mock

# ── 10. Every escalation was logged with a reason ────────────────────────────
esc_logged="$(jq -s '[.[] | select(.event == "delegation" and .outcome == "escalate")] | length' "$MODEL_ROUTE_LOG")"
if (( esc_logged >= 8 )); then
  pass=$((pass + 1)); echo "PASS escalations-logged ($esc_logged entries)"
else
  fail=$((fail + 1)); echo "FAIL escalations-logged: only $esc_logged entries"
fi

echo
echo "== $pass passed, $fail failed =="
(( fail == 0 ))
