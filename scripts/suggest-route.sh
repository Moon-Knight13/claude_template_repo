#!/usr/bin/env bash
# suggest-route.sh — map a task's shape to a board Route (Human | Claude | Local).
#
# Single source of routing truth: this defers to scripts/route-model.sh (the same
# logic CLAUDE.md uses) so the board's Route field never drifts from policy.
#
#   Human  — complex/high-risk work an agent should not auto-drive
#            (architecture, security, deep-debug, cross-cutting, or risk=high)
#   Local  — simple work route-model.sh sends to the local model
#   Claude — everything else (agentic work for a Claude session)
#
# Usage:
#   scripts/suggest-route.sh <task_type> <risk_level> <changed_file_count>
# Prints exactly one of: Human | Claude | Local
set -euo pipefail

TASK_TYPE="${1:-unknown}"
RISK_LEVEL="${2:-low}"
CHANGED_FILES="${3:-1}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Complex or high-risk work stays with a human orchestrator.
if [[ "$RISK_LEVEL" == "high" ]] || [[ "$TASK_TYPE" =~ ^(architecture|security|deep-debug|cross-cutting)$ ]]; then
  echo "Human"
  exit 0
fi

# Otherwise let route-model.sh decide local vs. Claude.
result="$(bash "$HERE/route-model.sh" "$TASK_TYPE" "$RISK_LEVEL" "$CHANGED_FILES")"
provider="${result%%:*}"

if [[ "$provider" == "local" ]]; then
  echo "Local"
else
  echo "Claude"
fi
