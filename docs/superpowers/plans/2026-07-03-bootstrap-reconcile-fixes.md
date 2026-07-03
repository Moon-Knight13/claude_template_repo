# Bootstrap Project Reconcile Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the 8 verified code-review findings in `scripts/bootstrap-project.sh` — an org-repo link regression and a duplicate-named-option data-loss path (both blockers), plus reordering, escaping, idempotency, and cleanup issues.

**Architecture:** Extract the single-select option ordering into a standalone, unit-testable jq program (`scripts/lib/reconcile-options.jq`) that is computed once and consumed by both the skip-check and the mutation payload. Build the GraphQL literal with jq `@json` for correct escaping. Fix the board-link call to rely on gh's current-directory repo resolution. Verify the GraphQL input accepts `id` before trusting the card-preserving reconcile.

**Tech Stack:** Bash, `gh` CLI (GitHub Projects v2 GraphQL), `jq`. Tests: plain-bash PASS/FAIL harness with PATH shims, matching `scripts/tests/test-day0.sh`.

## Global Constraints

- gh-CLI only — no secrets, no PATs (`CLAUDE.md` guardrails).
- Script stays idempotent and re-runnable; `set -euo pipefail`, `IFS=$'\n\t'` already set.
- Board is always owned by `@me`; every gh project subcommand in this script uses `--owner "@me"`. Keep that consistent.
- Option names are single-line (no embedded newlines) — the newline-join skip-check depends on this.
- Priority order (from `CLAUDE.md`): Security > Correctness > Maintainability. These fixes are Correctness class; touches infra/board wiring → Claude-routed, no local delegation.

---

## Finding → Task map

| # | Finding | Task |
|---|---------|------|
| 1 | Dup-named options detach cards (data loss) | 1, 2 |
| 2 | `gh project link` breaks on org repos (blocker) | 3 |
| 3 | Custom options silently reordered every run | 1, 2 |
| 4 | `esc` only escapes double-quotes | 1, 2 |
| 5 | Reconcile depends on `id` in option input (unverified) | 4 |
| 6 | Idempotency guard now order-strict | 2 (shared calc) + 4 (doc) |
| 7 | Desired order computed twice, can drift | 1, 2 |
| 8 | Double `jq` fork | 2 |

---

### Task 1: Extract option-ordering into a tested jq program

Isolates the ordering + preservation logic (findings 1, 3, 7; enables 4) into one file that is testable with crafted JSON and no network.

**Files:**
- Create: `scripts/lib/reconcile-options.jq`
- Test: `scripts/tests/test-reconcile-options.sh`

**Interfaces:**
- Produces: `reconcile-options.jq` — invoked as
  `jq -c -n --argjson existing "$existing" --argjson wanted "$wanted_json" -f scripts/lib/reconcile-options.jq`
  - `$existing`: JSON array of `{id,name,color,description}` (from the API; may be empty).
  - `$wanted`: JSON array of desired option-name strings.
  - Output: ordered JSON array of `{id?,name,color,description}` objects — wanted names first in `$wanted` order (each reusing the **first** existing option with that name, by id), then every remaining existing option preserved **by id**. `color` resolved (existing color kept; new options get a cycling default). `description` defaulted to `""`.

- [ ] **Step 1: Write the failing test**

Create `scripts/tests/test-reconcile-options.sh`:

