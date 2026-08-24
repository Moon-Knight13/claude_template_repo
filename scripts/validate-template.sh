#!/usr/bin/env bash
# Self-contained template integrity validator.
# Run locally or in CI to verify the template is complete and consistent.
#
# Checks are tiered. The always-required tier is the security baseline that
# justifies the template existing at all — devcontainer, secret scanning,
# semgrep, container scanning, CODEOWNERS, and the sync machinery itself. The
# optional tiers cover subsystems a derived repository may legitimately not
# want; each is skipped when it is switched off in template.conf.
#
# Before this was tiered, the required-file list was flat, so a derivative that
# deleted a subsystem it never used went red in CI and could not fix it locally
# (this validator is template-owned, so the next sync reverted the edit). See
# docs/TEMPLATE_GUIDE.md, "Optional subsystems".
set -euo pipefail

# shellcheck source=scripts/lib/subsystems.sh disable=SC1090,SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/subsystems.sh"

PASS=0
FAIL=0
SKIP=0

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

# require_files <subsystem|core> <file>...
# "core" is always checked. Anything else is checked only while that subsystem
# is enabled; when it is off the files are reported as skipped, never as missing.
require_files() {
    local subsystem="$1"
    shift
    if [[ "$subsystem" != "core" ]] && ! subsystem_enabled "$subsystem"; then
        echo "  --  ${subsystem} subsystem off in template.conf; skipping $# file(s)"
        SKIP=$((SKIP + $#))
        return 0
    fi
    local f
    for f in "$@"; do
        if [[ -f "$f" ]]; then
            check "$f" "pass"
        else
            check "$f" "fail" "File missing — add it, or switch the ${subsystem} subsystem off in template.conf"
        fi
    done
}

echo "Template Validation"
echo "==================="

# 1. Required files
echo ""
echo "[1] Required files (always):"
require_files core \
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
    template.conf \
    .github/dependabot.yml \
    .github/pull_request_template.md \
    .devcontainer/devcontainer.json \
    .devcontainer/Dockerfile \
    .devcontainer/init-firewall.sh \
    .claude/settings.json.example \
    .claude/commands/security-audit.md \
    docs/TEMPLATE_GUIDE.md \
    scripts/check-codeowners.sh \
    scripts/validate-template.sh \
    scripts/bootstrap-precommit.sh \
    scripts/install-claude-plugins.sh \
    scripts/lib/subsystems.sh \
    scripts/project-setup.sh \
    scripts/ci/README.md

echo ""
echo "[1a] Required files (local-model routing):"
require_files routing \
    docs/AI_ROUTING_POLICY.md \
    .claude/commands/route-task.md \
    scripts/route-model.sh \
    scripts/ask-local.sh

echo ""
echo "[1b] Required files (project board):"
require_files board \
    docs/KANBAN_WORKFLOW.md \
    .claude/commands/next-issue.md \
    .claude/commands/run-epic.md \
    .github/ISSUE_TEMPLATE/epic.yml \
    .github/ISSUE_TEMPLATE/user-story.yml \
    scripts/board.sh \
    scripts/suggest-route.sh \
    scripts/bootstrap-project.sh

echo ""
echo "[1c] Required files (BMAD):"
require_files bmad \
    docs/BMAD_WORKFLOW.md \
    .claude/commands/bmad.md \
    .claude/commands/bmad-to-board.md \
    scripts/install-bmad.sh \
    scripts/bootstrap-bmad.sh

echo ""
echo "[1d] Required files (caveman):"
require_files caveman \
    scripts/install-caveman.sh

echo ""
echo "[1e] Required files (day-0 provisioning):"
require_files day0 \
    .claude/commands/day0-check.md \
    scripts/check-day0.sh \
    scripts/setup-day0.sh \
    scripts/bootstrap-github-settings.sh

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
_track_targets=(.claude/commands/security-audit.md .claude/settings.json.example)
subsystem_enabled bmad && _track_targets+=(.claude/commands/bmad.md .claude/commands/bmad-to-board.md)
subsystem_enabled board && _track_targets+=(.claude/commands/next-issue.md .claude/commands/run-epic.md)
subsystem_enabled day0 && _track_targets+=(.claude/commands/day0-check.md)
subsystem_enabled routing && _track_targets+=(.claude/commands/route-task.md)

for f in "${_track_targets[@]}"; do
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
    # The seed README is placeholder-bearing by definition — it exists so a new
    # project has something to fill in. The template repo itself does not ship
    # this file, so this gate could only ever fire in derived repos, where it
    # flagged the seed as an unfilled placeholder on every run.
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
# postStartCommand tolerates a missing script only when its subsystem is off;
# the scripts it always runs must be present.
_poststart=(scripts/bootstrap-precommit.sh scripts/install-claude-plugins.sh)
subsystem_enabled caveman && _poststart+=(scripts/install-caveman.sh)
subsystem_enabled bmad && _poststart+=(scripts/install-bmad.sh scripts/bootstrap-bmad.sh)
subsystem_enabled day0 && _poststart+=(scripts/setup-day0.sh)

for script in "${_poststart[@]}"; do
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

# 8. CODEOWNERS placeholder guard (enforced in derived repos; no-op on the
# template, where the placeholder is the intentional forcing function). Shares
# scripts/check-codeowners.sh with the pre-commit hook so the two never drift.
echo ""
echo "[8] CODEOWNERS owner guard:"
if _co_out="$(bash scripts/check-codeowners.sh 2>&1)"; then
    check "CODEOWNERS has no unfilled placeholder owners" "pass"
else
    check "CODEOWNERS has no unfilled placeholder owners" "fail" "$_co_out"
fi

echo ""
if [[ $SKIP -gt 0 ]]; then
    echo "Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped (subsystems off in template.conf)"
else
    echo "Results: ${PASS} passed, ${FAIL} failed"
fi
echo ""

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi

echo "All template validation checks passed."
