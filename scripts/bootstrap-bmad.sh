#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=scripts/lib/subsystems.sh disable=SC1090,SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/subsystems.sh"

# Without this guard the missing-document check below turns a deliberate
# "this repo does not use BMAD" into a hard failure of postStartCommand.
if ! subsystem_enabled bmad; then
  subsystem_skip_notice bmad "BMAD bootstrap"
  exit 0
fi

required_file="docs/BMAD_WORKFLOW.md"

if [[ ! -f "$required_file" ]]; then
  echo "ERROR: Missing required BMAD workflow document: $required_file"
  echo "Restore this file from template history or author it explicitly for this project."
  exit 1
fi

if [[ ! -s "$required_file" ]]; then
  echo "ERROR: BMAD workflow document is empty: $required_file"
  echo "Populate it with project-specific workflow guidance."
  exit 1
fi

echo "BMAD bootstrap validation complete."
