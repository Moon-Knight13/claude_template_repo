#!/usr/bin/env bash
# adopt-template-sync.sh — retrofit template-update sync into a repo that was
# created from Moon-Knight13/claude_template_repo BEFORE the sync workflow
# existed. Fetches .github/workflows/template-sync.yml and .templatesyncignore
# from the template's main branch via the gh CLI (no tokens in files, matching
# board.sh conventions), writes them into this repo, and prints the follow-up
# steps. Idempotent: re-running refreshes both files.
#
# Usage: bash scripts/adopt-template-sync.sh
set -euo pipefail
IFS=$'\n\t'

TEMPLATE_REPO="Moon-Knight13/claude_template_repo"
FILES=(".github/workflows/template-sync.yml" ".templatesyncignore")

die() { echo "adopt-template-sync: $*" >&2; exit 1; }

command -v gh >/dev/null 2>&1 || die "gh is required (gh auth login first)."
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "run from inside a git repo."

# Refuse to run in the template repo itself — it must not sync from itself.
# Same detection as check-day0.sh: ask GitHub, fall back to the origin URL.
is_template_repo() {
    local is_template
    is_template=$(gh repo view --json isTemplate --jq '.isTemplate' 2>/dev/null || echo "")
    [[ "$is_template" == "true" ]] && return 0
    [[ "$is_template" == "false" ]] && return 1
    git remote get-url origin 2>/dev/null | grep -q "$TEMPLATE_REPO"
}
if is_template_repo; then
    die "this looks like the template repo itself; the sync workflow ships with it already."
fi

echo "Fetching sync files from $TEMPLATE_REPO@main..."
for f in "${FILES[@]}"; do
    mkdir -p "$(dirname "$f")"
    gh api "repos/$TEMPLATE_REPO/contents/$f?ref=main" --jq '.content' | base64 -d > "$f" \
        || die "failed to fetch $f from $TEMPLATE_REPO."
    echo "  wrote $f"
done

cat <<'EOF'

Done. Next steps:
  1. Review both files; add project-divergent paths to .templatesyncignore.
  2. Commit and push:
       git add .github/workflows/template-sync.yml .templatesyncignore
       git commit -m "chore: adopt template-sync workflow"
  3. One-time repo settings:
       - Settings > Actions > General > Workflow permissions:
         enable "Allow GitHub Actions to create and approve pull requests".
       - Optional (needed only when a sync PR changes .github/workflows/ files):
         add a fine-grained PAT secret named TEMPLATE_SYNC_TOKEN with
         contents: write, pull requests: write, workflows: write on this repo.
  4. Trigger the first sync from the Actions tab (workflow_dispatch on
     "template-sync") and review the PR it opens.
EOF
