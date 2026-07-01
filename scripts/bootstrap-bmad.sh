#!/usr/bin/env bash
set -euo pipefail

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
