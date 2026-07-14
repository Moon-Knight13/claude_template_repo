#!/usr/bin/env bash
# Guard: fail if .github/CODEOWNERS still carries the template placeholder
# (@your-org/your-team) as an active owner rule in a *derived* repo.
#
# Why this exists: the weekly repository-audit already catches an unfilled
# CODEOWNERS, but only on its Monday schedule — a placeholder reintroduced by a
# manual edit could sit broken for up to a week. While the owner is a
# non-existent team, branch protection's "require code owner review" silently
# has no effect. This runs the same check on every commit (pre-commit hook) and
# in CI (invoked by scripts/validate-template.sh), so a regression fails fast at
# its source instead of on the next scheduled audit.
#
# Template-aware: the pristine template repo intentionally ships the placeholder
# as the forcing function for consumers (see the .github/CODEOWNERS header and
# repository-audit.yml), so the check is a no-op there — reuses the shared
# is_template_repo() helper, mirroring check-day0.sh.
# Comment-aware: the placeholder legitimately appears in the file's header
# comments, so only non-comment (active) owner rules are scanned.
set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1090,SC1091
source "$_SCRIPT_DIR/lib/template-detect.sh"

CODEOWNERS_FILE=".github/CODEOWNERS"
PLACEHOLDER="@your-org/your-team"

if is_template_repo; then
    echo "OK: template repo — CODEOWNERS placeholder is intentional; skipping."
    exit 0
fi

if [[ ! -f "$CODEOWNERS_FILE" ]]; then
    echo "FAIL: $CODEOWNERS_FILE is missing."
    exit 1
fi

# Strip comment lines before scanning so a documented placeholder in the header
# does not trip the guard; only active owner rules count.
if grep -v '^[[:space:]]*#' "$CODEOWNERS_FILE" | grep -q "$PLACEHOLDER"; then
    echo "FAIL: $CODEOWNERS_FILE still contains placeholder '$PLACEHOLDER' in an active rule."
    echo "      Branch protection's 'require code owner review' has no effect until this is a real owner."
    echo "      Fix: bash scripts/setup-day0.sh   (derives the owner from the git remote),"
    echo "      or edit $CODEOWNERS_FILE by hand to use real GitHub users/teams."
    exit 1
fi

echo "OK: $CODEOWNERS_FILE has no placeholder owners."
