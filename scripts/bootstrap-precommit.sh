#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f ".pre-commit-config.yaml" ]]; then
  echo "No .pre-commit-config.yaml found. Skipping pre-commit bootstrap."
  exit 0
fi

min_precommit_version="3.7.0"

version_lt() {
  # Returns success if $1 < $2
  [[ "$(printf '%s\n' "$1" "$2" | sort -V | head -n1)" != "$2" ]]
}

install_or_upgrade_precommit() {
  if ! command -v python3 >/dev/null 2>&1; then
    echo "WARNING: python3 is required to install pre-commit. Skipping."
    exit 0
  fi

  python3 -m ensurepip --upgrade >/dev/null 2>&1 || true
  python3 -m pip install --user --break-system-packages "pre-commit>=${min_precommit_version}"
  export PATH="$HOME/.local/bin:$PATH"
}

if ! command -v pre-commit >/dev/null 2>&1; then
  install_or_upgrade_precommit
else
  current_precommit_version="$(pre-commit --version | awk '{print $2}')"
  if version_lt "$current_precommit_version" "$min_precommit_version"; then
    install_or_upgrade_precommit
  fi
fi

pre-commit install

if [[ "${PRECOMMIT_INSTALL_HOOK_ENVS:-0}" == "1" ]]; then
  pre-commit install --install-hooks
fi

# Keep startup deterministic; only update hook pins when explicitly requested.
if [[ "${PRECOMMIT_AUTOUPDATE:-0}" == "1" ]]; then
  pre-commit autoupdate
fi

echo "pre-commit bootstrap complete."
