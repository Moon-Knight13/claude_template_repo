#!/usr/bin/env bash
# Install official Anthropic Claude Code plugins.
# Idempotent — skips plugins that are already installed.
# Plugins are stored in the Claude Code config volume (/home/node/.claude)
# and persist across container rebuilds.
set -euo pipefail

plugins=(
  skill-creator@claude-plugins-official
  frontend-design@claude-plugins-official
  code-review@claude-plugins-official
  superpowers@claude-plugins-official
  github@claude-plugins-official
  commit-commands@claude-plugins-official
  semgrep@claude-plugins-official
)

installed=$(claude plugin list 2>/dev/null || echo "")

for plugin in "${plugins[@]}"; do
  name="${plugin%%@*}"
  if echo "$installed" | grep -q "${name}"; then
    echo "Already installed: ${name}"
  else
    echo "Installing: ${name}"
    claude plugin install "${plugin}"
  fi
done

echo "Claude Code plugin installation complete."
