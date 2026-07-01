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

# 1. CODEOWNERS populated with real owner
if [[ -f ".github/CODEOWNERS" ]] && ! grep -q "@your-org/your-team" .github/CODEOWNERS; then
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

# 5. Claude plugins installed (all 7 required plugins)
_installed_plugins=$(claude plugin list 2>/dev/null || echo "")
_all_plugins_ok=true
for _p in skill-creator frontend-design code-review superpowers github commit-commands semgrep; do
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

# 6. GitHub token set (required for github plugin)
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    check "GITHUB_TOKEN is set" "pass" ""
else
    check "GITHUB_TOKEN is set" "fail" \
        "Set GITHUB_TOKEN in your .env file or host shell profile. Create at: https://github.com/settings/tokens"
fi

# 7. Ollama (optional — warn only if LOCAL_MODEL_ENABLED=true)
LOCAL_MODEL_ENABLED="${LOCAL_MODEL_ENABLED:-true}"
if [[ "$LOCAL_MODEL_ENABLED" == "true" ]]; then
    LOCAL_MODEL_ENDPOINT="${LOCAL_MODEL_ENDPOINT:-http://host.docker.internal:11434}"
    if curl --silent --fail --connect-timeout 2 "$LOCAL_MODEL_ENDPOINT" >/dev/null 2>&1; then
        check "Ollama reachable at $LOCAL_MODEL_ENDPOINT" "pass" ""
    else
        check "Ollama reachable at $LOCAL_MODEL_ENDPOINT" "fail" \
            "Install Ollama on your host: https://ollama.com — then run: ollama pull qwen2.5-coder:7b"
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
