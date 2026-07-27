#!/usr/bin/env bash
set -euo pipefail

COMMAND="$(jq -r '.tool_input.command' </dev/stdin)"

# Block destructive patterns
if echo "$COMMAND" | grep -Eq 'rm -rf|git push --force|curl .*\| bash'; then
  # Exit 2 => blocking error (denies tool execution)
  echo "Blocked dangerous command: $COMMAND" >&2
  exit 2
fi

exit 0
