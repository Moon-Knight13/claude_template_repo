#!/usr/bin/env bash
# Validate that all day-0 setup steps are complete.
#
# Auth-first: the two browser logins (gh, claude) are the ONLY manual steps —
# everything else is applied automatically by scripts/setup-day0.sh on container
# start (and on every re-run). This script therefore reports the auth gates
# first; while gh is unauthenticated, the gh-dependent items report SKIP (not
# FAIL) so the output has exactly one root-cause error and one fix command.
#
# States:
#   OK    configured
#   FAIL  needs action (listed hint) — the only state that fails the run
#   SKIP  blocked on an earlier auth gate; fixes itself once you log in
#   WARN  optional feature unavailable (never fails the run)
#
# Run again after each step — exits 0 only when nothing FAILs.
set -euo pipefail

PASS=0
FAIL=0
SKIP=0
WARN=0

check() {
    local description="$1"
    local result="$2"  # "pass" | "fail" | "skip" | "warn"
    local hint="$3"

    case "$result" in
        pass)
            echo "  OK  $description"
            ((PASS++)) || true
            ;;
        skip)
            echo " SKIP $description (blocked: $hint)"
            ((SKIP++)) || true
            ;;
        warn)
            echo " WARN $description"
            echo "      -> $hint"
            ((WARN++)) || true
            ;;
        *)
            echo " FAIL $description"
            echo "      -> $hint"
            ((FAIL++)) || true
            ;;
    esac
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

# ── Auth gates ────────────────────────────────────────────────────────────────
# The only manual day-0 steps. Everything below "Setup" self-heals via
# scripts/setup-day0.sh once these pass.
echo "Auth gates (the only manual steps — browser OAuth, no tokens on disk)"

# 1. No token in the environment — checked BEFORE gh auth, because an env token
# makes `gh auth status` report "authenticated" via the token and would mask
# the browser-OAuth state this template requires.
if [[ -n "${GITHUB_TOKEN:-}${GH_TOKEN:-}" ]]; then
    check "No GitHub token in environment" "fail" \
        "Unset GITHUB_TOKEN/GH_TOKEN (check .env, host shell profile, devcontainer config) — this template uses gh browser OAuth so tokens never sit in env vars where any process can read them."
else
    check "No GitHub token in environment" "pass" ""
fi

# 2. gh authenticated via browser OAuth. Gates every gh-dependent item below.
GH_AUTHED=false
if gh auth status >/dev/null 2>&1; then
    GH_AUTHED=true
    check "gh CLI authenticated (browser OAuth)" "pass" ""
else
    check "gh CLI authenticated (browser OAuth)" "fail" \
        "Run in your terminal: gh auth login --hostname github.com --git-protocol https --web -s project  — then: gh auth setup-git  — then re-run: bash scripts/setup-day0.sh"
fi

# 3. GitHub Projects scope (needed to create/manage the Kanban board).
# Match the quoted 'project' scope token — an unanchored "project" also matches
# the read-only 'read:project' scope, which cannot create/manage the board.
GH_SCOPE=false
if [[ "$GH_AUTHED" == "true" ]]; then
    if gh auth status 2>&1 | grep -qF "'project'"; then
        GH_SCOPE=true
        check "gh has Projects scope" "pass" ""
    else
        check "gh has Projects scope" "fail" \
            "Grant it with: gh auth refresh -s project  — then re-run: bash scripts/setup-day0.sh"
    fi
else
    check "gh has Projects scope" "skip" "gh not authenticated"
fi

# 4. Claude CLI authenticated (browser login; credentials live in the config
# volume, never in the repo).
if ! command -v claude >/dev/null 2>&1; then
    check "Claude CLI authenticated" "fail" \
        "claude CLI not found — rebuild the devcontainer (it installs Claude Code on start)."
elif claude auth status 2>/dev/null | grep -qE '"loggedIn":[[:space:]]*true'; then
    check "Claude CLI authenticated" "pass" ""
else
    check "Claude CLI authenticated" "fail" \
        "Run in your terminal: claude auth login  (browser OAuth)"
fi

# ── Setup (auto-applied by scripts/setup-day0.sh) ────────────────────────────
echo ""
echo "Setup (auto-applied by scripts/setup-day0.sh on container start / re-run)"

