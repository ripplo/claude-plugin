#!/usr/bin/env bash
set -uo pipefail

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
if [ "$TOOL" != "ExitPlanMode" ]; then
  exit 0
fi

cd "$CLAUDE_PROJECT_DIR"

# Find the plan file referenced by the system — fall back to most recent in ~/.claude/plans/
PLAN_FILE=$(echo "$INPUT" | jq -r '.context.plan_file_path // empty')
if [ -z "$PLAN_FILE" ] || [ ! -f "$PLAN_FILE" ]; then
  PLAN_FILE=$(ls -t "$HOME/.claude/plans"/*.md 2>/dev/null | head -1 || true)
fi
if [ -z "$PLAN_FILE" ] || [ ! -f "$PLAN_FILE" ]; then
  exit 0
fi

# Does the plan claim to touch user-facing app code?
if ! grep -qiE 'apps/web|apps/server|route|component|user flow' "$PLAN_FILE"; then
  exit 0
fi

# If it touches app code, it must reference .ripplo/tests or a "Tests to implement" section
if grep -qE '\.ripplo/tests|Tests to implement' "$PLAN_FILE"; then
  exit 0
fi

echo "Plan touches user-facing code but cites no .ripplo/tests stubs." >&2
echo "Add a 'Tests to implement' section listing .notImplemented() test ids, or reference existing .ripplo/tests files." >&2
exit 2
