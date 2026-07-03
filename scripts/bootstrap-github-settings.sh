#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Configure GitHub repository protections to the template's standard.
#
# Uses a repository RULESET (not legacy branch protection) targeting the default
# branch. Idempotent: creates the ruleset if it does not exist, updates it in
# place if a ruleset of the same name already exists.
#
# The ruleset enforces:
#   - pull request required, with N approving reviews (default 1)
#   - required status checks: the template's universal gates (validate-template,
#     semgrep, gitleaks) must pass before merge
#   - linear history; no force-pushes, deletions, or direct pushes to the branch
#
# Also applies repo-level settings: merge hygiene (squash/rebase only,
# auto-delete branches) and "Allow GitHub Actions to create and approve pull
# requests" (needed by the template-sync workflow).
#
# Safe by default: dry-run unless APPLY=true, targets the default branch (or the
# BRANCH override, once REQUIRE_DEFAULT_BRANCH=false unlocks it), and refuses to
# require code-owner reviews while CODEOWNERS is still a placeholder.
#
# Environment overrides:
#   APPLY=true                 actually mutate settings (default: dry-run)
#   RULESET_NAME=...           ruleset name (default: Main_Branch_Protections)
#   REQUIRED_APPROVALS=1       approving reviews required
#   REQUIRE_CODEOWNERS=true    require code-owner review (guarded by placeholder check)
#   DISMISS_STALE=true         dismiss stale approvals on new pushes
#   REQUIRE_THREAD_RESOLUTION=true   require all review threads resolved
#   REQUIRED_CHECKS=a,b,c      status-check contexts (bare job names)
#   STRICT_STATUS_CHECKS=false require branch up to date before merge
#   ADMIN_BYPASS=false         allow repo admins to bypass the ruleset (default:
#                              false — admins are subject to the same gates as
#                              everyone, matching the prior enforce_admins:true
#                              posture; set true for a solo repo needing a break-glass)
#   REQUIRE_DEFAULT_BRANCH=true  refuse to target a non-default branch

RULESET_NAME="${RULESET_NAME:-Main_Branch_Protections}"
BRANCH="${BRANCH:-main}"
REQUIRED_APPROVALS="${REQUIRED_APPROVALS:-1}"
REQUIRE_CODEOWNERS="${REQUIRE_CODEOWNERS:-true}"
DISMISS_STALE="${DISMISS_STALE:-true}"
REQUIRE_THREAD_RESOLUTION="${REQUIRE_THREAD_RESOLUTION:-true}"
STRICT_STATUS_CHECKS="${STRICT_STATUS_CHECKS:-false}"
ADMIN_BYPASS="${ADMIN_BYPASS:-false}"
APPLY="${APPLY:-false}"
REQUIRE_DEFAULT_BRANCH="${REQUIRE_DEFAULT_BRANCH:-true}"
SNAPSHOT_DIR="${SNAPSHOT_DIR:-.ai/bootstrap-snapshots}"

# Universal status-check contexts (bare check-run / job names). A derived repo
# can extend this with its own lint/test job names via REQUIRED_CHECKS.
CHECKS_RAW="${REQUIRED_CHECKS:-validate-template,semgrep,gitleaks}"
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
  echo "Refusing to target a non-default branch."
  echo "Default branch is '$DEFAULT_BRANCH'. Requested branch is '$BRANCH'."
  echo "Set REQUIRE_DEFAULT_BRANCH=false to target '$BRANCH' explicitly (refs/heads/$BRANCH)."
  exit 1
fi

PERM="$(gh api "repos/$OWNER/$REPO/collaborators/$(gh api user --jq .login)/permission" --jq .permission)"
if [[ "$PERM" != "admin" ]]; then
  echo "Admin permission is required. Current permission: $PERM"
  exit 1
fi

