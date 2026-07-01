#!/usr/bin/env bash
set -euo pipefail

if [[ "${CAVEMAN_ENABLED:-1}" != "1" ]]; then
  echo "Caveman install disabled (CAVEMAN_ENABLED=${CAVEMAN_ENABLED})."
  exit 0
fi

CAVEMAN_VERSION="${CAVEMAN_VERSION:-v1.9.0}"
CAVEMAN_MODE="${CAVEMAN_MODE:-lite}"
CAVEMAN_INSTALL_SHA256="${CAVEMAN_INSTALL_SHA256:-}"
MARKER_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
MARKER_FILE="$MARKER_DIR/.template-caveman-version"
mkdir -p "$MARKER_DIR"

if [[ -f "$MARKER_FILE" ]] && grep -q "^${CAVEMAN_VERSION}$" "$MARKER_FILE"; then
  echo "Caveman already installed at ${CAVEMAN_VERSION}."
else
  INSTALL_URL="https://raw.githubusercontent.com/JuliusBrussee/caveman/${CAVEMAN_VERSION}/install.sh"
  INSTALL_FILE="$(mktemp)"

  curl -fsSL "$INSTALL_URL" -o "$INSTALL_FILE"

  if [[ -z "$CAVEMAN_INSTALL_SHA256" ]]; then
    echo "ERROR: CAVEMAN_INSTALL_SHA256 is required for secure installer verification."
    echo "Set it in your environment or .env (do not hardcode secrets in repo files)."
    rm -f "$INSTALL_FILE"
    exit 1
  fi

  ACTUAL_SHA256="$(sha256sum "$INSTALL_FILE" | awk '{print $1}')"
  if [[ "$ACTUAL_SHA256" != "$CAVEMAN_INSTALL_SHA256" ]]; then
    echo "ERROR: Caveman installer checksum mismatch."
    echo "Expected: $CAVEMAN_INSTALL_SHA256"
    echo "Actual:   $ACTUAL_SHA256"
    rm -f "$INSTALL_FILE"
    exit 1
  fi

  bash "$INSTALL_FILE" --only claude --non-interactive
  rm -f "$INSTALL_FILE"
  echo "$CAVEMAN_VERSION" > "$MARKER_FILE"
fi

# Mode activation is session-based; this file documents intended default mode.
echo "$CAVEMAN_MODE" > "$MARKER_DIR/.caveman-default-mode"
echo "Caveman install complete. Default mode: $CAVEMAN_MODE"