```bash
#!/usr/bin/env bash
# Offline unit tests for scripts/lib/reconcile-options.jq — ordering, id-keyed
# preservation (no data loss on duplicate names), and default color assignment.
# No network, no gh, no auth.
#
# Usage: bash scripts/tests/test-reconcile-options.sh
# Exit: 0 all pass, 1 otherwise.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JQF="$(dirname "$HERE")/lib/reconcile-options.jq"

pass=0
fail=0
ok()  { echo "PASS $1"; pass=$((pass + 1)); }
bad() { echo "FAIL $1: $2"; fail=$((fail + 1)); }

run() { # $1=existing json  $2=wanted json  -> ordered json on stdout
  jq -c -n --argjson existing "$1" --argjson wanted "$2" -f "$JQF"
}

# 1. Duplicate-named existing options: BOTH ids must survive (no drop).
existing='[{"id":"A","name":"Todo","color":"GRAY","description":""},
           {"id":"B","name":"Todo","color":"BLUE","description":""}]'
wanted='["Todo","Done"]'
out="$(run "$existing" "$wanted")"
ids="$(jq -r '[.[].id] | @csv' <<<"$out")"
if grep -q '"A"' <<<"$ids" && grep -q '"B"' <<<"$ids"; then
  ok "dup-name keeps both ids"
else
  bad "dup-name keeps both ids" "ids=$ids"
fi

# 2. Wanted order first, then extras preserved by id.
existing='[{"id":"X","name":"Custom","color":"RED","description":""},
           {"id":"Y","name":"Todo","color":"GRAY","description":""}]'
wanted='["Todo","Done"]'
out="$(run "$existing" "$wanted")"
names="$(jq -r '[.[].name] | join(",")' <<<"$out")"
if [[ "$names" == "Todo,Done,Custom" ]]; then
  ok "wanted-first then extras"
else
  bad "wanted-first then extras" "names=$names"
fi

# 3. Existing option reused by id + color preserved; new option gets a color.
todo_id="$(jq -r '.[] | select(.name=="Todo") | .id' <<<"$out")"
done_color="$(jq -r '.[] | select(.name=="Done") | .color' <<<"$out")"
if [[ "$todo_id" == "Y" && -n "$done_color" && "$done_color" != "null" ]]; then
  ok "reuse id + color, new gets color"
else
  bad "reuse id + color, new gets color" "todo_id=$todo_id done_color=$done_color"
fi

# 4. Empty existing: all wanted become new options (no ids).
out="$(run '[]' '["A","B"]')"
if [[ "$(jq -r 'length' <<<"$out")" == "2" && "$(jq -r 'map(has("id")) | any' <<<"$out")" == "false" ]]; then
  ok "empty existing -> all new"
else
  bad "empty existing -> all new" "$out"
fi

echo "----"
echo "PASS=$pass FAIL=$fail"
[[ "$fail" -eq 0 ]]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/tests/test-reconcile-options.sh`
Expected: FAIL — `jq: error ... Could not open "scripts/lib/reconcile-options.jq"` (file not yet created).

- [ ] **Step 3: Write the jq program**

Create `scripts/lib/reconcile-options.jq`:

```jq
# Compute the desired, ordered single-select option set for updateProjectV2Field.
#
# Inputs (via --argjson):
#   $existing : array of {id,name,color,description} as returned by the API (may be []).
#   $wanted   : array of desired option-name strings, in canonical order.
#
# Output: ordered array of {id?,name,color,description}. Wanted names come first in
# $wanted order, each reusing the FIRST existing option with that name (so its id,
# color and description — and therefore its cards — are preserved). Every remaining
# existing option is then appended, matched BY ID so duplicate-named options are
# never collapsed or dropped. Colors: existing kept; new options get a cycling
# default. This is the single source of truth for option order.
def colors: ["GRAY","BLUE","GREEN","YELLOW","ORANGE","RED","PURPLE","PINK"];

([ $wanted[] as $w | ([ $existing[] | select(.name == $w) ][0]) // {name: $w} ]) as $wantedOpts
| ([ $wantedOpts[] | .id ] | map(select(. != null))) as $usedIds
| ([ $existing[] | select((.id // null) as $i | ($i == null) or (($usedIds | index($i)) | not)) ]) as $extras
| ($wantedOpts + $extras)
| to_entries
| map(
    .key as $i
    | .value
    | {
        name: .name,
        color: (.color // colors[$i % (colors | length)]),
        description: (.description // "")
      }
      + (if .id then { id: .id } else {} end)
  )
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash scripts/tests/test-reconcile-options.sh`
Expected: `PASS=4 FAIL=0`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/reconcile-options.jq scripts/tests/test-reconcile-options.sh
git commit -m "fix(board): key single-select reconcile by id, extract to tested jq"
```

---

### Task 2: Wire bootstrap-project.sh to the extracted ordering + @json payload

Replaces the inline reconcile logic with the shared `reconcile-options.jq` output, builds the payload with jq `@json` (fixes escaping, finding 4), removes the duplicated order computation (finding 7), and collapses the double jq fork (finding 8).

**Files:**
- Modify: `scripts/bootstrap-project.sh` — add `SCRIPT_DIR` near the top; replace the reconcile block at lines ~116–151 inside `ensure_single_select`.

**Interfaces:**
- Consumes: `scripts/lib/reconcile-options.jq` from Task 1.

- [ ] **Step 1: Add SCRIPT_DIR near the top of the script**

After `IFS=$'\n\t'` (line 16), add:

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
```

