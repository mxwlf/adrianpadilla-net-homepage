#!/usr/bin/env bash
#
# Tears the test environment down, and stands it back up.
#
# WHY THIS EXISTS
# ---------------
# The test environment is a Static Web App on the Free SKU, so it costs nothing
# to leave running -- but it is a deployable surface bound to a public hostname,
# and it only needs to exist while a release is actually being looked at.
# Teardown removes the app; the next release puts it back.
#
# THE RESOURCE GROUP IS NEVER TOUCHED, and that is structural rather than
# careful. infra/test/ reads the group with a `data` block, so it is not in the
# state file and `tofu destroy` has nothing to delete. The assertion in
# `assert_group_survives` is there to notice if that ever stops being true.
#
# THE ONE DNS RECORD, AND WHAT CHANGED
# ------------------------------------
# `test.adrianpadilla.net` is a CNAME in the `adrianpadilla.net` zone, which
# lives in a different subscription (`connectivity`, resource group `dns-prod`)
# and also serves the apex plus git, id, ntfy, codenomad, macwolf, ief-replay,
# the DKIM selectors and a Tailscale challenge. That record used to be made by
# hand, once, on the grounds that it never changes.
#
# It changes now. A torn-down app releases its `*.azurestaticapps.net` hostname,
# and a rebuilt one is assigned a NEW one, so the record has to move on every
# teardown and every restore. Leaving it pointing at the released hostname is
# the textbook dangling-CNAME subdomain takeover: whoever next claims that
# Azure hostname serves content on our domain.
#
# So the deploy identity does now hold a DNS permission -- but at RECORD SET
# scope, not zone scope:
#
#   /subscriptions/<dns>/resourceGroups/dns-prod/providers/Microsoft.Network
#     /dnsZones/adrianpadilla.net/CNAME/test
#
# `DNS Zone Contributor` there can write exactly one record and cannot read,
# change or delete anything else in the zone. The original objection was blast
# radius, and at this scope the blast radius is the record we already intended
# to change. See docs/deployment.md for the grant.
#
# WHAT "PARKED" MEANS, PRECISELY
# ------------------------------
# Teardown points the record at `www.adrianpadilla.net` (PARKED_CNAME). That
# makes the name resolve into production and kills the takeover risk, which is
# the property worth having. It does NOT produce a browser-visible redirect:
# production is also Free SKU and its two custom-domain slots are both spent on
# the apex and `www`, so nothing there is bound to `test.adrianpadilla.net` and
# an HTTPS request to it fails the certificate check rather than answering 301.
# A real redirect needs a host that terminates TLS for the name -- see
# docs/deployment.md.
#
# Usage:
#   ./scripts/test-env.sh status
#   ./scripts/test-env.sh teardown     # ASSUME_YES=1 to skip the prompt
#   ./scripts/test-env.sh restore      # idempotent; safe on every release
#
# Required:
#   DNS_SUBSCRIPTION_ID   subscription holding the adrianpadilla.net zone
#
# Optional:
#   DNS_RESOURCE_GROUP    default dns-prod
#   DNS_ZONE              default adrianpadilla.net
#   DNS_RECORD_NAME       default test  (relative to the zone)
#   PARKED_CNAME          default www.adrianpadilla.net
#   RECORD_TTL            default 60    (seconds; low so a flip is cheap)
#   ASSUME_YES            1 to answer the teardown confirmation
#   DNS_WAIT_SECONDS      default 300   (how long restore waits for the record)

set -euo pipefail

# Hardcoded, not derived from INFRA_ENV. Every other infra target takes the
# environment as a variable; this one must not, because `make test-env-teardown
# INFRA_ENV=prod` would otherwise be a one-command outage.
INFRA_DIR='infra/test'
SWA_RESOURCE='azurerm_static_web_app.test'

