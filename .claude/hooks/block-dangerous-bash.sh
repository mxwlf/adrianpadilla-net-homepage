#!/usr/bin/env bash
set -euo pipefail

COMMAND="$(jq -r '.tool_input.command' </dev/stdin)"

# Block destructive patterns.
#
# `--force-with-lease` is deliberately NOT blocked. It refuses the push when the
# remote ref is not where the last fetch said it was, so it cannot silently
# clobber a commit that arrived in the meantime -- the failure mode bare
# `--force` has. Blocking both left no sanctioned way to perform an authorized
# history correction, and the workaround for that is always worse than the rule.
#
# `--force([^-]|$)` is the portable way to say "--force, but not
# --force-with-lease". BSD grep has no -P, so a `(?!...)` lookahead is not
# available: it would be matched literally and quietly block nothing.
if echo "$COMMAND" | grep -Eq 'rm -rf|git push --force([^-]|$)|curl .*\| bash'; then
  # Exit 2 => blocking error (denies tool execution)
  echo "Blocked dangerous command: $COMMAND" >&2
  exit 2
fi

exit 0
