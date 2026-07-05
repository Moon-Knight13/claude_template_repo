#!/usr/bin/env bash
# Asserts the board link is owner-agnostic. Static source check — deterministic,
# no network, no auth.
#
# `gh project link` ties the repo owner to the project owner and therefore cannot
# link a personal (@me) board to an org-owned repo. The link must instead use the
# linkProjectV2ToRepository GraphQL mutation, which works for personal AND
# org-owned repos.
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