DNS_RESOURCE_GROUP="${DNS_RESOURCE_GROUP:-dns-prod}"
DNS_ZONE="${DNS_ZONE:-adrianpadilla.net}"
DNS_RECORD_NAME="${DNS_RECORD_NAME:-test}"
PARKED_CNAME="${PARKED_CNAME:-www.adrianpadilla.net}"
RECORD_TTL="${RECORD_TTL:-60}"
DNS_WAIT_SECONDS="${DNS_WAIT_SECONDS:-300}"
TOFU="${TOFU:-tofu}"

die() {
  echo "Error: $*" >&2
  exit 1
}

say() { echo "==> $*"; }

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# Checked before the preconditions below, so that a typo or a bare invocation
# prints the usage rather than a complaint about an unset variable.
COMMAND="${1:-}"
case "$COMMAND" in
  status | teardown | restore) ;;
  *)
    echo "Usage: $0 {status|teardown|restore}" >&2
    exit 2
    ;;
esac

# ---------------------------------------------------------------------------
# Preconditions
# ---------------------------------------------------------------------------

command -v "$TOFU" >/dev/null 2>&1 ||
  die "\`$TOFU\` was not found on your PATH. Install OpenTofu: brew install opentofu"
command -v az >/dev/null 2>&1 || die 'the Azure CLI (az) is required.'

[[ -d "$INFRA_DIR" ]] || die "$INFRA_DIR does not exist."
[[ -f "$INFRA_DIR/backend.config" ]] || die "$(
  cat <<'MSG'
infra/test/backend.config does not exist.
       Create the state storage first:
           SUBSCRIPTION_ID=<guid> RESOURCE_GROUP=<name> make tf-bootstrap INFRA_ENV=test
MSG
)"

# Guards on the DNS inputs. The record name is interpolated into a write
# command, and `@` or `*` there would aim it at the apex or a wildcard -- the
# records this whole design exists to keep away from automation.
[[ -n "${DNS_SUBSCRIPTION_ID:-}" ]] ||
  die 'DNS_SUBSCRIPTION_ID is required (the subscription holding the DNS zone).'
