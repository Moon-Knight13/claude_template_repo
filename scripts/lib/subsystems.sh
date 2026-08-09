#!/usr/bin/env bash
# Reads template.conf and answers "is this optional subsystem enabled?".
#
# Sourced by scripts/validate-template.sh and by the install-* / bootstrap-*
# scripts the devcontainer runs at container start.
#
# Every subsystem defaults to ENABLED when template.conf is absent or does not
# mention it, so a derived repository that predates template.conf behaves
# exactly as before.
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/subsystems.sh"
#   subsystem_enabled BMAD || exit 0

# Resolve the repository root from this file's location so callers can be run
# from anywhere.
_subsystems_repo_root() {
  local here
  here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  # scripts/lib -> scripts -> repo root
  (cd "$here/../.." && pwd)
}

# subsystem_enabled <NAME>
# NAME is the suffix after SUBSYSTEM_, case-insensitive: ROUTING, BOARD, BMAD,
# CAVEMAN, DAY0. Returns 0 when enabled, 1 when explicitly disabled.
subsystem_enabled() {
  local name=${1:?subsystem_enabled requires a subsystem name}
  local key value conf

  # Uppercase without requiring bash 4 parameter expansion.
  key="SUBSYSTEM_$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]')"
  conf="$(_subsystems_repo_root)/template.conf"

  # No config file: everything is on.
  [[ -f "$conf" ]] || return 0

  # Read the last assignment for the key, tolerating surrounding whitespace,
  # inline comments and quotes. Deliberately does NOT source the file, so a
  # malformed or hostile template.conf cannot execute code.
  value=$(sed -n -E "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*([^#]*).*/\1/p" "$conf" | tail -n 1)
  value=${value%"${value##*[![:space:]]}"}   # strip trailing whitespace
  value=${value#\"}; value=${value%\"}
  value=${value#\'}; value=${value%\'}
  value=$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')

  case "$value" in
    false | 0 | no | off) return 1 ;;
    *) return 0 ;;
  esac
}

# subsystem_skip_notice <NAME> <what>
# Uniform message so a skipped install reads as deliberate, not broken.
subsystem_skip_notice() {
  echo "-- ${2:-$1} skipped: SUBSYSTEM_$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')=false in template.conf"
}
