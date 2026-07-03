#!/usr/bin/env bash
# Validate that all manual day-0 setup steps are complete.
# Run after cloning to see what still needs to be done.
# Run again after each step — exits 0 only when everything is configured.
set -euo pipefail

PASS=0
FAIL=0

check() {
    local description="$1"
    local result="$2"  # "pass" or "fail"
    local hint="$3"

    if [[ "$result" == "pass" ]]; then
        echo "  OK  $description"
        ((PASS++)) || true
    else
        echo " FAIL $description"
        echo "      -> $hint"
        ((FAIL++)) || true
    fi
}

echo "Day-0 Setup Validation"
echo "======================"

# Day-0 checks target repos *derived* from this template; the pristine template
# itself fails them by design (placeholder CODEOWNERS, no .env, no markers).
# is_template_repo() lives in the shared helper so setup-day0.sh reuses it.
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1090,SC1091
source "$_SCRIPT_DIR/lib/template-detect.sh"

if is_template_repo; then
    echo "  --  This is the template repo itself — day-0 checks are not applicable."
    echo "      They validate repos derived from the template."
    echo "      To run the full checklist anyway: DAY0_FORCE_FULL=1 bash scripts/check-day0.sh"
    exit 0
fi

# 1. CODEOWNERS populated with real owner
# Ignore comment lines: the placeholder legitimately appears in the file's header
# comments, so only real owner rules should be scanned for the unreplaced default.
if [[ -f ".github/CODEOWNERS" ]] && ! grep -v '^[[:space:]]*#' .github/CODEOWNERS | grep -q "@your-org/your-team"; then
    check "CODEOWNERS customized with real owners" "pass" ""
else
    check "CODEOWNERS customized with real owners" "fail" \
        "Edit .github/CODEOWNERS and replace '@your-org/your-team' with your GitHub username or team."
fi

# 2. .env file exists
if [[ -f ".env" ]]; then
    check ".env file exists" "pass" ""
else
    check ".env file exists" "fail" \
        "Run: cp .env.example .env  — then review and update the values."
fi

# 3. .claude/settings.json exists (MCP routing configured)
if [[ -f ".claude/settings.json" ]]; then
    check ".claude/settings.json exists (MCP routing)" "pass" ""
else
    check ".claude/settings.json exists (MCP routing)" "fail" \
        "Run: cp .claude/settings.json.example .claude/settings.json  — then update model and endpoint if needed."
fi

# 4. GitHub bootstrap has been run (completion marker written by bootstrap-github-settings.sh)
if [[ -f ".ai/bootstrap-completed" ]]; then
    check "GitHub settings bootstrapped" "pass" ""
else
    check "GitHub settings bootstrapped" "fail" \
        "Run: APPLY=false bash scripts/bootstrap-github-settings.sh (dry-run), then: APPLY=true bash scripts/bootstrap-github-settings.sh"
fi

# 5. Claude plugins installed (all 5 required plugins)
_installed_plugins=$(claude plugin list 2>/dev/null || echo "")
_all_plugins_ok=true
for _p in skill-creator frontend-design code-review superpowers commit-commands; do
    if ! echo "$_installed_plugins" | grep -q "${_p}"; then
        _all_plugins_ok=false
        break
    fi
done
if [[ "$_all_plugins_ok" == "true" ]]; then
    check "All Claude plugins installed" "pass" ""
else
    check "All Claude plugins installed" "fail" \
        "Run: bash scripts/install-claude-plugins.sh  (or restart the devcontainer to re-run postStartCommand)"
fi

# 6. gh authenticated via browser OAuth (no tokens in env vars or repo files —
# gh keeps the OAuth token in its own config volume and acts as git's
# credential helper)
if gh auth status >/dev/null 2>&1; then
    check "gh CLI authenticated (browser OAuth)" "pass" ""
else
    check "gh CLI authenticated (browser OAuth)" "fail" \
        "Run in your terminal: gh auth login --hostname github.com --git-protocol https --web  — then: gh auth setup-git"
fi
if [[ -n "${GITHUB_TOKEN:-}${GH_TOKEN:-}" ]]; then
    check "No GitHub token in environment" "fail" \
        "Unset GITHUB_TOKEN/GH_TOKEN — this template uses gh browser OAuth so tokens never sit in env vars where any process can read them."
else
    check "No GitHub token in environment" "pass" ""
fi

# 7. GitHub Projects scope granted (needed to create/manage the Kanban board)
# Match the quoted 'project' scope token — an unanchored "project" also matches the
# read-only 'read:project' scope, which cannot create/manage the board.
if gh auth status 2>&1 | grep -qF "'project'"; then
    check "gh has Projects scope" "pass" ""
else
    check "gh has Projects scope" "fail" \
        "Grant it with: gh auth refresh -s project"
fi

# 8. Kanban board bootstrapped
if [[ -f ".ai/project-bootstrap-completed" ]]; then
    check "Kanban board bootstrapped" "pass" ""
else
    check "Kanban board bootstrapped" "fail" \
        "Run: APPLY=true bash scripts/bootstrap-project.sh"
fi

# 9. Ollama (optional — warn only if LOCAL_MODEL_ENABLED=true)
LOCAL_MODEL_ENABLED="${LOCAL_MODEL_ENABLED:-true}"
if [[ "$LOCAL_MODEL_ENABLED" == "true" ]]; then
    LOCAL_MODEL_ENDPOINT="${LOCAL_MODEL_ENDPOINT:-http://host.docker.internal:11434}"
    if curl --silent --fail --connect-timeout 2 "$LOCAL_MODEL_ENDPOINT" >/dev/null 2>&1; then
        check "Ollama reachable at $LOCAL_MODEL_ENDPOINT" "pass" ""
    else
        check "Ollama reachable at $LOCAL_MODEL_ENDPOINT" "fail" \
            "Install + pull (https://ollama.com; ollama pull qwen2.5-coder:7b), then bind to 0.0.0.0 so the container can reach it (default 127.0.0.1 is loopback-only). See docs/TEMPLATE_GUIDE.md 'Bind Ollama so the container can reach it' — read the security disclaimer first."
    fi
else
    echo "  --  Ollama check skipped (LOCAL_MODEL_ENABLED=false)"
fi

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi

echo "All day-0 steps complete."