[[ "$DNS_RECORD_NAME" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] ||
  die "DNS_RECORD_NAME='$DNS_RECORD_NAME' is not a plain single-label hostname. Refusing: an apex or wildcard name is out of scope for this script."
[[ -n "$PARKED_CNAME" ]] || die 'PARKED_CNAME must not be empty.'
[[ "$RECORD_TTL" =~ ^[0-9]+$ ]] || die "RECORD_TTL='$RECORD_TTL' is not a number."

FQDN="${DNS_RECORD_NAME}.${DNS_ZONE}"

# ---------------------------------------------------------------------------
# OpenTofu
# ---------------------------------------------------------------------------
# Initialised here rather than through `make tf-init`, so that nothing in this
# script's path can be pointed at another environment.

tf() { "$TOFU" -chdir="$INFRA_DIR" "$@"; }

tf_init() {
  say "Initialising OpenTofu in $INFRA_DIR"
  tf init -input=false -backend-config=backend.config >/dev/null
}

# Empty output (rather than a failure) when the resource is not in state, which
# is the normal condition after a teardown.
tf_output() {
  tf output -raw "$1" 2>/dev/null || true
}

# The structural promise, checked rather than trusted.
#
# `tofu state list` distinguishes the two cases exactly: a group read with a
# `data` block is listed as `data.azurerm_resource_group.test` and is not
# destroyable, while one this configuration owned would be listed bare, as
# `azurerm_resource_group.<name>`. Only the second is a problem, which is why
# this matches on the address rather than searching plan JSON -- there the data
# source's own type string appears too, and would be a false positive.
assert_group_survives() {
  say 'Checking no resource group is in the state'
  if tf state list | grep -qE '^azurerm_resource_group\.'; then
    die 'the OpenTofu state contains a managed azurerm_resource_group. infra/test/ must reference the group with a `data` block, never own it, or this teardown would delete it. Aborting.'
  fi
  echo '    the group is a data source, so destroy cannot reach it'
}

# ---------------------------------------------------------------------------
# DNS
# ---------------------------------------------------------------------------
# Only ever `set-record`, never `delete`. Repointing keeps the record set in
# existence, which is both what we want (no NXDOMAIN, no dangling target) and
# the narrowest thing the record-set-scoped role needs to permit.

dns_current_target() {
  az network dns record-set cname show \
    --subscription "$DNS_SUBSCRIPTION_ID" \
    --resource-group "$DNS_RESOURCE_GROUP" \
    --zone-name "$DNS_ZONE" \
    --name "$DNS_RECORD_NAME" \
    --query 'cnameRecord.cname' \
    --output tsv 2>/dev/null || true
}

dns_point_at() {
  local target="${1%.}" current
  current="$(dns_current_target)"
  current="${current%.}"

  if [[ "$current" == "$target" ]]; then
    say "$FQDN already points at $target"
    return 0
  fi

  say "Pointing $FQDN at $target (was ${current:-<unset>})"
  az network dns record-set cname set-record \
    --subscription "$DNS_SUBSCRIPTION_ID" \
    --resource-group "$DNS_RESOURCE_GROUP" \
    --zone-name "$DNS_ZONE" \
    --record-set-name "$DNS_RECORD_NAME" \
    --cname "$target" \
    --output none ||
    die "could not write $FQDN. The deploy identity needs DNS Zone Contributor at the record-set scope -- see docs/deployment.md."

  # TTL is a property of the record set, not of the record, so it is a second
  # call. Kept low deliberately: every teardown and restore moves this record,
  # and an hour-long TTL would make each flip an hour of stale answers.
  az network dns record-set cname update \
    --subscription "$DNS_SUBSCRIPTION_ID" \
    --resource-group "$DNS_RESOURCE_GROUP" \
    --zone-name "$DNS_ZONE" \
    --name "$DNS_RECORD_NAME" \
    --set "ttl=$RECORD_TTL" \
    --output none
}

# Waits on the authoritative record rather than on a resolver. Azure DNS is the
# source of truth here, and `azurerm_static_web_app_custom_domain` validates by
# `cname-delegation` against it -- a stale answer in some public resolver's
# cache is not what the binding is checking.
dns_wait_for() {
  local want="${1%.}" waited=0 got
  say "Waiting for $FQDN to read back as $want"
  while :; do
    got="$(dns_current_target)"
    got="${got%.}"
    if [[ "$got" == "$want" ]]; then
      echo "    confirmed after ${waited}s"
      return 0
    fi
    [[ "$waited" -lt "$DNS_WAIT_SECONDS" ]] ||
      die "$FQDN still reads '$got' after ${waited}s, expected '$want'."
    sleep 10
    waited=$((waited + 10))
  done
}

# ---------------------------------------------------------------------------
# Custom domain readiness
# ---------------------------------------------------------------------------
# A freshly bound hostname is not immediately serveable: Azure has to issue a
# certificate for it, and until it does, HTTPS to the name fails the handshake
# rather than returning an error page. The provider's create does wait, but this
# is checked explicitly anyway — the next thing to run is release.yml's smoke
# test, whose `curl --retry` budget is about a minute, and a TLS failure there
# would look like a bad deploy rather than a cold certificate.

swa_wait_ready() {
  local app group waited=0 status
  app="$(tf_output static_web_app_name)"
  group="$(tf_output resource_group_name)"
  [[ -n "$app" && -n "$group" ]] || die 'cannot read the app name or resource group from the OpenTofu outputs.'

  say "Waiting for $FQDN to report Ready on $app"
  while :; do
    status="$(
      az staticwebapp hostname show \
        --name "$app" \
        --resource-group "$group" \
        --hostname "$FQDN" \
        --query 'status' \
        --output tsv 2>/dev/null || true
    )"
    case "$status" in
      Ready)
        echo "    ready after ${waited}s"
        return 0
        ;;
      Failed)
        die "Azure reports the $FQDN binding as Failed. Check the CNAME, then re-run."
        ;;
    esac
    [[ "$waited" -lt "$DNS_WAIT_SECONDS" ]] ||
      die "$FQDN is still '${status:-unknown}' after ${waited}s, not Ready."
    sleep 15
    waited=$((waited + 15))
  done
}

# ---------------------------------------------------------------------------
# status
# ---------------------------------------------------------------------------

