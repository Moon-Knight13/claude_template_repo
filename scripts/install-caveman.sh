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

# Point the user-level statusLine at the plugin's statusline script. The script
# lives under a hash-versioned plugin cache path that changes on every plugin
# update, so this must be (re)resolved at container start rather than hardcoded
# in template settings. Runs on every start — the marker above only skips the
# download.
configure_statusline() {
  local settings="$MARKER_DIR/settings.json"
  local script="" candidate

  for candidate in "$MARKER_DIR"/plugins/cache/caveman/caveman/*/src/hooks/caveman-statusline.sh; do
    if [[ -f "$candidate" ]] && { [[ -z "$script" ]] || [[ "$candidate" -nt "$script" ]]; }; then
      script="$candidate"
    fi
  done

  if [[ -z "$script" ]]; then
    echo "WARN: caveman statusline script not found under plugin cache; skipping statusline setup."
    return 0
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo "WARN: jq not available; skipping statusline setup."
    return 0
  fi

  if [[ ! -f "$settings" ]]; then
    echo '{}' > "$settings"
  elif ! jq -e . "$settings" >/dev/null 2>&1; then
    echo "WARN: $settings is not valid JSON; refusing to touch it. Fix it, then rerun."
    return 0
  fi

  local current
  current="$(jq -r '.statusLine.command // ""' "$settings")"
  if [[ "$current" == *"caveman-statusline.sh"* && "$current" == *"$script"* ]]; then
    echo "Caveman statusline already configured."
    return 0
  fi
  if [[ -n "$current" && "$current" != *"caveman-statusline.sh"* ]]; then
    echo "Custom statusLine already set in $settings; leaving it alone."
    return 0
  fi

  local tmp
  tmp="$(mktemp)"
  jq --arg cmd "bash \"$script\"" \
    '.statusLine = {type: "command", command: $cmd}' "$settings" > "$tmp"
  mv "$tmp" "$settings"
  echo "Caveman statusline configured: $script"
}

configure_statusline

# Mode activation is session-based; this file documents intended default mode.
echo "$CAVEMAN_MODE" > "$MARKER_DIR/.caveman-default-mode"
echo "Caveman install complete. Default mode: $CAVEMAN_MODE"
