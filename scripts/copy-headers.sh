#!/usr/bin/env bash
set -euo pipefail

HOSTING_TARGET="${HOSTING_TARGET:-}"
DIST_DIR="${DIST_DIR:-dist}"

if [ -z "$HOSTING_TARGET" ]; then
  echo "HOSTING_TARGET not set — skipping headers copy."
  echo "Set HOSTING_TARGET to 'cloudflare' or 'netlify' to copy headers."
  exit 0
fi

case "$HOSTING_TARGET" in
  cloudflare)
    echo "Copying Cloudflare Pages headers to $DIST_DIR/_headers"
    cp ops/headers/cloudflare/_headers "$DIST_DIR/_headers"
    ;;
  netlify)
    echo "Copying Netlify headers to $DIST_DIR/_headers"
    cp ops/headers/netlify/_headers "$DIST_DIR/_headers"
    ;;
  *)
    echo "Unknown HOSTING_TARGET: $HOSTING_TARGET"
    echo "Supported values: cloudflare, netlify"
    exit 1
    ;;
esac

echo "Headers copied successfully."
