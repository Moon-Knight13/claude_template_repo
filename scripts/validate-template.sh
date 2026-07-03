#!/usr/bin/env bash
# Self-contained template integrity validator.
# Run locally or in CI to verify the template is complete and consistent.
set -euo pipefail

PASS=0
FAIL=0

check() {
    local description="$1"
    local result="$2"
    local hint="${3:-}"
    if [[ "$result" == "pass" ]]; then
        echo "  OK  $description"
        ((PASS++)) || true
    else
        echo " FAIL $description"
        [[ -n "$hint" ]] && echo "      -> $hint"
        ((FAIL++)) || true
    fi
}

echo "Template Validation"
echo "==================="

# 1. Required files
echo ""
echo "[1] Required files:"
for f in \
    README.md SECURITY.md CLAUDE.md LICENSE \
    .gitignore .editorconfig .env.example \
    .gitleaks.toml .semgrep.yml .pre-commit-config.yaml \
    .github/CODEOWNERS \
    .github/workflows/ci.yml \
    .github/workflows/secret-scan.yml \
    .github/workflows/semgrep.yml \
    .github/workflows/container-scan.yml \
    .github/workflows/repository-audit.yml \
    .github/workflows/template-sync.yml \
    .templatesyncignore \
    .github/dependabot.yml \
    .github/pull_request_template.md \
    .devcontainer/devcontainer.json \
    .devcontainer/Dockerfile \
    .devcontainer/init-firewall.sh \
    .claude/settings.json.example \
    .claude/commands/bmad.md \
    .claude/commands/bmad-to-board.md \
    .claude/commands/next-issue.md \
    .claude/commands/run-epic.md \
    .claude/commands/day0-check.md \
    .claude/commands/route-task.md \
    .claude/commands/security-audit.md \
    .github/ISSUE_TEMPLATE/epic.yml \
    .github/ISSUE_TEMPLATE/user-story.yml \
    docs/TEMPLATE_GUIDE.md \
    docs/AI_ROUTING_POLICY.md \
    docs/BMAD_WORKFLOW.md \
    docs/KANBAN_WORKFLOW.md \
    docs/README.template.md \
    scripts/route-model.sh \
    scripts/ask-local.sh \
    scripts/suggest-route.sh \
    scripts/board.sh \
    scripts/check-day0.sh \
    scripts/validate-template.sh \
    scripts/bootstrap-github-settings.sh \
    scripts/bootstrap-project.sh \
    scripts/bootstrap-precommit.sh \
    scripts/bootstrap-bmad.sh \
    scripts/install-bmad.sh \
    scripts/install-caveman.sh \
    scripts/install-claude-plugins.sh \
    scripts/adopt-template-sync.sh \
    scripts/ci/README.md; do
    if [[ -f "$f" ]]; then
        check "$f" "pass"
    else
        check "$f" "fail" "File missing — add it or update this validator"
    fi
done

# 2. Script executable permissions
echo ""
echo "[2] Script permissions:"
while IFS= read -r -d '' script; do
    if [[ -x "$script" ]]; then
        check "$script is executable" "pass"
    else
        check "$script is executable" "fail" "Run: chmod +x $script"
    fi
done < <(find scripts -name "*.sh" -print0)

# 3. .claude/ template files are not gitignored
echo ""
echo "[3] Git-track check (.claude/ template files):"
# settings.local.json is intentionally NOT listed here — it is machine-local and
# gitignored so per-developer permissions don't propagate to derived repos.
for f in \
    .claude/commands/bmad.md \
    .claude/commands/bmad-to-board.md \
    .claude/commands/next-issue.md \
    .claude/commands/run-epic.md \
    .claude/commands/day0-check.md \
    .claude/commands/route-task.md \
    .claude/commands/security-audit.md \
    .claude/settings.json.example; do
    if [[ ! -f "$f" ]]; then
        check "$f is NOT gitignored" "fail" "File doesn't exist — create it first"
        continue
    fi
    if git check-ignore -q "$f" 2>/dev/null; then
        check "$f is NOT gitignored" "fail" "Update .gitignore — add !$f to allow this file"
    else
        check "$f is NOT gitignored" "pass"
    fi
done

# 4. YAML syntax
echo ""
echo "[4] YAML syntax:"
if command -v python3 &>/dev/null; then
    for yml in .github/workflows/*.yml .pre-commit-config.yaml .github/dependabot.yml; do
        if python3 -c "import yaml, sys; yaml.safe_load(open('$yml'))" 2>/dev/null; then
            check "$yml" "pass"
        else
            check "$yml" "fail" "Invalid YAML — run: python3 -c \"import yaml; yaml.safe_load(open('$yml'))\""
        fi
    done
else
    echo "  --  python3 not available; YAML syntax check skipped"
fi

# 5. Placeholder scan (only in files that should NOT have placeholders)
echo ""
echo "[5] Placeholder scan:"
# Scan content files only. Scripts, workflows, and command definitions legitimately
# reference these patterns as detection logic or setup instructions, not as unfilled
# placeholders — so they are excluded from this scan.
_placeholder_clean=true
while IFS= read -r -d '' f; do
    [[ "$f" == "./README.md" ]] && continue
    [[ "$f" == "./.github/CODEOWNERS" ]] && continue
    [[ "$f" == "./docs/README.template.md" ]] && continue
    if grep -qE '_TODO:|your-org/your-team|<!-- Replace' "$f" 2>/dev/null; then
        check "No placeholder in $f" "fail" "Unexpected template placeholder found — check the file"
        _placeholder_clean=false
    fi
done < <(find . -type f \( -name "*.md" -o -name "*.json" \) \
    ! -path "./.git/*" ! -path "./node_modules/*" \
    ! -path "./scripts/*" ! -path "./.github/workflows/*" ! -path "./.claude/commands/*" \
    ! -path "./_bmad/*" ! -path "./_bmad-output/*" ! -path "./.claude/skills/*" -print0)
if [[ "$_placeholder_clean" == "true" ]]; then
    check "No unexpected placeholders in tracked files" "pass"
fi

# 6. devcontainer.json postStartCommand scripts all exist
echo ""
echo "[6] devcontainer.json postStartCommand scripts:"
for script in \
    scripts/install-caveman.sh \
    scripts/install-bmad.sh \
    scripts/bootstrap-bmad.sh \
    scripts/bootstrap-precommit.sh \
    scripts/install-claude-plugins.sh; do
    if [[ -f "$script" ]]; then
        check "$script exists" "pass"
    else
        check "$script exists" "fail" "Referenced in devcontainer.json postStartCommand but missing"
    fi
done

# 7. ShellCheck (optional — skip gracefully if not installed)
echo ""
echo "[7] Shell script linting (shellcheck):"
if command -v shellcheck &>/dev/null; then
    while IFS= read -r -d '' script; do
        if shellcheck "$script" &>/dev/null; then
            check "shellcheck: $script" "pass"
        else
            check "shellcheck: $script" "fail" "Run: shellcheck $script"
        fi
    done < <(find scripts -name "*.sh" -print0)
else
    echo "  --  shellcheck not installed; skipping (apt-get install shellcheck)"
fi

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
echo ""

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi

echo "All template validation checks passed."
