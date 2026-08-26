#!/usr/bin/env bash
# check-explainer-drift.sh — fail a commit that changes the architecture without
# updating the visual briefing that describes it.
#
# CLAUDE.md's Guardrails require docs/explainer/index.html to be updated in the
# SAME PR when the architecture, routing, security gates, or component set
# change. That rule lived only as prose, which makes it exactly the kind of
# boundary this template has been moving into mechanisms: a paragraph is
# followed when someone remembers it, and the explainer is the one artefact a
# non-technical reader is pointed at, so silent drift there misinforms the
# audience least able to detect it.
#
# Scope is deliberately narrow — the files that change what the template IS, not
# every file. A docs typo or a new test should not demand a diagram edit.
#
# Run by pre-commit against staged files; also runnable by hand against a range:
#   bash scripts/check-explainer-drift.sh                 # staged changes
#   bash scripts/check-explainer-drift.sh origin/main...  # a branch's changes
set -euo pipefail

EXPLAINER="docs/explainer/index.html"

# Governing surfaces: what the agent may do, how work is routed, which gates run.
GOVERNING_RE='^(\.devcontainer/|\.claude/settings\.json$|\.claude/hooks/|\.claude/agents/|\.github/workflows/|scripts/route-model\.sh$|scripts/delegate-local\.sh$|scripts/suggest-route\.sh$|\.semgrep\.yml$|\.gitleaks\.toml$|template\.conf$)'

if [[ $# -gt 0 ]]; then
    changed="$(git diff --name-only "$@")"
    context="the range $*"
else
    changed="$(git diff --cached --name-only)"
    context="the staged changes"
fi

[[ -n "$changed" ]] || exit 0

drifted="$(grep -E "$GOVERNING_RE" <<<"$changed" || true)"
[[ -n "$drifted" ]] || exit 0

if grep -qxF "$EXPLAINER" <<<"$changed"; then
    exit 0
fi

# The explainer may legitimately not need a change — a pinned-version bump in the
# Dockerfile does not alter the architecture. Say how to proceed rather than just
# refusing, so the escape is deliberate instead of the check being deleted.
cat >&2 <<MSG
$EXPLAINER was not updated, but $context touches files that define the
template's architecture, routing, or security gates:

$(sed 's/^/  /' <<<"$drifted")

CLAUDE.md requires the explainer to be updated in the same change: it is the
briefing non-technical readers are pointed at, and it is published via GitHub
Pages, so drift there is invisible to the people least able to spot it.

Either update $EXPLAINER, or - if this genuinely does not change what the
template is, such as a pinned version bump - record that in the commit message
and re-run with:

  SKIP=explainer-drift git commit ...
MSG
exit 1
