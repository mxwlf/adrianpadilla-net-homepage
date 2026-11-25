#!/usr/bin/env bash
#
# Asserts the security headers a live URL serves.
#
#   check-security-headers.sh URL
#   check-security-headers.sh --headers FILE   # a saved `curl -I` dump (tests)
#
# Run by monitor.yml against production and by release.yml against the test
# environment, through `make check-headers URL=...`. Exits 1 if a required
# header is missing, has the wrong value, or is sent more than once with
# different values. Known gaps are a `::notice::`, not a failure: a check that
# is red for a reason nobody intends to fix this week teaches you to ignore it.

set -euo pipefail

if [ "${1:-}" = "--headers" ] && [ -n "${2:-}" ]; then
  HEADER_FILE="$2"
  STATUS="$(tr -d '\r' < "$HEADER_FILE" | grep -E '^HTTP/' | tail -n1 | awk '{print $2}')"
elif [ -n "${1:-}" ]; then
  URL="$1"
  echo "Checking security headers for $URL"

  # Reachability and status are settled before a single header is judged. An
  # unreachable host must report as an unreachable host: "six security headers
  # are missing" would send the next person looking for the wrong incident. A
  # non-200 also means the headers may have come from an error path, where the
  # host config does not necessarily apply.
  HEADER_FILE="$(mktemp)"
  trap 'rm -f "$HEADER_FILE"' EXIT
  if ! STATUS="$(curl -sS --retry 3 --retry-all-errors --max-time 20 \
    -I -o "$HEADER_FILE" -w '%{http_code}' "$URL")"; then
    echo "::error::could not reach $URL — no headers were checked"
    exit 1
  fi
else
  echo "usage: $0 URL | $0 --headers FILE" >&2
  exit 2
fi

HEADERS="$(tr -d '\r' < "$HEADER_FILE")"
printf '%s\n' "$HEADERS"

if [ "$STATUS" != "200" ]; then
  echo "::error::${URL:-$HEADER_FILE} returned HTTP $STATUS — headers not asserted"
  exit 1
fi

FAILED=0

# Every copy of header $1, one per line.
copies_of() {
  printf '%s\n' "$HEADERS" | sed -nE "s/^[[:space:]]*$1:[[:space:]]*(.*)/\1/Ip"
  return 0
}

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# A header this repo declares should replace the one Azure adds by default, not
# be sent next to it. Browsers do not agree on which copy wins (the first for
# HSTS and nosniff, the last for Referrer-Policy), so copies that differ fail
# and the caller judges nothing. Identical copies only get a notice, because
# every browser reads them the same way.
copies_agree() {
  local count distinct
  count="$(copies_of "$1" | wc -l | tr -d ' ')"
  [ "$count" -gt 1 ] || return 0
  distinct="$(copies_of "$1" | tr '[:upper:]' '[:lower:]' | sort -u | wc -l | tr -d ' ')"
  if [ "$distinct" -gt 1 ]; then
    echo "[FAIL] $1 sent $count times with different values:"
    copies_of "$1" | sed 's/^/         /'
    FAILED=1
    return 1
  fi
  echo "::notice::$1 sent $count identical times — the declared header was added next to the platform's instead of replacing it"
  return 0
}

# Only called after copies_agree, so the first copy stands for all of them.
value_of() {
  copies_of "$1" | head -n1
  return 0
}

require_exact() {
  copies_agree "$1" || return 0
  local actual; actual="$(value_of "$1")"
  if [ -z "$actual" ]; then
    echo "[FAIL] $1 absent (want: $2)"; FAILED=1
  elif [ "$(lower "$actual")" = "$(lower "$2")" ]; then
    echo "[PASS] $1: $actual"
  else
    echo "[FAIL] $1: $actual (want: $2)"; FAILED=1
  fi
  return 0
}

require_present() {
  copies_agree "$1" || return 0
  local actual; actual="$(value_of "$1")"
  if [ -n "$actual" ]; then
    echo "[PASS] $1"
  else
    echo "[FAIL] $1 absent"; FAILED=1
  fi
  return 0
}

# A ratchet, not a target. The floor is what production serves today, so the
# check catches a reduction without being red about a value we already know is
# low. Raise the floor in the same change that raises the header.
HSTS_FLOOR=86400
HSTS_PRODUCTION_LIFETIME=31536000

require_hsts() {
  copies_agree Strict-Transport-Security || return 0
  local actual max_age
  actual="$(value_of Strict-Transport-Security)"
  if [ -z "$actual" ]; then
    echo "[FAIL] Strict-Transport-Security absent"; FAILED=1; return 0
  fi
  max_age="$(printf '%s' "$actual" | sed -nE 's/.*[Mm]ax-[Aa]ge=([0-9]+).*/\1/p')"
  if [ -z "$max_age" ]; then
    echo "[FAIL] Strict-Transport-Security: $actual has no max-age"; FAILED=1; return 0
  fi
  if [ "$max_age" -lt "$HSTS_FLOOR" ]; then
    echo "[FAIL] Strict-Transport-Security max-age=$max_age is below the floor of $HSTS_FLOOR"; FAILED=1; return 0
  fi
  echo "[PASS] Strict-Transport-Security: $actual"
  if [ "$max_age" -lt "$HSTS_PRODUCTION_LIFETIME" ]; then
    echo "::notice::Strict-Transport-Security max-age=$max_age is still the trial value, not a production lifetime (known gap)"
  fi
  return 0
}

require_exact X-Content-Type-Options nosniff
require_exact X-Frame-Options DENY
require_present Content-Security-Policy
require_present Permissions-Policy
require_exact Referrer-Policy same-origin
require_hsts

if [ "$FAILED" -eq 1 ]; then
  echo "::error::${URL:-$HEADER_FILE} is missing or weakening a required security header"
  exit 1
fi
echo "All required security headers present with acceptable values."
