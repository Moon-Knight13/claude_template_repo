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

STATUS_OPTIONS=("Backlog" "Todo" "Ready" "In Progress" "In Review" "Done")
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
  # Field exists — reconcile to the DESIRED ORDER while preserving board state.
  # updateProjectV2Field replaces the entire option set: an option sent WITH its
  # id is kept (cards stay attached); an option sent without an id is created; any
  # existing option omitted from the payload is deleted (detaching its cards). So
  # we emit the wanted options in order (reusing the id where a name already
  # exists), then append any extra existing options not in the wanted list — those
  # are preserved, never dropped. This fixes both missing options AND wrong order
  # (e.g. a board still carrying the pre-seeded Todo/In Progress/Done order that an
  # append-only reconcile could never correct).
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

  # Desired option names as a JSON array.
  local wanted_json
  wanted_json="$(printf '%s\n' "$@" | jq -R . | jq -s .)"

  # Skip the mutation when the field already has exactly the wanted options in the
  # wanted order (wanted first, then any extras). Newline-join is safe: option
  # names are single-line.
  local target_order current_order
  target_order="$(jq -r --argjson w "$wanted_json" '
    ([ $w[] ] + [ .[].name | select(. as $n | ($w | index($n)) | not) ]) | join("\n")
  ' <<<"$existing")"
  current_order="$(jq -r '[ .[].name ] | join("\n")' <<<"$existing")"
  if [[ "$target_order" == "$current_order" ]]; then
    echo "Field '$name' already has the required options in order."
    return
  fi
  echo "Reconciling field '$name' options to desired order."

  # Build the GraphQL singleSelectOptions literal in target order: reuse id+color
  # for names that already exist; assign a cycling color to newly-created ones.
  local combined
  combined="$(jq -rn --argjson existing "$existing" --argjson wanted "$wanted_json" '
    def colors: ["GRAY","BLUE","GREEN","YELLOW","ORANGE","RED","PURPLE","PINK"];
    def esc: gsub("\""; "\\\"");
    ($existing | map({(.name): .}) | add // {}) as $byname
    | ([ $wanted[] | $byname[.] // {name: ., new: true} ]
       + [ $existing[] | select(.name as $n | ($wanted | index($n)) | not) ]) as $opts
    | [ $opts | to_entries[]
        | .key as $i | .value as $o
        | ( if $o.id then "id:\"\($o.id)\"," else "" end ) as $idp
        | ( $o.color // (colors[$i % (colors|length)]) ) as $col
        | "{\($idp)name:\"\($o.name|esc)\",color:\($col),description:\"\($o.description // "" | esc)\"}"
      ] | "[" + join(",") + "]"
  ')"
  gh api graphql -f query="mutation{updateProjectV2Field(input:{fieldId:\"$fid\",singleSelectOptions:$combined}){projectV2Field{... on ProjectV2SingleSelectField{id}}}}" >/dev/null \
    || echo "  WARN: could not update '$name' options automatically; set them in the board UI: ${*}" >&2
}

# Status is the built-in board field; align it to the kanban flow.
ensure_single_select "Status" "${STATUS_OPTIONS[@]}"
ensure_single_select "BMAD Stage" "${BMAD_OPTIONS[@]}"
ensure_single_select "Route" "${ROUTE_OPTIONS[@]}"

# --- Link board to repo ---------------------------------------------------------
# Surface the real outcome instead of swallowing stderr: an already-linked board is
# benign, but a permission/scope failure must not masquerade as success.
# gh resolves --repo against the literal --owner value, so "@me" produces the
# bogus repo "@me/<repo>". Pass the real login and the BARE repo name, matching
# gh's own example (`--owner monalisa --repo my_repo`).
if link_out="$(gh project link "$PROJECT_NUMBER" --owner "$OWNER_LOGIN" --repo "$REPO" 2>&1)"; then
  echo "Linked board to $OWNER_REPO."
elif printf '%s' "$link_out" | grep -qi "already"; then
  echo "Board already linked to $OWNER_REPO."
else
  echo "WARNING: failed to link board to $OWNER_REPO — fix and re-run, or link manually:" >&2
  printf '  gh project link %s --owner %s --repo %s\n' "$PROJECT_NUMBER" "$OWNER_LOGIN" "$REPO" >&2
  printf '%s\n' "$link_out" >&2
fi

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
