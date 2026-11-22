#!/usr/bin/env bash
# guard-harness-files.sh — PreToolUse guard over the files that govern the agent.
#
# Why this is a hook and not a permissions.deny rule: deny rules are absolute and
# unoverridable ("no scope can remove one that another scope added"), and this
# repo's own /firewall-allow command legitimately edits
# .devcontainer/init-firewall.sh, while the template repo edits every file below
# as its product. A deny rule would break both. A hook can be conditional.
#
# The boundary is real despite the escape hatch: CLAUDE_ALLOW_HARNESS_EDIT is
# read from the hook process's inherited environment, which comes from the
# Claude Code process. A model cannot set it mid-session, because each Bash tool
# call gets a fresh shell whose exports die with it. Only whoever launched the
# session can set it.
#
# Contract: stdin is the PreToolUse JSON; exit 0 with a permissionDecision, or
# exit 0 silently to fall through to the normal permission flow.
set -euo pipefail

input="$(cat)"
file_path="$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$input")"
[[ -n "$file_path" ]] || exit 0

project_dir="${CLAUDE_PROJECT_DIR:-$(jq -r '.cwd // empty' <<<"$input")}"
rel="${file_path#"$project_dir"/}"

# Governing files: anything that decides what the agent may do, how it is
# routed, or which gates run. Editing these from inside a session is how a
# drifting or steered agent would quietly widen its own boundary.
is_governing() {
    case "$1" in
        .claude/settings.json|.claude/settings.json.example) return 0 ;;
        .claude/hooks/*|.claude/agents/*|.claude/commands/*)  return 0 ;;
        .mcp.json|CLAUDE.md|.templatesyncignore)              return 0 ;;
        .devcontainer/*)                                      return 0 ;;
        .github/workflows/*)                                  return 0 ;;
        .semgrep.yml|.gitleaks.toml|.pre-commit-config.yaml)  return 0 ;;
        scripts/route-model.sh|scripts/suggest-route.sh)      return 0 ;;
        scripts/delegate-local.sh|scripts/local-health.sh)    return 0 ;;
        scripts/validate-template.sh)                         return 0 ;;
        *) return 1 ;;
    esac
}

is_governing "$rel" || exit 0

if [[ "${CLAUDE_ALLOW_HARNESS_EDIT:-0}" == "1" ]]; then
    jq -n --arg f "$rel" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        additionalContext: ("Editing governing file \($f) — permitted because CLAUDE_ALLOW_HARNESS_EDIT=1 is set for this session. State in the commit message why the guardrail changed.")
      }
    }'
    exit 0
fi

jq -n --arg f "$rel" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: ("\($f) governs what this agent is allowed to do, so a session cannot edit it in passing. If changing it IS the task, restart Claude Code with CLAUDE_ALLOW_HARNESS_EDIT=1 in the environment — a deliberate act by the person running the session, which a tool call cannot fake. See docs/THREAT_MODEL.md.")
  }
}'
exit 0