- [ ] **Step 2: Replace the reconcile block**

Replace lines ~116–151 (from `# Desired option names as a JSON array.` through the closing `gh api graphql ... || echo "  WARN ..."` of the reconcile) with:

```bash
  # Desired option names as a JSON array (single jq process; finding 8).
  local wanted_json
  wanted_json="$(printf '%s\n' "$@" | jq -Rn '[inputs]')"

  # Compute the desired ordered option set ONCE — single source of truth for both
  # the skip-check and the mutation payload (finding 7). Wanted options come first
  # in canonical order (reusing each existing option's id/color/description by first
  # name match), then any remaining existing options preserved BY ID so duplicate
  # names are never dropped (finding 1). See scripts/lib/reconcile-options.jq.
  #
  # Idempotency: after one reconcile the field order becomes [wanted...]+[extras...],
  # so subsequent runs hit the skip-check and no-op. Residual risk (finding 6): if
  # the API renormalizes option order after we set it (e.g. pins a built-in option),
  # target_order never equals current_order and the mutation re-fires every run.
  # That is a benign no-op-mutation, not data loss, and is not cheaply detectable
  # client-side; revisit only if observed against the live API.
  local ordered
  ordered="$(jq -c -n --argjson existing "$existing" --argjson wanted "$wanted_json" \
    -f "$SCRIPT_DIR/lib/reconcile-options.jq")"

  # Skip the mutation when the field already has exactly the wanted options in the
  # wanted order (wanted first, then extras). Newline-join is safe: names are single-line.
  local target_order current_order
  target_order="$(jq -r '[ .[].name ] | join("\n")' <<<"$ordered")"
  current_order="$(jq -r '[ .[].name ] | join("\n")' <<<"$existing")"
  if [[ "$target_order" == "$current_order" ]]; then
    echo "Field '$name' already has the required options in order."
    return
  fi
  echo "Reconciling field '$name' options to desired order."

  # Build the GraphQL singleSelectOptions literal from the ordered set. jq @json
  # correctly escapes name/description (backslashes, quotes, control chars — finding 4);
  # color is a GraphQL enum, emitted unquoted.
  local combined
  combined="$(jq -r '
    map("{"
        + (if .id then "id:" + (.id | @json) + "," else "" end)
        + "name:" + (.name | @json)
        + ",color:" + .color
        + ",description:" + (.description | @json)
        + "}")
    | "[" + join(",") + "]"
  ' <<<"$ordered")"
  gh api graphql -f query="mutation{updateProjectV2Field(input:{fieldId:\"$fid\",singleSelectOptions:$combined}){projectV2Field{... on ProjectV2SingleSelectField{id}}}}" >/dev/null \
    || echo "  WARN: could not update '$name' options automatically; set them in the board UI: ${*}" >&2
```

Note: the old `def esc` and `def colors` inside the inline jq are gone — colors now live in `reconcile-options.jq`, escaping is `@json`.

- [ ] **Step 3: Syntax + reconcile regression check**

Run:
```bash
bash -n scripts/bootstrap-project.sh && echo "SYNTAX OK"
bash scripts/tests/test-reconcile-options.sh
```
Expected: `SYNTAX OK`, then `PASS=4 FAIL=0`.

- [ ] **Step 4: Escaping spot-check (the payload projection)**

Verify `@json` escapes a backslash-bearing name end-to-end:
```bash
printf '%s' '[{"name":"Blocked \\ Waiting","color":"GRAY","description":""}]' \
  | jq -r 'map("name:" + (.name | @json)) | join(",")'
```
Expected output exactly: `name:"Blocked \\ Waiting"` (valid GraphQL string escape).

