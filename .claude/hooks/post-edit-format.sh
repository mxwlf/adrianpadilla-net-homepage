#!/usr/bin/env bash
set -euo pipefail

# Extract the file path from the tool input
FILE="$(jq -r '.tool_input.file_path // .tool_input.path // empty' </dev/stdin)"

if [ -z "$FILE" ]; then
  exit 0
fi

# Only format if prettier is available and the file exists
if command -v npx &>/dev/null && [ -f "$FILE" ]; then
  npx --yes prettier --write "$FILE" 2>/dev/null || true
fi

exit 0
