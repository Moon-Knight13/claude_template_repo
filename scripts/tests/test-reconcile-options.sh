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