cmd_status() {
  tf_init
  local app host domain target
  app="$(tf_output static_web_app_name)"
  host="$(tf_output default_host_name)"
  domain="$(tf_output custom_domain)"
  target="$(dns_current_target)"

  echo
  if [[ -n "$app" ]]; then
    echo "Static Web App   $app"
    echo "Azure hostname   ${host:-<unknown>}"
    echo "Custom domain    ${domain:-<not bound>}"
  else
    echo 'Static Web App   torn down (nothing in the OpenTofu state)'
  fi
  echo "$FQDN  ->  ${target:-<no CNAME>}"
  echo

  if [[ -z "$app" ]]; then
    echo 'State: TORN DOWN. The next release restores it, or run `make test-env-restore`.'
  elif [[ -n "$host" && "${target%.}" == "${host%.}" ]]; then
    echo 'State: UP, and DNS points at it.'
  else
    echo 'State: the app exists but DNS points somewhere else. `make test-env-restore` reconciles it.'
  fi
}

# ---------------------------------------------------------------------------
# teardown
# ---------------------------------------------------------------------------
# DNS moves FIRST. The alternative -- destroy, then repoint -- leaves a window
# in which the record names a released Azure hostname that anyone can claim.
# The custom-domain binding deletes fine with the record already moved; Azure
# does not re-validate on the way out.

cmd_teardown() {
  tf_init

  if [[ -z "$(tf_output static_web_app_name)" ]]; then
    say 'Nothing in the OpenTofu state -- the test environment is already torn down'
    dns_point_at "$PARKED_CNAME"
    return 0
  fi

  if [[ "${ASSUME_YES:-}" != '1' ]]; then
    echo
    echo "This destroys the test Static Web App and parks $FQDN at $PARKED_CNAME."
    echo "The resource group is not touched. The next release rebuilds the app."
    read -r -p 'Type `teardown` to continue: ' reply
    [[ "$reply" == 'teardown' ]] || die 'aborted.'
  fi

  assert_group_survives
  dns_point_at "$PARKED_CNAME"

  say 'Destroying the test environment'
  tf destroy -input=false -auto-approve

  echo
  say "Torn down. $FQDN is parked at $PARKED_CNAME."
  echo "    Note: that name has no custom-domain binding in production, so it"
  echo "    resolves but does not serve HTTPS. See docs/deployment.md."
}

# ---------------------------------------------------------------------------
# restore
# ---------------------------------------------------------------------------
# Idempotent, because release.yml runs it before every deploy to test. When the
# environment is already up and the record already matches, it costs one no-op
# plan and one DNS read.
#
# The rebuild is two applies, for the reason the first-ever apply was two:
# `azurerm_static_web_app_custom_domain` validates by `cname-delegation`, so the
# CNAME has to resolve to the app's hostname before the binding can be created
# -- and the hostname is not known until the app exists. A fresh app gets a
# fresh `*.azurestaticapps.net` name, so this is not a first-run special case.

cmd_restore() {
  tf_init

  local host target
  host="$(tf_output default_host_name)"
  target="$(dns_current_target)"

  if [[ -n "$host" && -n "$(tf_output custom_domain)" && "${target%.}" == "${host%.}" ]]; then
    say "Test environment is already up and $FQDN points at it"
    tf apply -input=false -auto-approve
    return 0
  fi

  say "Creating the Static Web App ($SWA_RESOURCE only)"
  # Targeted, because the domain binding in the same configuration cannot
  # succeed until DNS has been moved -- which needs the hostname this creates.
  tf apply -input=false -auto-approve -target="$SWA_RESOURCE"

  host="$(tf_output default_host_name)"
  [[ -n "$host" ]] || die 'the apply produced no default_host_name output.'

  dns_point_at "$host"
  dns_wait_for "$host"

  say 'Binding the custom domain'
  tf apply -input=false -auto-approve

  swa_wait_ready

  echo
  say "Restored. $FQDN -> $host"
}

# ---------------------------------------------------------------------------

"cmd_${COMMAND}"