- [ ] **Step 5: Commit**

```bash
git add scripts/bootstrap-project.sh
git commit -m "fix(board): reconcile options via shared jq, @json escaping, single jq fork"
```

---

### Task 3: Fix the board-link call (blocker, finding 2)

**Corrected during implementation.** The finding's suggested flag tweak does not work. `gh project link` overwrites `opts.owner` with the resolved **project** owner and then builds the repo-to-link as `<project-owner>/<repo>` (verified against gh v2.95.0 source: `link.go:157-161,197` and the "different owner" check at `validateRepoOrTeamFlag:140`). It therefore forces repo-owner == project-owner and **cannot** link this personal (`@me`) board to an org-owned repo at any flag combination. The real fix bypasses `gh project link` entirely and calls the owner-agnostic GraphQL mutation `linkProjectV2ToRepository` with the project + repo node IDs (the script already has `PROJECT_ID` and uses `gh api graphql` throughout).

**Files:**
- Modify: `scripts/bootstrap-project.sh` lines ~159–173 (the `--- Link board to repo ---` block).
- Test: `scripts/tests/test-bootstrap-link.sh`

- [ ] **Step 1: Write the failing test**

Create `scripts/tests/test-bootstrap-link.sh`:

```bash
#!/usr/bin/env bash
# Asserts the board link is owner-agnostic: uses the linkProjectV2ToRepository
# GraphQL mutation (works for personal AND org-owned repos), NOT owner-coupled
# `gh project link`. Static source check — deterministic, no network, no auth.
#
# Usage: bash scripts/tests/test-bootstrap-link.sh
# Exit: 0 pass, 1 fail.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$(dirname "$HERE")/bootstrap-project.sh"

fail=0
# Ignore comment lines — only a real invocation counts.
if grep -vE '^[[:space:]]*#' "$SCRIPT" | grep -qE 'gh project link'; then
  echo "FAIL link-owner-agnostic: still uses owner-coupled 'gh project link'"
  fail=1
fi
if ! grep -q 'linkProjectV2ToRepository' "$SCRIPT"; then
  echo "FAIL link-owner-agnostic: linkProjectV2ToRepository mutation not found"
  fail=1
fi
[[ "$fail" -eq 0 ]] && echo "PASS link-owner-agnostic"
exit "$fail"
```

Note: a full end-to-end shim run is out of scope — the script preamble (`gh auth status`, project create/view/field-list) would need extensive mocking already exercised conceptually by `test-day0.sh`. The static assertion is deterministic and pins the regression.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/tests/test-bootstrap-link.sh`
Expected: `FAIL link-no-bare-repo` (current code passes `--repo "$REPO"`).

- [ ] **Step 3: Fix the link block**

Replace lines ~159–173 with:

```bash
# --- Link board to repo ---------------------------------------------------------
# `gh project link` ties the repo owner to the PROJECT owner — it builds the
# repo-to-link reference as <project-owner>/<repo> and rejects a mismatched
# --owner — so it cannot link this personal (@me) board to an organization-owned
# repo. Link via the owner-agnostic GraphQL mutation instead: resolve the repo's
# node id, then linkProjectV2ToRepository against the board's PROJECT_ID. This
# works for personal and org-owned repos alike (subject to the caller's repo
# permissions) and is idempotent. Surface the real outcome: an already-linked
# board is benign, but a permission/scope failure must not masquerade as success.
repo_owner="${OWNER_REPO%/*}"
if repo_id="$(gh api graphql -f query='
    query($owner:String!,$name:String!){repository(owner:$owner,name:$name){id}}
  ' -f owner="$repo_owner" -f name="$REPO" --jq '.data.repository.id' 2>&1)" && [[ -n "$repo_id" && "$repo_id" != "null" ]]; then
  if link_out="$(gh api graphql -f query='
      mutation($projectId:ID!,$repositoryId:ID!){
        linkProjectV2ToRepository(input:{projectId:$projectId,repositoryId:$repositoryId}){repository{id}}
      }' -f projectId="$PROJECT_ID" -f repositoryId="$repo_id" 2>&1)"; then
    echo "Linked board to $OWNER_REPO."
  elif printf '%s' "$link_out" | grep -qi "already"; then
    echo "Board already linked to $OWNER_REPO."
  else
    echo "WARNING: failed to link board to $OWNER_REPO — confirm you have write access to the repo, then re-run:" >&2
    printf '%s\n' "$link_out" >&2
  fi
