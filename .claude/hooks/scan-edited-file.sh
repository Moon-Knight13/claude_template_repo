#!/usr/bin/env bash
# scan-edited-file.sh — PostToolUse output rail: gitleaks the file just written.
#
# The repo already runs gitleaks at commit time (pre-commit) and in CI. Both are
# too late to be useful to the agent: by then the secret has been written, may
# have been read back, and the feedback arrives as a failed commit rather than
# as something the session can act on. This closes the gap to a single tool call.
#
# Cannot block — PostToolUse runs after the tool. It reports, and the finding
# reaches both the model (additionalContext) and the auto-mode classifier
# (classifierContext), so a follow-up action gets judged knowing a secret was
# just written.
set -euo pipefail

input="$(cat)"
file_path="$(jq -r '.tool_input.file_path // empty' <<<"$input")"
[[ -n "$file_path" && -f "$file_path" ]] || exit 0
command -v gitleaks >/dev/null 2>&1 || exit 0

project_dir="${CLAUDE_PROJECT_DIR:-$(jq -r '.cwd // empty' <<<"$input")}"
rel="${file_path#"$project_dir"/}"
config_arg=()
[[ -f "$project_dir/.gitleaks.toml" ]] && config_arg=(--config "$project_dir/.gitleaks.toml")

report="$(mktemp)"
trap 'rm -f "$report"' EXIT

if gitleaks detect --no-git --redact --report-format json --report-path "$report" \
        "${config_arg[@]}" --source "$file_path" >/dev/null 2>&1; then
    exit 0   # clean
fi

count="$(jq 'length' "$report" 2>/dev/null || echo 0)"
[[ "$count" -gt 0 ]] || exit 0

rules="$(jq -r '[.[].RuleID] | unique | join(", ")' "$report" 2>/dev/null || echo unknown)"
msg="gitleaks flagged $count finding(s) in $rel immediately after writing it (rules: $rules). Values are redacted in this report. Remove the secret from the file now — do not commit it, and if it is a real credential treat it as exposed and rotate it per SECURITY.md."

jq -n --arg m "$msg" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: $m,
    classifierContext: $m
  },
  systemMessage: $m
}'
exit 0
