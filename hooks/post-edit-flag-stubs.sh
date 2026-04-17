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

SUMMARY=$(npx ripplo status --format summary 2>/dev/null | grep '^tests:' || true)

if [ -n "$SUMMARY" ]; then
  echo "Reminder: .notImplemented() stubs still present — ${SUMMARY}" >&2
fi
exit 0
