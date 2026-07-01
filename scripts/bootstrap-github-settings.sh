#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

BRANCH="${BRANCH:-main}"
REQUIRED_APPROVALS="${REQUIRED_APPROVALS:-1}"
REQUIRE_CODEOWNERS="${REQUIRE_CODEOWNERS:-true}"
DISMISS_STALE="${DISMISS_STALE:-true}"
REQUIRE_UP_TO_DATE="${REQUIRE_UP_TO_DATE:-true}"
APPLY="${APPLY:-false}"
REQUIRE_DEFAULT_BRANCH="${REQUIRE_DEFAULT_BRANCH:-true}"
SNAPSHOT_DIR="${SNAPSHOT_DIR:-.ai/bootstrap-snapshots}"

CHECKS_RAW="${REQUIRED_CHECKS:-ci / detect-and-route,secret-scan / gitleaks,semgrep / semgrep}"
IFS=',' read -r -a CHECKS <<< "$CHECKS_RAW"

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI is required."
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required."
  exit 1
fi

gh auth status >/dev/null

OWNER_REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
OWNER="${OWNER_REPO%%/*}"
REPO="${OWNER_REPO##*/}"
DEFAULT_BRANCH="$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)"

if [[ "$REQUIRE_DEFAULT_BRANCH" == "true" && "$BRANCH" != "$DEFAULT_BRANCH" ]]; then
  echo "Refusing to modify non-default branch protection."
  echo "Default branch is '$DEFAULT_BRANCH'. Requested branch is '$BRANCH'."
  echo "Set REQUIRE_DEFAULT_BRANCH=false only if you intentionally need a different branch."
  exit 1
fi

if ! gh api "repos/$OWNER/$REPO/branches/$BRANCH" >/dev/null 2>&1; then
  echo "Branch '$BRANCH' does not exist in $OWNER_REPO."
  exit 1
fi

PERM="$(gh api "repos/$OWNER/$REPO/collaborators/$(gh api user --jq .login)/permission" --jq .permission)"
if [[ "$PERM" != "admin" ]]; then
  echo "Admin permission is required. Current permission: $PERM"
  exit 1
fi

CHECKS_JSON="$(printf '%s\n' "${CHECKS[@]}" | jq -R . | jq -s .)"

PROTECTION_PAYLOAD="$(jq -n \
  --argjson checks "$CHECKS_JSON" \
  --argjson approvals "$REQUIRED_APPROVALS" \
  --argjson codeowners "$REQUIRE_CODEOWNERS" \
  --argjson dismiss "$DISMISS_STALE" \
  --argjson strict "$REQUIRE_UP_TO_DATE" \
  '{
    required_status_checks: {strict: $strict, contexts: $checks},
    enforce_admins: true,
    required_pull_request_reviews: {
      dismiss_stale_reviews: $dismiss,
      require_code_owner_reviews: $codeowners,
      required_approving_review_count: $approvals
    },
    restrictions: null,
    required_linear_history: true,
    allow_force_pushes: false,
    allow_deletions: false,
    block_creations: false,
    required_conversation_resolution: true,
    lock_branch: false,
    allow_fork_syncing: false
  }')"

echo "Repository: $OWNER_REPO"
echo "Branch: $BRANCH"
echo "Default branch: $DEFAULT_BRANCH"
echo "Apply mode: $APPLY"
echo "Required checks: $CHECKS_RAW"

if [[ "$APPLY" != "true" ]]; then
  echo "Dry run only. Set APPLY=true to mutate settings."
  exit 0
fi

mkdir -p "$SNAPSHOT_DIR"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
PROTECTION_SNAPSHOT="$SNAPSHOT_DIR/${REPO}-${BRANCH}-protection-${STAMP}.json"
REPO_SETTINGS_SNAPSHOT="$SNAPSHOT_DIR/${REPO}-repo-settings-${STAMP}.json"

if ! gh api "repos/$OWNER/$REPO/branches/$BRANCH/protection" > "$PROTECTION_SNAPSHOT" 2>/dev/null; then
  # Branch may not have protection yet; keep a valid placeholder snapshot.
  echo '{}' > "$PROTECTION_SNAPSHOT"
fi
gh api "repos/$OWNER/$REPO" > "$REPO_SETTINGS_SNAPSHOT"

gh api \
  --method PUT \
  -H "Accept: application/vnd.github+json" \
  "repos/$OWNER/$REPO/branches/$BRANCH/protection" \
  --input - <<< "$PROTECTION_PAYLOAD"

gh api \
  --method PATCH \
  -H "Accept: application/vnd.github+json" \
  "repos/$OWNER/$REPO" \
  -f allow_merge_commit=false \
  -f allow_rebase_merge=true \
  -f allow_squash_merge=true \
  -f delete_branch_on_merge=true >/dev/null

mkdir -p .ai && touch .ai/bootstrap-completed
echo "Bootstrap applied successfully."
echo "Snapshots saved:"
echo "  Branch protection: $PROTECTION_SNAPSHOT"
echo "  Repo settings:     $REPO_SETTINGS_SNAPSHOT"
echo "Rollback hint (branch protection):"
echo "  gh api --method PUT -H 'Accept: application/vnd.github+json' repos/$OWNER/$REPO/branches/$BRANCH/protection --input $PROTECTION_SNAPSHOT"
