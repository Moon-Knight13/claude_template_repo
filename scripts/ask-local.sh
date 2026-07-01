#!/usr/bin/env bash
# Thin wrapper for the Ollama generate API.
# Used by the CLAUDE.md Task Routing Protocol and CI scripts.
# Not intended for direct end-user use — prefer the Claude Code session for interactive work.
#
# Usage: ask-local.sh <prompt text...>
# Returns: the model's response text on stdout, exits non-zero on failure.
set -euo pipefail

LOCAL_MODEL_ENDPOINT="${LOCAL_MODEL_ENDPOINT:-http://host.docker.internal:11434}"
LOCAL_MODEL_MODEL="${LOCAL_MODEL_MODEL:-qwen2.5-coder:7b}"

if [[ $# -eq 0 ]]; then
    echo "Usage: ask-local.sh <prompt text>" >&2
    exit 1
fi

PROMPT="$*"

curl -sfS "${LOCAL_MODEL_ENDPOINT}/api/generate" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg model "$LOCAL_MODEL_MODEL" --arg prompt "$PROMPT" \
        '{model: $model, prompt: $prompt, stream: false}')" \
    | jq -r '.response'
