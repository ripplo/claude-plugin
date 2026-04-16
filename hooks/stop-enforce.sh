#!/usr/bin/env bash
set -uo pipefail

# Skip stop hook for subagents
INPUT=$(cat)
AGENT_ID=$(echo "$INPUT" | jq -r '.agent_id // empty')
if [ -n "$AGENT_ID" ]; then
  exit 0
fi

cd "$CLAUDE_PROJECT_DIR"
ERRORS=""

# ---------- Lint all tests ----------
LINT_OUTPUT=$(npx ripplo lint 2>&1) || {
  ERRORS="${ERRORS}--- Ripplo Lint ---\n${LINT_OUTPUT}\n\n"
}

# ---------- Check for notImplemented tests ----------
LIST_OUTPUT=$(npx ripplo list 2>&1) || true
NOT_IMPL=$(echo "$LIST_OUTPUT" | grep "notImplemented" || true)
if [ -n "$NOT_IMPL" ]; then
  ERRORS="${ERRORS}--- Unimplemented Tests ---\nThe following tests are marked notImplemented and need implementation:\n${NOT_IMPL}\n\n"
fi

# ---------- Run tests if doctor passes ----------
if npx ripplo doctor > /dev/null 2>&1; then
  RUN_OUTPUT=$(npx ripplo run 2>&1) || {
    FAILED_RUNS=$(echo "$RUN_OUTPUT" | grep -A5 "FAILED" || true)
    if [ -n "$FAILED_RUNS" ]; then
      ERRORS="${ERRORS}--- Ripplo Run Failures ---\n${FAILED_RUNS}\n\n"
    fi
  }
fi

# ---------- Report ----------
if [ -n "$ERRORS" ]; then
  echo -e "$ERRORS" >&2
  exit 2
fi
