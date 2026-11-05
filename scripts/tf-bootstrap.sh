#!/usr/bin/env bash
#
# Creates the Blob Storage that holds the test environment's OpenTofu state.
#
# This is the one piece of infrastructure OpenTofu cannot create, because it is
# where OpenTofu keeps its state: the backend has to exist before the first
# `tofu init`. Everything else in the test environment is in infra/test/.
#
# Idempotent — safe to re-run. It creates what is missing, leaves what exists,
# and rewrites infra/test/backend.config either way.
#
# Usage:
#   SUBSCRIPTION_ID=<guid> RESOURCE_GROUP=<name> ./scripts/tf-bootstrap.sh
#
# Optional:
#   STORAGE_ACCOUNT   default apnhtfstate (3-24 chars, lowercase alphanumeric,
#                     globally unique across Azure)
#   CONTAINER         default tfstate
#   LOCATION          default westus2
#   CI_PRINCIPAL_ID   object id of the workload-identity service principal, to
#                     grant alongside your own identity

set -euo pipefail

STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-apnhtfstate}"
CONTAINER="${CONTAINER:-tfstate}"
LOCATION="${LOCATION:-westus2}"

die() {
  echo "Error: $*" >&2
  exit 1
}

[[ -n "${SUBSCRIPTION_ID:-}" ]] || die 'SUBSCRIPTION_ID is required (the test subscription).'
[[ -n "${RESOURCE_GROUP:-}" ]] || die 'RESOURCE_GROUP is required (must already exist).'

command -v az >/dev/null 2>&1 || die 'the Azure CLI (az) is required.'

echo "==> Subscription $SUBSCRIPTION_ID, resource group $RESOURCE_GROUP"

az group show \
  --subscription "$SUBSCRIPTION_ID" \
  --name "$RESOURCE_GROUP" \
  --output none 2>/dev/null ||
  die "resource group '$RESOURCE_GROUP' does not exist in $SUBSCRIPTION_ID. Create it first; OpenTofu deliberately does not own the group."

# ---------------------------------------------------------------------------
# Storage account
# ---------------------------------------------------------------------------
# allow-shared-key-access false is the point of the exercise: with keys
# disabled, the ONLY way to reach this state is an Entra identity holding a data
# -plane role. There is no key to leak, and none to rotate.

if az storage account show \
  --subscription "$SUBSCRIPTION_ID" \
  --name "$STORAGE_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --output none 2>/dev/null; then
  echo "==> Storage account $STORAGE_ACCOUNT already exists"
else
  echo "==> Creating storage account $STORAGE_ACCOUNT"
  az storage account create \
    --subscription "$SUBSCRIPTION_ID" \
    --name "$STORAGE_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --sku Standard_LRS \
    --kind StorageV2 \
    --min-tls-version TLS1_2 \
    --https-only true \
    --allow-blob-public-access false \
    --allow-shared-key-access false \
    --output none
fi

echo "==> Enabling blob versioning, change feed and soft delete"
az storage account blob-service-properties update \
  --subscription "$SUBSCRIPTION_ID" \
  --account-name "$STORAGE_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --enable-versioning true \
  --enable-delete-retention true \
  --delete-retention-days 30 \
  --enable-container-delete-retention true \
  --container-delete-retention-days 30 \
  --output none

# ---------------------------------------------------------------------------
# Data-plane role assignments
# ---------------------------------------------------------------------------
# Granted before the container is created, because creating it with
# --auth-mode login needs the role to be in place.

ACCOUNT_SCOPE="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT}"
CONTAINER_SCOPE="${ACCOUNT_SCOPE}/blobServices/default/containers/${CONTAINER}"

grant() {
  local principal="$1" scope="$2" label="$3"
  echo "==> Granting Storage Blob Data Contributor to $label"
  az role assignment create \
    --assignee-object-id "$principal" \
    --assignee-principal-type "$4" \
    --role 'Storage Blob Data Contributor' \
    --scope "$scope" \
    --output none 2>/dev/null ||
    echo "    (already assigned, or you lack rights to assign it)"
}

ME="$(az ad signed-in-user show --query id --output tsv)"
grant "$ME" "$ACCOUNT_SCOPE" 'you' 'User'

if [[ -n "${CI_PRINCIPAL_ID:-}" ]]; then
  # Scoped to the container rather than the account: CI needs this one state
  # file, not every blob the account will ever hold.
  grant "$CI_PRINCIPAL_ID" "$CONTAINER_SCOPE" 'the CI service principal' 'ServicePrincipal'
fi

# ---------------------------------------------------------------------------
# Container
# ---------------------------------------------------------------------------
# Role assignments are eventually consistent, so a freshly granted role can take
# a short while to be honoured on the data plane.

echo "==> Creating container $CONTAINER (retrying while the role propagates)"
for attempt in 1 2 3 4 5 6; do
  if az storage container create \
    --subscription "$SUBSCRIPTION_ID" \
    --name "$CONTAINER" \
    --account-name "$STORAGE_ACCOUNT" \
    --auth-mode login \
    --output none 2>/dev/null; then
    echo "    created (or already present)"
    break
  fi
  [[ "$attempt" -lt 6 ]] || die "could not create container '$CONTAINER'. If the role was just granted, wait a minute and re-run."
  echo "    attempt $attempt failed, waiting 15s"
  sleep 15
done

# ---------------------------------------------------------------------------
# backend.config
# ---------------------------------------------------------------------------
# A backend block cannot interpolate variables, so `make tf-init` passes these
# with -backend-config. Git-ignored: it names the account, which is not secret
# but is environment-specific.

BACKEND_CONFIG="$(dirname "$0")/../infra/test/backend.config"
cat >"$BACKEND_CONFIG" <<EOF
resource_group_name  = "${RESOURCE_GROUP}"
storage_account_name = "${STORAGE_ACCOUNT}"
container_name       = "${CONTAINER}"
key                  = "test.tfstate"
subscription_id      = "${SUBSCRIPTION_ID}"
EOF

echo
echo "==> Wrote $(cd "$(dirname "$BACKEND_CONFIG")" && pwd)/backend.config"
echo "==> Next: cp infra/test/terraform.tfvars.example infra/test/terraform.tfvars"
echo "          then fill it in and run \`make tf-plan\`"
