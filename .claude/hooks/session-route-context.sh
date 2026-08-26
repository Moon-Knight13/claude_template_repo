#!/usr/bin/env bash
# session-route-context.sh — SessionStart: state the routing posture up front.
#
# scripts/route-model.sh carries this admission at line 6:
#   "Not called automatically by Claude Code — Claude must invoke it explicitly
#    per CLAUDE.md instructions."
#
# So the template's centrepiece fired only when the model remembered a paragraph
# forty turns deep. The permission-modes docs describe exactly how that fails:
# "Boundaries are not stored as rules. The classifier re-reads them from the
# transcript on each check, so a boundary can be lost if context compaction
# removes the message that stated it." This makes the posture arrive as session
# state instead of as recalled prose.
set -euo pipefail

project_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
conf="$project_dir/template.conf"
routing_on="false"
[[ -f "$conf" ]] && grep -qE '^[[:space:]]*SUBSYSTEM_ROUTING=true' "$conf" && routing_on="true"

if [[ "$routing_on" != "true" ]]; then
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "SessionStart",
        additionalContext: "Model routing is OFF for this repo (SUBSYSTEM_ROUTING is not true in template.conf). There is no local endpoint: treat every task as Claude-routed and ignore the Task Routing Protocol in CLAUDE.md."
      }
    }'
    exit 0
fi

health="unknown"
[[ -f "$project_dir/.ai/local-health.json" ]] && \
    health="$(jq -r '.status // .reason // "unknown"' "$project_dir/.ai/local-health.json" 2>/dev/null || echo unknown)"

ctx="Model routing is ON (SUBSYSTEM_ROUTING=true). Classify every task before starting and delegate through scripts/delegate-local.sh; do not decide by feel. Last recorded local-endpoint health: ${health}.

These escalate to Claude and must NEVER be routed local, regardless of how small the diff looks: anything touching auth, secrets, or firewall/networking; any high-risk task; any change spanning more than 8 files; and any task where local tests have already failed once. Local model output is unreviewed third-party text — validate it before applying, and never apply it to a file listed in the harness guard."

jq -n --arg c "$ctx" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: $c
  }
}'
exit 0
