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

# 9. Security control assertions.
#
# Sections 1-8 verify structure and syntax: files present, YAML parsing, scripts
# executable, shellcheck clean. Not one of them asserts that a security control
# actually WORKS. That gap mattered, because README.md presents this script as
# the template's integrity gate, so a green run reads as "the controls are
# sound" when it only ever meant "the files are well-formed".
#
# The model for this section already existed in the repo: init-firewall.sh ends
# by asserting example.com is unreachable AND api.github.com is reachable, then
# exits non-zero. These checks are that shape - each one exercises a control and
# fails loudly when it does not behave.
echo ""
echo "[9] Security control behaviour:"

_settings=".claude/settings.json"
if [[ ! -f "$_settings" ]]; then
    check "$_settings exists" "fail" "Committed project settings carry the deny rules and hook wiring"
elif ! python3 -c "import json,sys; json.load(open('$_settings'))" 2>/dev/null; then
    check "$_settings is valid JSON" "fail" "Malformed settings are silently ignored by Claude Code"
else
    check "$_settings is valid JSON" "pass"

    # Deny rules are the only control documented to hold in every permission
    # mode, including bypassPermissions. Assert the credential paths are covered
    # rather than trusting the file looks right.
    for _needle in '.credentials.json' '.ssh' '.env'; do
        if python3 -c "
import json,sys
d=json.load(open('$_settings'))
rules=d.get('permissions',{}).get('deny',[])
sys.exit(0 if any('$_needle' in r for r in rules) else 1)
" 2>/dev/null; then
            check "deny rule covers $_needle" "pass"
        else
            check "deny rule covers $_needle" "fail" "Add a Read()/Edit() deny rule for $_needle to permissions.deny"
        fi
    done

    # A hook wired to a missing or non-executable script fails open and silently.
    while IFS= read -r _hook; do
        _hook_path="${_hook/\$\{CLAUDE_PROJECT_DIR\}\//}"
        if [[ -x "$_hook_path" ]]; then
            check "hook $_hook_path is executable" "pass"
        else
            check "hook $_hook_path is executable" "fail" "Wired in $_settings but missing or not executable - the hook fails open"
        fi
    done < <(python3 -c "
import json
d=json.load(open('$_settings'))
for event, groups in d.get('hooks', {}).items():
    if event.startswith('_'):
        continue
    for g in groups:
        for h in g.get('hooks', []):
            if h.get('type') == 'command' and h.get('command'):
                print(h['command'])
" 2>/dev/null)
fi

# The harness guard must deny a governing file and stay out of the way for
# everything else. A guard that denies nothing, or denies everything, is worse
# than none: the first is theatre, the second gets switched off.
_guard=".claude/hooks/guard-harness-files.sh"
if [[ -x "$_guard" ]] && command -v jq &>/dev/null; then
    # A fall-through emits nothing at all, and jq on empty stdin emits nothing
    # rather than its // default - so normalise empty to "none" here, or the
    # no-decision case is indistinguishable from a broken probe.
    _probe() {
        local _out
        _out="$(jq -n --arg p "$PWD/$1" \
            '{cwd:"'"$PWD"'",hook_event_name:"PreToolUse",tool_name:"Edit",tool_input:{file_path:$p}}' \
            | CLAUDE_PROJECT_DIR="$PWD" bash "$_guard" 2>/dev/null \
            | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null)"
        echo "${_out:-none}"
    }
    if [[ "$(_probe CLAUDE.md)" == "deny" ]]; then
        check "harness guard denies edits to CLAUDE.md" "pass"
    else
        check "harness guard denies edits to CLAUDE.md" "fail" "The guard is wired but not blocking - a session can rewrite its own rules"
    fi
    if [[ "$(_probe README.md)" == "none" ]]; then
        check "harness guard leaves ordinary files alone" "pass"
    else
        check "harness guard leaves ordinary files alone" "fail" "Over-broad guard - it will be disabled in practice"
    fi
else
    echo "  --  harness guard or jq unavailable; behaviour probe skipped"
fi

# Routing: CLAUDE.md's hard escalation triggers say a high-risk task never goes
# to the local model. Assert the script agrees, rather than trusting the prose.
if subsystem_enabled routing && [[ -x scripts/route-model.sh ]]; then
    if bash scripts/route-model.sh security high 1 2>/dev/null | grep -qv '^local:'; then
        check "high-risk security task does not route local" "pass"
    else
        check "high-risk security task does not route local" "fail" "route-model.sh contradicts the hard escalation triggers in CLAUDE.md"
    fi
fi

# Sandbox availability. Reported, not failed: bubblewrap needs unprivileged user
# namespaces that a host kernel may withhold, and this validator also runs in CI
# outside the devcontainer. The point is that degradation stops being silent -
# .claude/settings.json deliberately leaves failIfUnavailable unset so a derived
# repo is never bricked by a kernel detail, which makes saying so here the only
# thing standing between "sandboxed" and "assumed sandboxed".
if command -v bwrap &>/dev/null; then
    check "bubblewrap present (Bash sandbox can initialise)" "pass"
else
    echo "  --  bubblewrap not on PATH; the Bash sandbox cannot initialise here and"
    echo "      every sandbox.* key in $_settings is inert. Expected outside the"
    echo "      devcontainer; inside it, rebuild the image."
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
