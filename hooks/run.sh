#!/bin/sh
root="${CLAUDE_PROJECT_DIR:-$PWD}"
if [ -f "$root/node_modules/ripplo/dist/hook.js" ]; then
  exec node "$root/node_modules/ripplo/dist/hook.js" "$1"
fi
if [ -f "$root/node_modules/ripplo/dist/index.js" ]; then
  exec node "$root/node_modules/ripplo/dist/index.js" hook "$1"
fi
if [ -x "$root/node_modules/.bin/ripplo-hook" ]; then
  exec "$root/node_modules/.bin/ripplo-hook" "$1"
fi
if [ -x "$root/node_modules/.bin/ripplo" ]; then
  exec "$root/node_modules/.bin/ripplo" hook "$1"
fi
exec npx ripplo hook "$1"
