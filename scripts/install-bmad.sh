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

if [[ -f "$MARKER_FILE" ]] && grep -q "^${BMAD_VERSION}$" "$MARKER_FILE"; then
  echo "BMAD already installed at ${BMAD_VERSION}."
  exit 0
fi

npx -y "bmad-method@${BMAD_VERSION}" install --modules bmm --tools claude-code --yes

echo "$BMAD_VERSION" > "$MARKER_FILE"
echo "BMAD install complete."