# Guard: do not require code-owner reviews while CODEOWNERS is unset or still the
# shipped placeholder — that would make the branch permanently unmergeable.
if [[ "$REQUIRE_CODEOWNERS" == "true" ]]; then
  if [[ ! -f .github/CODEOWNERS ]] || grep -q "@your-org/your-team" .github/CODEOWNERS; then
    echo "Refusing to require code-owner reviews: .github/CODEOWNERS is missing or still"
    echo "contains the placeholder '@your-org/your-team'."
    echo "Populate CODEOWNERS with real owners, or re-run with REQUIRE_CODEOWNERS=false."
    exit 1
  fi
fi

# Ruleset target ref. Normally the default branch (via the ~DEFAULT_BRANCH token).
# When REQUIRE_DEFAULT_BRANCH=false permits BRANCH to name a non-default branch,
# target that branch explicitly — otherwise the override would silently protect
# the default branch and leave the branch the operator named unprotected.
if [[ "$BRANCH" == "$DEFAULT_BRANCH" ]]; then
  REF_INCLUDE_JSON='["~DEFAULT_BRANCH"]'
else
  REF_INCLUDE_JSON="$(jq -n --arg b "refs/heads/$BRANCH" '[$b]')"
fi

CHECKS_JSON="$(printf '%s\n' "${CHECKS[@]}" | jq -R '{context: .}' | jq -s .)"

if [[ "$ADMIN_BYPASS" == "true" ]]; then
  # actor_id 5 = the built-in "admin" repository role.
  BYPASS_JSON='[{"actor_id":5,"actor_type":"RepositoryRole","bypass_mode":"always"}]'
else
  BYPASS_JSON='[]'
fi

RULESET_PAYLOAD="$(jq -n \
  --arg name "$RULESET_NAME" \
  --argjson approvals "$REQUIRED_APPROVALS" \
  --argjson codeowners "$REQUIRE_CODEOWNERS" \
  --argjson dismiss "$DISMISS_STALE" \
  --argjson thread "$REQUIRE_THREAD_RESOLUTION" \
  --argjson strict "$STRICT_STATUS_CHECKS" \
  --argjson checks "$CHECKS_JSON" \
  --argjson bypass "$BYPASS_JSON" \
  --argjson refinclude "$REF_INCLUDE_JSON" \
  '{
    name: $name,
    target: "branch",
    enforcement: "active",
    bypass_actors: $bypass,
    conditions: { ref_name: { include: $refinclude, exclude: [] } },
    rules: [
      {type: "deletion"},
      {type: "creation"},
      {type: "update"},
      {type: "non_fast_forward"},
      {type: "required_linear_history"},
      {type: "pull_request", parameters: {
        required_approving_review_count: $approvals,
        dismiss_stale_reviews_on_push: $dismiss,
        require_code_owner_review: $codeowners,
        require_last_push_approval: false,
        required_review_thread_resolution: $thread,
        allowed_merge_methods: ["squash", "rebase"]
      }},
      {type: "required_status_checks", parameters: {
        strict_required_status_checks_policy: $strict,
        do_not_enforce_on_create: false,
        required_status_checks: $checks
      }}
    ]
  }')"

EXISTING_ID="$(gh api "repos/$OWNER/$REPO/rulesets" --jq ".[] | select(.name==\"$RULESET_NAME\") | .id" 2>/dev/null | head -n1 || true)"

echo "Repository:      $OWNER_REPO"
echo "Default branch:  $DEFAULT_BRANCH"
echo "Target ref:      $(jq -r 'join(", ")' <<<"$REF_INCLUDE_JSON")"
if [[ -n "$EXISTING_ID" ]]; then
  echo "Ruleset:         $RULESET_NAME (update id=$EXISTING_ID)"
else
  echo "Ruleset:         $RULESET_NAME (create)"
