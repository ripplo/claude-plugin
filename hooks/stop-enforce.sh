#!/usr/bin/env bash
set -uo pipefail

INPUT=$(cat)
AGENT_ID=$(echo "$INPUT" | jq -r '.agent_id // empty')
if [ -n "$AGENT_ID" ]; then
  exit 0
fi

cd "$CLAUDE_PROJECT_DIR"

# Skip silently if Ripplo isn't set up in this project.
if [ ! -d ".ripplo" ]; then
  exit 0
fi

ERRORS=""

CHANGED_TESTS=$(git diff --name-only HEAD -- .ripplo/tests 2>/dev/null | awk -F/ '/\.ts$/ { sub(/\.ts$/, "", $NF); print $NF }')
CHANGED_IDS=$(echo "$CHANGED_TESTS" | tr '\n' ' ' | sed 's/ *$//')

LINT_ARGS=()
if [ -n "$CHANGED_IDS" ]; then
  # shellcheck disable=SC2206
  LINT_ARGS=(--require-implemented $CHANGED_IDS)
fi
LINT_OUTPUT=$(npx ripplo lint "${LINT_ARGS[@]}" 2>&1) || {
  ERRORS="${ERRORS}--- Ripplo Lint ---\n${LINT_OUTPUT}\n\n"
}

UNIMPL=$(npx ripplo status --format summary 2>/dev/null || true)
if [ -n "$UNIMPL" ]; then
  ERRORS="${ERRORS}--- Unimplemented stubs remain ---\n${UNIMPL}\n\n"
fi

if [ -n "$CHANGED_IDS" ] && npx ripplo doctor > /dev/null 2>&1; then
  # shellcheck disable=SC2086
  RUN_OUTPUT=$(npx ripplo run $CHANGED_IDS 2>&1) || {
    FAILED_RUNS=$(echo "$RUN_OUTPUT" | grep -A5 "FAILED" || true)
    if [ -n "$FAILED_RUNS" ]; then
      ERRORS="${ERRORS}--- Ripplo Run Failures (${CHANGED_IDS}) ---\n${FAILED_RUNS}\n\n"
    fi
  }
fi

if [ -n "$ERRORS" ]; then
  echo -e "$ERRORS" >&2
  exit 2
fi