else
  echo "WARNING: could not resolve the node id for $OWNER_REPO; board not linked:" >&2
  printf '%s\n' "$repo_id" >&2
fi
```

Note: linking a **user** (`@me`) project to an **org** repo requires that your token can write to that repo; the board itself stays personal. If instead you want the board owned by the org for org repos, that is a larger change (parameterize every `--owner "@me"` in the script by the repo owner) — out of scope here, flagged as follow-up.

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
bash scripts/tests/test-bootstrap-link.sh
bash -n scripts/bootstrap-project.sh && echo "SYNTAX OK"
```
Expected: `PASS link-owner-agnostic`, then `SYNTAX OK`.

- [ ] **Step 5: Commit**

```bash
git add scripts/bootstrap-project.sh scripts/tests/test-bootstrap-link.sh
git commit -m "fix(board): link via linkProjectV2ToRepository so org repos link"
```

---

### Task 4: Verify `id` acceptance (finding 5); idempotency note landed in Task 2

The whole card-preserving reconcile assumes `ProjectV2SingleSelectFieldOptionInput` accepts `id`. This cannot be checked offline (needs auth), so it is a gated verification, not a code edit. (Finding 6's residual-risk comment already lands in Task 2 Step 2.)

- [ ] **Step 1: Verify the input type accepts `id` (requires `gh auth login` / `GH_TOKEN`)**

Run:
```bash
gh api graphql -f query='query{__type(name:"ProjectV2SingleSelectFieldOptionInput"){inputFields{name}}}' \
  --jq '.data.__type.inputFields[].name'
```
Expected: the list **includes `id`** (alongside `name`, `color`, `description`).

- **If `id` is present:** the reconcile approach is sound — nothing more to change.
- **If `id` is absent:** STOP. The current design (and this plan's Task 1/2) cannot preserve cards via `id`; the mutation would either error or recreate options and detach cards. Contingency: fall back to **append-only** reconcile (only ever ADD missing options, never send the full replacement set) and open a follow-up to revisit ordering. Do not ship Task 2's full-replacement payload in that case.

---

## Verification (end to end)

Offline (no auth):
```bash
bash -n scripts/bootstrap-project.sh && echo "SYNTAX OK"
bash scripts/tests/test-reconcile-options.sh   # expect PASS=4 FAIL=0
bash scripts/tests/test-bootstrap-link.sh      # expect PASS link-owner-agnostic
pre-commit run --all-files                     # all gates green
```

Live (needs `gh auth login` + `project` scope; ideally a scratch org repo):
```bash
# 1. id-acceptance preflight (Task 4 Step 1) returns a list containing 'id'.
# 2. From inside an ORG-owned repo checkout:
APPLY=true bash scripts/bootstrap-project.sh
#    Expect: "Linked board to <org>/<repo>." (or "already linked") — NOT a link failure.
# 3. Add a custom Status option in the board UI, then re-run twice:
APPLY=true bash scripts/bootstrap-project.sh
APPLY=true bash scripts/bootstrap-project.sh
#    Expect: second consecutive run prints "already has the required options in order"
#    (idempotent), and the custom option is still present with its cards intact.
```

## Self-review notes

- Findings 1,3,4,7,8 land in Tasks 1–2; finding 2 in Task 3; finding 5 in Task 4; finding 6 comment in Task 2 Step 2. All 8 mapped.
- No placeholders: every code + jq block is complete; every command has an expected result.
- Type/name consistency: `reconcile-options.jq` output shape (`{id?,name,color,description}`) is what Task 2's `combined`/`target_order` projections read; `SCRIPT_DIR` defined in Task 2 Step 1 is used in Task 2 Step 2.
- Blockers (Tasks 2–3) are independent and can ship before Task 4's live verification if auth is unavailable — but Task 2 must not be trusted in production until Task 4 Step 1 confirms `id` acceptance.
