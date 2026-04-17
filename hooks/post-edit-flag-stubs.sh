#!/usr/bin/env bash
set -uo pipefail

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only on app code edits
case "$FILE" in
  */apps/web/*|*/apps/server/*) ;;
  *) exit 0 ;;
esac

cd "$CLAUDE_PROJECT_DIR"

# Skip silently if Ripplo isn't set up in this project.
if [ ! -d ".ripplo" ]; then
  exit 0
fi

SUMMARY=$(npx ripplo status --format summary 2>/dev/null | grep '^tests:' || true)

if [ -n "$SUMMARY" ]; then
  echo "Reminder: .notImplemented() stubs still present — ${SUMMARY}" >&2
fi
exit 0
