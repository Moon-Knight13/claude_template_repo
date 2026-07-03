#!/usr/bin/env bash
# Auto-run the unattended day-0 setup steps on container start (wired into
# devcontainer.json postStartCommand). Performs everything that does NOT need
# interactive auth: copies config files into place, fills CODEOWNERS from the
# git remote, and — only when gh is already authenticated — runs the GitHub
# bootstraps. Ends by printing the day-0 status plus next steps so the build
# log guides the user through the remaining (auth-only) work.
#
# Idempotent and safe to re-run on every container start: every step is guarded
# by a missing-file / placeholder / marker check. Always exits 0 so it never
# breaks the postStart chain.
#
# NOTE: intentionally not `set -e` — best-effort steps must not abort the run.
set -uo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Operate from the repo root so relative paths (.env, .github/…) resolve.
cd "$_SCRIPT_DIR/.." || exit 0

# shellcheck disable=SC1090,SC1091
source "$_SCRIPT_DIR/lib/template-detect.sh"

echo "Day-0 auto-setup"
echo "================"

# The pristine template must not self-configure (would dirty its own tree).
if is_template_repo; then
    echo "  --  Template repo — skipping auto-setup (derived repos configure on build)."
    exit 0
fi

# 1. Copy config files into place (never clobber an existing file).
if [[ ! -f .env && -f .env.example ]]; then
    cp .env.example .env
    echo "  ++  Created .env from .env.example"
fi
if [[ ! -f .claude/settings.json && -f .claude/settings.json.example ]]; then
    cp .claude/settings.json.example .claude/settings.json
    echo "  ++  Created .claude/settings.json from example"
fi

# 2. Fill CODEOWNERS with the repo owner derived from the git remote (no gh auth
#    needed). Only touches the file while it still holds the placeholder.
if [[ -f .github/CODEOWNERS ]] && grep -q "@your-org/your-team" .github/CODEOWNERS; then
    _remote="$(git remote get-url origin 2>/dev/null || echo "")"
    # Strip protocol/host prefix and .git suffix, then take the owner segment.
    _owner="$(echo "$_remote" | sed -E 's#^(git@[^:]+:|https?://[^/]+/)##; s#\.git$##' | cut -d/ -f1)"
    if [[ -n "$_owner" ]]; then
        sed -i "s#@your-org/your-team#@${_owner}#g" .github/CODEOWNERS
        echo "  ++  Set CODEOWNERS owner to @${_owner} (from git remote)"
        echo "      NOTE: if @${_owner} is a GitHub organization, CODEOWNERS needs a team"
        echo "      (e.g. @${_owner}/your-team) — a bare org is not a valid code owner."
    fi
fi

# 3. Best-effort GitHub bootstraps — only when gh is already authenticated.
#    These mutate REMOTE GitHub settings, so log loudly. Each is guarded by its
#    completion marker so it runs at most once.
if gh auth status >/dev/null 2>&1; then
    if ! grep -q "@your-org/your-team" .github/CODEOWNERS 2>/dev/null \
        && [[ ! -f .ai/bootstrap-completed ]]; then
        echo "  >>  gh authenticated — applying GitHub repo settings (bootstrap-github-settings.sh)…"
        APPLY=true bash scripts/bootstrap-github-settings.sh \
            || echo "  !!  bootstrap-github-settings.sh failed (continuing)"
    fi
    if gh auth status 2>&1 | grep -qF "'project'" \
        && [[ ! -f .ai/project-bootstrap-completed ]]; then
        echo "  >>  gh has 'project' scope — bootstrapping Kanban board (bootstrap-project.sh)…"
        APPLY=true bash scripts/bootstrap-project.sh \
            || echo "  !!  bootstrap-project.sh failed (continuing)"
    fi
else
    echo "  --  gh not authenticated yet — skipping GitHub/board bootstraps (see next steps)."
fi

# 4. Show current day-0 status; print next steps if anything still remains.
echo ""
if bash scripts/check-day0.sh; then
    echo ""
    echo "All day-0 steps complete — repo is fully configured."
else
    cat <<'EOF'

Next steps (the only manual, auth-gated part):
  1. Authenticate Claude:  run `claude` and log in.
  2. Authenticate GitHub:
       gh auth login --hostname github.com --git-protocol https --web
       gh auth setup-git
       gh auth refresh -s project
  3. Re-run this script to finish the GitHub + Kanban board bootstraps:
       bash scripts/setup-day0.sh
  (Optional local model: install Ollama on the host, then
   `ollama pull qwen2.5-coder:7b`, or set LOCAL_MODEL_ENABLED=false in .env.)
EOF
fi

exit 0
