# CI Script Hooks

When a language marker exists, matching scripts in this folder are required.

Examples:
- scripts/ci/lint-node.sh
- scripts/ci/test-node.sh
- scripts/ci/lint-python.sh
- scripts/ci/test-python.sh

If a marker file is detected and scripts are missing, CI fails by design.