# 5. CODEOWNERS populated with real owner
# Ignore comment lines: the placeholder legitimately appears in the file's header
# comments, so only real owner rules should be scanned for the unreplaced default.
if [[ -f ".github/CODEOWNERS" ]] && ! grep -v '^[[:space:]]*#' .github/CODEOWNERS | grep -q "@your-org/your-team"; then
    check "CODEOWNERS customized with real owners" "pass" ""
else
    check "CODEOWNERS customized with real owners" "fail" \
        "Run: bash scripts/setup-day0.sh  (derives the owner from the git remote; or edit .github/CODEOWNERS by hand)"
fi

# 6. .env file exists
if [[ -f ".env" ]]; then
    check ".env file exists" "pass" ""
else
    check ".env file exists" "fail" \
        "Run: bash scripts/setup-day0.sh  (copies .env.example — then review the values)"
fi

# 7. .claude/settings.json exists (MCP routing configured)
if [[ -f ".claude/settings.json" ]]; then
    check ".claude/settings.json exists (MCP routing)" "pass" ""
else
    check ".claude/settings.json exists (MCP routing)" "fail" \
        "Run: bash scripts/setup-day0.sh  (copies the example — then update model and endpoint if needed)"
fi

# 8. Claude plugins installed (all 5 required plugins)
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

# 9. GitHub bootstrap has been run (completion marker written by
# bootstrap-github-settings.sh). setup-day0.sh applies it once gh is authed.
if [[ -f ".ai/bootstrap-completed" ]]; then
    check "GitHub settings bootstrapped" "pass" ""
elif [[ "$GH_AUTHED" == "true" ]]; then
    check "GitHub settings bootstrapped" "fail" \
        "Run: bash scripts/setup-day0.sh  (applies the ruleset; needs repo admin)"
else
    check "GitHub settings bootstrapped" "skip" "gh not authenticated"
fi

# 10. Kanban board bootstrapped. setup-day0.sh applies it once gh has the
# project scope.
if [[ -f ".ai/project-bootstrap-completed" ]]; then
    check "Kanban board bootstrapped" "pass" ""
elif [[ "$GH_AUTHED" == "true" && "$GH_SCOPE" == "true" ]]; then
    check "Kanban board bootstrapped" "fail" \
        "Run: bash scripts/setup-day0.sh  (creates the Project board)"
else
    check "Kanban board bootstrapped" "skip" "gh not authenticated or missing project scope"
fi

# ── Optional ──────────────────────────────────────────────────────────────────
echo ""
echo "Optional"

# 11. Ollama (host-side and optional — a WARN, never a FAIL: it cannot be
# installed from inside the container, and day-0 must be able to go green with
# just the two logins).
LOCAL_MODEL_ENABLED="${LOCAL_MODEL_ENABLED:-true}"
if [[ "$LOCAL_MODEL_ENABLED" == "true" ]]; then
    LOCAL_MODEL_ENDPOINT="${LOCAL_MODEL_ENDPOINT:-http://host.docker.internal:11434}"
    if curl --silent --fail --connect-timeout 2 "$LOCAL_MODEL_ENDPOINT" >/dev/null 2>&1; then
        check "Ollama reachable at $LOCAL_MODEL_ENDPOINT" "pass" ""
    else
        check "Ollama reachable at $LOCAL_MODEL_ENDPOINT" "warn" \
            "Optional local routing. Install + pull (https://ollama.com; ollama pull qwen2.5-coder:7b), then bind to 0.0.0.0 so the container can reach it (default 127.0.0.1 is loopback-only). See docs/TEMPLATE_GUIDE.md 'Bind Ollama so the container can reach it' — read the security disclaimer first. Or set LOCAL_MODEL_ENABLED=false in .env."
    fi
else
    echo "  --  Ollama check skipped (LOCAL_MODEL_ENABLED=false)"
fi

echo ""
echo "Results: ${PASS} ok, ${FAIL} failed, ${SKIP} skipped, ${WARN} warnings"

if [[ $SKIP -gt 0 ]]; then
    echo "SKIP items unblock themselves — fix the auth FAILs above, then re-run: bash scripts/setup-day0.sh"
fi

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi

echo "All day-0 steps complete."
