#!/usr/bin/env bash
# Create (or reuse) the per-repo GitHub Project v2 board for this repository.
#
# Idempotent: safe to re-run. Creates the board, the BMAD Stage and Route
# single-select fields, aligns the Status field to the kanban flow, creates the
# coordination labels, links the board to the repo, and writes .ai/project.env
# (sourced by scripts/board.sh).
#
# gh-CLI only — no secrets, no PATs. Requires the 'project' gh scope:
#   gh auth refresh -s project
#
# Usage:
#   bash scripts/bootstrap-project.sh              # dry run (prints the plan)
#   APPLY=true bash scripts/bootstrap-project.sh   # create/reconcile the board
set -euo pipefail
IFS=$'\n\t'

APPLY="${APPLY:-false}"
PROJECT_ENV="${PROJECT_ENV:-.ai/project.env}"
MARKER="${PROJECT_MARKER:-.ai/project-bootstrap-completed}"

STATUS_OPTIONS=("Backlog" "Ready" "In Progress" "In Review" "Done")
BMAD_OPTIONS=("Discovery" "Requirements" "Architecture" "Task Decomposition" "Implementation" "Security & Release")
ROUTE_OPTIONS=("Human" "Claude" "Local")

for cmd in gh jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "$cmd is required." >&2
    exit 1
  fi
done

gh auth status >/dev/null

# The Projects v2 API needs the 'project' scope, which is not in the default
# gh token. Fail early with an actionable hint rather than a cryptic API error.
if ! gh project list --owner "@me" --limit 1 >/dev/null 2>&1; then
  echo "Cannot access GitHub Projects. Grant the scope with:" >&2
  echo "  gh auth refresh -s project" >&2
  exit 1
fi

OWNER_REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
REPO="${OWNER_REPO##*/}"
OWNER_LOGIN="$(gh api user --jq .login)"
TITLE="${PROJECT_TITLE:-$REPO board}"

echo "Repository:    $OWNER_REPO"
echo "Board owner:   $OWNER_LOGIN"
echo "Board title:   $TITLE"
echo "Apply mode:    $APPLY"
( IFS='|'; echo "Status flow:   ${STATUS_OPTIONS[*]}" )

if [[ "$APPLY" != "true" ]]; then
  echo
  echo "Dry run only. Set APPLY=true to create/reconcile the board."
  exit 0
fi

# --- Find or create the project -------------------------------------------------
PROJECT_NUMBER="$(gh project list --owner "@me" --format json \
  | jq -r --arg t "$TITLE" '.projects[] | select(.title == $t) | .number' | head -n1)"

if [[ -z "$PROJECT_NUMBER" ]]; then
  echo "Creating project '$TITLE'..."
  PROJECT_NUMBER="$(gh project create --owner "@me" --title "$TITLE" --format json | jq -r '.number')"
else
  echo "Reusing existing project #$PROJECT_NUMBER."
fi

PROJECT_JSON="$(gh project view "$PROJECT_NUMBER" --owner "@me" --format json)"
PROJECT_ID="$(jq -r '.id' <<<"$PROJECT_JSON")"
PROJECT_URL="$(jq -r '.url' <<<"$PROJECT_JSON")"

# --- Field helpers --------------------------------------------------------------
fields_json() { gh project field-list "$PROJECT_NUMBER" --owner "@me" --format json; }

field_id() { fields_json | jq -r --arg n "$1" '.fields[] | select(.name == $n) | .id' | head -n1; }

# Build a GraphQL single-select options literal, cycling through option colors.
options_literal() {
  local colors=(GRAY BLUE GREEN YELLOW ORANGE RED PURPLE PINK)
  local out="" i=0 name
  for name in "$@"; do
    local color="${colors[$(( i % ${#colors[@]} ))]}"
    local esc="${name//\"/\\\"}"
    out+="{name:\"$esc\",color:$color,description:\"\"},"
    i=$((i+1))
  done
  printf '[%s]' "${out%,}"
}