fi
echo "Required checks: $CHECKS_RAW"
echo "Approvals:       $REQUIRED_APPROVALS  Code-owner review: $REQUIRE_CODEOWNERS  Admin bypass: $ADMIN_BYPASS"
echo "Actions PRs:     allow GitHub Actions to create and approve pull requests"
echo "Apply mode:      $APPLY"

if [[ "$APPLY" != "true" ]]; then
  echo ""
  echo "Dry run only. Set APPLY=true to mutate settings. Payload preview:"
  echo "$RULESET_PAYLOAD" | jq .
  exit 0
fi

mkdir -p "$SNAPSHOT_DIR"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
RULESET_SNAPSHOT="$SNAPSHOT_DIR/${REPO}-ruleset-${STAMP}.json"
REPO_SETTINGS_SNAPSHOT="$SNAPSHOT_DIR/${REPO}-repo-settings-${STAMP}.json"
WORKFLOW_PERMS_SNAPSHOT="$SNAPSHOT_DIR/${REPO}-workflow-permissions-${STAMP}.json"

gh api "repos/$OWNER/$REPO" > "$REPO_SETTINGS_SNAPSHOT"
gh api "repos/$OWNER/$REPO/actions/permissions/workflow" > "$WORKFLOW_PERMS_SNAPSHOT" 2>/dev/null \
  || echo '{}' > "$WORKFLOW_PERMS_SNAPSHOT"

if [[ -n "$EXISTING_ID" ]]; then
  gh api "repos/$OWNER/$REPO/rulesets/$EXISTING_ID" > "$RULESET_SNAPSHOT" 2>/dev/null || echo '{}' > "$RULESET_SNAPSHOT"
  gh api --method PUT \
    -H "Accept: application/vnd.github+json" \
    "repos/$OWNER/$REPO/rulesets/$EXISTING_ID" \
    --input - <<< "$RULESET_PAYLOAD" >/dev/null
  echo "Updated ruleset id=$EXISTING_ID."
else
  echo '{}' > "$RULESET_SNAPSHOT"
  NEW_ID="$(gh api --method POST \
    -H "Accept: application/vnd.github+json" \
    "repos/$OWNER/$REPO/rulesets" \
    --input - <<< "$RULESET_PAYLOAD" --jq .id)"
  echo "Created ruleset id=$NEW_ID."
fi

# Repo-level merge hygiene (not covered by rulesets): squash/rebase only, auto-delete branches.
gh api \
  --method PATCH \
  -H "Accept: application/vnd.github+json" \
  "repos/$OWNER/$REPO" \
  -f allow_merge_commit=false \
  -f allow_rebase_merge=true \
  -f allow_squash_merge=true \
  -f delete_branch_on_merge=true >/dev/null

# Allow GitHub Actions to create and approve pull requests — required by the
# template-sync workflow (and any other PR-creating automation). This endpoint
# only accepts PUT (PATCH 404s); the body is partial, so the repo's
# default_workflow_permissions is kept.
gh api \
  --method PUT \
  -H "Accept: application/vnd.github+json" \
  "repos/$OWNER/$REPO/actions/permissions/workflow" \
  -F can_approve_pull_request_reviews=true >/dev/null

mkdir -p .ai && touch .ai/bootstrap-completed
echo "Bootstrap applied successfully."
echo "Snapshots saved:"
echo "  Ruleset (prior): $RULESET_SNAPSHOT"
echo "  Repo settings:   $REPO_SETTINGS_SNAPSHOT"
if [[ -n "$EXISTING_ID" ]]; then
  echo "Rollback hint: restore the prior ruleset from the snapshot, e.g."
  echo "  gh api --method PUT repos/$OWNER/$REPO/rulesets/$EXISTING_ID --input $RULESET_SNAPSHOT"
  echo "  (trim id/created_at/_links fields the API rejects on write)"
else
  echo "Rollback hint: delete the newly created ruleset, e.g."
  echo "  gh api --method DELETE repos/$OWNER/$REPO/rulesets/<id-printed-above>"
fi
