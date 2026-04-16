#!/usr/bin/env bash
set -uo pipefail

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path')

# Only lint .ripplo/**/*.ts files
case "$FILE" in
  */.ripplo/*.ts|*/.ripplo/**/*.ts) ;;
  *) exit 0 ;;
esac

cd "$CLAUDE_PROJECT_DIR"

# Run full lint (compilation always processes the whole .ripplo/ tree)
ERRORS=$(npx ripplo lint 2>&1) || {
  echo "$ERRORS" >&2
  exit 2
}
