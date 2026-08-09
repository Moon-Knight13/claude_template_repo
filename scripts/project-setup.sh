#!/usr/bin/env bash
# Project-specific container setup — the derivative's extension point.
#
# Every other entry in devcontainer.json's postStartCommand is template-owned,
# which leaves a derivative with nowhere to run its own start-time setup:
# editing devcontainer.json downstream works until the next template-sync
# reverts it (`-X theirs`), and adding devcontainer.json to .templatesyncignore
# would sever the channel that carries devcontainer security fixes downstream.
# This script exists so that dilemma does not arise.
#
# The template ships it as a no-op. To use it in a derivative:
#
#   1. Replace the body below with whatever your project needs at container
#      start (extra runtime deps, symlinks, fetching a fixture, …).
#   2. Add `scripts/project-setup.sh` to .templatesyncignore so sync stops
#      proposing the template's no-op version. Do this only AFTER the file
#      exists locally — listing a path sync has not delivered yet means it
#      never arrives, and postStartCommand then dies with exit 127.
#
# Two constraints worth respecting:
#
#   - Exit 0 unless the failure genuinely warrants a broken container. This
#     runs last in a `&&` chain, so a non-zero exit marks the whole
#     postStartCommand failed.
#   - Network egress is deny-by-default (see .devcontainer/init-firewall.sh).
#     registry.npmjs.org, pypi.org and files.pythonhosted.org are reachable;
#     anything else needs adding to the allowlist there first.

set -euo pipefail

echo "project-setup.sh: nothing to do (template default)."
echo "  Derivatives override this — see the comments in this file."
