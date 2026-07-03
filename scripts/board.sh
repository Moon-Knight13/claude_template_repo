#!/usr/bin/env bash
# board.sh — the gh-native Kanban board API for this repo's GitHub Project v2.
#
# Every board read/write goes through here (skills and humans alike), using your
# already-authed gh CLI — no secrets, no CI. Requires the board to have been
# created by scripts/bootstrap-project.sh (which writes .ai/project.env) and the
# 'project' gh scope (gh auth refresh -s project).
#
# Subcommands:
#   add <issue#>                     Add an issue to the board (Status=Backlog).
#   set-field <issue#> <field> <val> Set Status | "BMAD Stage" | Route to <val>.
#   move <issue#> <status-slug>      Move card: backlog|ready|in-progress|in-review|done.
#   next                             Print the top Ready + agent-ready + unassigned card.
#   claim <issue#>                   Atomic claim: assign + wip + In Progress + re-check.
#   release <issue#>                 Undo a claim: unassign + drop wip + back to Ready.
set -euo pipefail
IFS=$'\n\t'

PROJECT_ENV="${PROJECT_ENV:-.ai/project.env}"

die() { echo "board.sh: $*" >&2; exit 1; }

for cmd in gh jq; do
  command -v "$cmd" >/dev/null 2>&1 || die "$cmd is required."
done

[[ -f "$PROJECT_ENV" ]] || die "$PROJECT_ENV not found. Run: APPLY=true bash scripts/bootstrap-project.sh"
# shellcheck disable=SC1090
source "$PROJECT_ENV"
: "${PROJECT_NUMBER:?PROJECT_NUMBER missing in $PROJECT_ENV}"
: "${PROJECT_OWNER:?PROJECT_OWNER missing in $PROJECT_ENV}"
: "${PROJECT_ID:?PROJECT_ID missing in $PROJECT_ENV}"

NUM="$PROJECT_NUMBER"
OWNER="$PROJECT_OWNER"

me() { gh api user --jq .login; }

# Cache field-list once per invocation.
_FIELDS=""
fields() { [[ -n "$_FIELDS" ]] || _FIELDS="$(gh project field-list "$NUM" --owner "$OWNER" --format json)"; printf '%s' "$_FIELDS"; }

field_id() { fields | jq -r --arg n "$1" '.fields[] | select(.name==$n) | .id' | head -n1; }
option_id() { fields | jq -r --arg n "$1" --arg v "$2" '.fields[] | select(.name==$n) | .options[]? | select(.name==$v) | .id' | head -n1; }

item_id() {
  gh project item-list "$NUM" --owner "$OWNER" --format json --limit 800 \
    | jq -r --argjson num "$1" '.items[] | select(.content.number == $num) | .id' | head -n1
}

ensure_item() {
  local n="$1" iid
  iid="$(item_id "$n")"
  if [[ -z "$iid" ]]; then
    local url; url="$(gh issue view "$n" --json url --jq .url)"
    gh project item-add "$NUM" --owner "$OWNER" --url "$url" --format json | jq -r '.id'
  else
    printf '%s' "$iid"
  fi
}

set_field() {
  local n="$1" field="$2" value="$3"
  local iid fid oid
  iid="$(ensure_item "$n")"
  fid="$(field_id "$field")"
  [[ -n "$fid" ]] || die "no field named '$field' on the board"
  oid="$(option_id "$field" "$value")"
  [[ -n "$oid" ]] || die "field '$field' has no option '$value'"
  gh project item-edit --id "$iid" --project-id "$PROJECT_ID" --field-id "$fid" --single-select-option-id "$oid" >/dev/null
  echo "#$n: $field -> $value"
}

status_for_slug() {
  case "$1" in
    backlog)     echo "Backlog" ;;
    todo)        echo "Todo" ;;
    ready)       echo "Ready" ;;
    in-progress|wip) echo "In Progress" ;;
    in-review|review) echo "In Review" ;;
    done)        echo "Done" ;;
    *) die "unknown status slug '$1' (backlog|todo|ready|in-progress|in-review|done)" ;;
  esac
}

cmd_add() {
  local n="$1"; [[ -n "$n" ]] || die "usage: board.sh add <issue#>"
  set_field "$n" "Status" "Backlog"  # set_field ensures the card exists
}

