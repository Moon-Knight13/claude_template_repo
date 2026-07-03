#!/usr/bin/env bash
# Shared helper: detect whether the current repo is the pristine template
# itself (vs. a repo derived from it). Sourced by scripts/check-day0.sh and
# scripts/setup-day0.sh so the detection logic lives in exactly one place.
#
# Assumes the caller runs from the repo root (both callers are invoked as
# `bash scripts/<name>.sh`), so the offline fallback's relative paths resolve.

# is_template_repo — returns 0 (true) on the template repo, 1 (false) on a
# derived repo. DAY0_FORCE_FULL=1 forces the derived (full-checklist) treatment
# even on the template.
is_template_repo() {
    [[ "${DAY0_FORCE_FULL:-0}" == "1" ]] && return 1

    # Preferred: ask GitHub — authoritative when reachable.
    local is_template
    is_template=$(gh repo view --json isTemplate --jq '.isTemplate' 2>/dev/null || echo "")
    [[ "$is_template" == "true" ]] && return 0
    [[ "$is_template" == "false" ]] && return 1

    # Offline fallback: require BOTH the placeholder CODEOWNERS and the
    # template's own origin URL, so derived repos always get the full check.
    if [[ -f ".github/CODEOWNERS" ]] && grep -q "@your-org/your-team" .github/CODEOWNERS \
        && git remote get-url origin 2>/dev/null | grep -q "Moon-Knight13/claude_template_repo"; then
        return 0
    fi
    return 1
}