# Set a single-select field's options (creates the field if missing).
ensure_single_select() {
  local name="$1"; shift
  local snapshot; snapshot="$(fields_json)"
  local fid; fid="$(jq -r --arg n "$name" '.fields[] | select(.name == $n) | .id' <<<"$snapshot" | head -n1)"
  if [[ -z "$fid" ]]; then
    echo "Creating field '$name'..."
    local csv; csv="$(IFS=,; echo "$*")"
    gh project field-create "$PROJECT_NUMBER" --owner "@me" \
      --name "$name" --data-type SINGLE_SELECT --single-select-options "$csv" >/dev/null
    return
  fi
  # Field exists — reconcile ADDITIVELY. updateProjectV2Field replaces the entire
  # option set, and any option sent without an id is created fresh, so re-sending
  # existing options by name alone would delete+recreate them and DETACH every card
  # currently set to that option (e.g. a board still on the built-in Todo/Done).
  # To preserve board state we keep every existing option verbatim (by its id) and
  # append only the wanted options that are genuinely missing.
  local existing
  existing="$(gh api graphql -f query="query{node(id:\"$fid\"){... on ProjectV2SingleSelectField{options{id name color description}}}}" \
    --jq '.data.node.options // []' 2>/dev/null || echo '[]')"

  # Guard: if we couldn't read options but the field is known to have some, skip
  # rather than risk wiping them.
  local snap_count exist_count
  snap_count="$(jq -r --arg n "$name" '[.fields[] | select(.name==$n) | (.options // [])[]] | length' <<<"$snapshot")"
  exist_count="$(jq 'length' <<<"$existing")"
  if [[ "$exist_count" == "0" && "${snap_count:-0}" != "0" ]]; then
    echo "  WARN: could not read existing options for '$name' via API; skipping reconcile to avoid data loss. Set them in the board UI if needed: ${*}" >&2
    return
  fi

  local missing=() opt
  for opt in "$@"; do
    jq -e --arg n "$opt" 'any(.[]; .name == $n)' <<<"$existing" >/dev/null \
      || missing+=("$opt")
  done
  if [[ ${#missing[@]} -eq 0 ]]; then
    echo "Field '$name' already has all required options."
    return
  fi
  echo "Adding missing options to field '$name': ${missing[*]}"

  # Existing options first (with ids → preserved), then the new ones (no id → created).
  local kept new_lit combined
  kept="$(jq -r '
    def esc: gsub("\""; "\\\"");
    [ .[] | "{id:\"\(.id)\",name:\"\(.name|esc)\",color:\(.color),description:\"\(.description // "" | esc)\"}" ] | join(",")
  ' <<<"$existing")"
  new_lit="$(options_literal "${missing[@]}")"   # -> [ {..},{..} ]
  new_lit="${new_lit#[}"; new_lit="${new_lit%]}"
  if [[ -n "$kept" && -n "$new_lit" ]]; then
    combined="[$kept,$new_lit]"
  else
    combined="[${kept}${new_lit}]"
  fi
  gh api graphql -f query="mutation{updateProjectV2Field(input:{fieldId:\"$fid\",singleSelectOptions:$combined}){projectV2Field{... on ProjectV2SingleSelectField{id}}}}" >/dev/null \
    || echo "  WARN: could not update '$name' options automatically; add these in the board UI: ${missing[*]}" >&2
}

# Status is the built-in board field; align it to the kanban flow.
ensure_single_select "Status" "${STATUS_OPTIONS[@]}"
ensure_single_select "BMAD Stage" "${BMAD_OPTIONS[@]}"
ensure_single_select "Route" "${ROUTE_OPTIONS[@]}"

# --- Link board to repo ---------------------------------------------------------
gh project link "$PROJECT_NUMBER" --owner "@me" --repo "$OWNER_REPO" >/dev/null 2>&1 \
  || echo "Note: project already linked to $OWNER_REPO (or link not permitted)."

# --- Coordination labels --------------------------------------------------------
create_label() { gh label create "$1" --color "$2" --description "$3" --force >/dev/null 2>&1 || true; }
create_label "epic"        "6f42c1" "A group of related user stories"
create_label "story"       "0e8a16" "A single unit of work / one card"
create_label "agent-ready" "1d76db" "Ready to be claimed by an agent session"
create_label "wip"         "fbca04" "Claimed — work in progress, do not touch"

# --- Persist board coordinates --------------------------------------------------
mkdir -p "$(dirname "$PROJECT_ENV")"
cat > "$PROJECT_ENV" <<EOF
# Written by scripts/bootstrap-project.sh — sourced by scripts/board.sh
PROJECT_NUMBER="$PROJECT_NUMBER"
PROJECT_OWNER="$OWNER_LOGIN"
PROJECT_ID="$PROJECT_ID"
PROJECT_URL="$PROJECT_URL"
EOF

touch "$MARKER"

echo
echo "Board ready: $PROJECT_URL"
echo "Coordinates written to $PROJECT_ENV"
echo "Next: create issues from the Epic/User Story templates, then use /bmad-to-board or scripts/board.sh."