cmd_next() {
  # Top card that is Ready, labelled agent-ready, and unassigned.
  local items n
  items="$(gh project item-list "$NUM" --owner "$OWNER" --format json --limit 800)"
  while IFS= read -r n; do
    [[ -n "$n" ]] || continue
    local meta; meta="$(gh issue view "$n" --json number,title,url,labels,assignees,state 2>/dev/null)" || continue
    [[ "$(jq -r '.state' <<<"$meta")" == "OPEN" ]] || continue
    jq -e '.labels[]? | select(.name=="agent-ready")' <<<"$meta" >/dev/null || continue
    [[ "$(jq -r '.assignees | length' <<<"$meta")" == "0" ]] || continue
    jq -r '"#\(.number)  \(.title)\n\(.url)"' <<<"$meta"
    return 0
  done < <(jq -r '.items[] | select((.status // "") == "Ready") | .content.number' <<<"$items")
  echo "No Ready + agent-ready + unassigned cards."
  return 0
}

cmd_claim() {
  local n="$1"; [[ -n "$n" ]] || die "usage: board.sh claim <issue#>"
  local who; who="$(me)"

  # Pre-check: refuse an already-claimed card.
  local pre; pre="$(gh issue view "$n" --json assignees,labels)"
  if [[ "$(jq -r '.assignees | length' <<<"$pre")" != "0" ]]; then
    echo "#$n already assigned to: $(jq -r '[.assignees[].login] | join(", ")' <<<"$pre") — not claiming." >&2
    return 3
  fi

  gh issue edit "$n" --add-assignee "@me" --add-label "wip" >/dev/null
  set_field "$n" "Status" "In Progress" >/dev/null

  # Re-read: confirm we are the sole assignee (optimistic-lock against a race).
  local post owners
  post="$(gh issue view "$n" --json assignees)"
  owners="$(jq -r '[.assignees[].login] | join(",")' <<<"$post")"
  if [[ "$owners" != "$who" ]]; then
    echo "#$n was claimed concurrently (assignees: $owners). Releasing my hold." >&2
    gh issue edit "$n" --remove-assignee "@me" >/dev/null || true
    # We also set 'wip' + In Progress moments ago. If a rival still holds the card
    # that lock is theirs — leave it. But if we just backed off and NO ONE is left
    # (mutual back-off), clear it so the card doesn't strand as wip/In-Progress with
    # zero assignees, invisible to `next` yet flagged "do not touch".
    local after
    after="$(gh issue view "$n" --json assignees)"
    if [[ "$(jq -r '.assignees | length' <<<"$after")" == "0" ]]; then
      gh issue edit "$n" --remove-label "wip" >/dev/null || true
      set_field "$n" "Status" "Ready" >/dev/null || true
    fi
    return 3
  fi
  echo "Claimed #$n as $who (assigned + wip + In Progress)."
}

cmd_release() {
  local n="$1"; [[ -n "$n" ]] || die "usage: board.sh release <issue#>"
  # Gate the Status flip on the unassign/unlabel actually succeeding — otherwise a
  # swallowed error would leave the card assigned + wip yet shown Ready, so `next`
  # (Ready AND unassigned) never surfaces it and the story is silently orphaned.
  gh issue edit "$n" --remove-assignee "@me" --remove-label "wip" >/dev/null \
    || die "failed to unassign/unlabel #$n; leaving card as-is (Status not changed)."
  set_field "$n" "Status" "Ready" >/dev/null
  echo "Released #$n (back to Ready)."
}

main() {
  local sub="${1:-}"; shift || true
  case "$sub" in
    add)       cmd_add "${1:-}" ;;
    set-field) [[ $# -ge 3 ]] || die "usage: board.sh set-field <issue#> <field> <value>"; set_field "$1" "$2" "$3" ;;
    move)      [[ $# -ge 2 ]] || die "usage: board.sh move <issue#> <status-slug>"; set_field "$1" "Status" "$(status_for_slug "$2")" ;;
    next)      cmd_next ;;
    claim)     cmd_claim "${1:-}" ;;
    release)   cmd_release "${1:-}" ;;
    ""|-h|--help|help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed '1d' ;;
    *) die "unknown subcommand '$sub' (see: board.sh help)" ;;
  esac
}

main "$@"
