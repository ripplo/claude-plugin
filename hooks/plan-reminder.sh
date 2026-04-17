#!/usr/bin/env bash
set -uo pipefail

INPUT=$(cat)
MODE=$(echo "$INPUT" | jq -r '.mode // empty')

# Only nudge during plan mode
if [ "$MODE" != "plan" ]; then
  exit 0
fi

cd "$CLAUDE_PROJECT_DIR"

# Skip silently if Ripplo isn't set up in this project.
if [ ! -d ".ripplo" ]; then
  exit 0
fi

SUMMARY=$(npx ripplo status --format summary 2>/dev/null || true)

if [ -n "$SUMMARY" ]; then
  {
    echo "Existing .notImplemented() stubs — list any you plan to implement under a \"Tests to implement\" section:"
    echo "$SUMMARY" | sed 's/^/  /'
    echo "Also add new stubs for any user flow this plan changes."
  } >&2
fi
exit 0
