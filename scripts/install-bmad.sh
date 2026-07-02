#!/usr/bin/env bash
set -euo pipefail

if [[ "${BMAD_ENABLED:-1}" != "1" ]]; then
  echo "BMAD install disabled (BMAD_ENABLED=${BMAD_ENABLED})."
  exit 0
fi

BMAD_VERSION="${BMAD_VERSION:-6.9.0}"
MARKER_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
MARKER_FILE="$MARKER_DIR/.template-bmad-version"
mkdir -p "$MARKER_DIR"

# The installer writes its output relative to the cwd, so pin to the repo root
# no matter where this script is invoked from.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# BMAD_FORCE=1 bypasses the version marker (operator knob for cleanup reinstalls).
if [[ "${BMAD_FORCE:-0}" != "1" ]] \
  && [[ -f "$MARKER_FILE" ]] && grep -q "^${BMAD_VERSION}$" "$MARKER_FILE"; then
  echo "BMAD already installed at ${BMAD_VERSION}."
  exit 0
fi

npx -y "bmad-method@${BMAD_VERSION}" install --directory "$REPO_ROOT" \
  --modules bmm --tools claude-code --yes

# Only record success if the installer actually produced output at the repo
# root; otherwise leave the marker absent so the next start retries.
if [[ ! -d "$REPO_ROOT/_bmad" ]]; then
  echo "ERROR: BMAD installer finished but $REPO_ROOT/_bmad is missing — not writing version marker." >&2
  exit 1
fi

echo "$BMAD_VERSION" > "$MARKER_FILE"
echo "BMAD install complete."
