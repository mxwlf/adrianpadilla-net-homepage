#!/usr/bin/env bash
set -euo pipefail

# Run lint as a smoke test after task completion
make lint 2>&1 || {
  echo "CI smoke test (make lint) failed. Please fix lint errors before continuing." >&2
  exit 1
}

exit 0
