#!/usr/bin/env bash
#
# Creates the Blob Storage that holds one environment's OpenTofu state.
#
# This is the one piece of infrastructure OpenTofu cannot create, because it is
# where OpenTofu keeps its state: the backend has to exist before the first
# `tofu init`. Everything else in an environment is in infra/<env>/.
#
# Idempotent — safe to re-run. It creates what is missing, leaves what exists,
# and rewrites infra/<env>/backend.config either way.
#
# EVERY environment-specific value is derived from INFRA_ENV, and that is the
# point. An earlier version hardcoded both `infra/test/backend.config` and the
# state key `test.tfstate`, so bootstrapping prod silently overwrote the test
# environment's backend config with prod's values and aimed prod's state at
# test's blob. Nothing failed; it exited 0. Hence the existence check below:
# a typo in INFRA_ENV now stops the script instead of inventing a directory.
#
# Usage:
#   SUBSCRIPTION_ID=<guid> RESOURCE_GROUP=<name> [INFRA_ENV=test] \
#     ./scripts/tf-bootstrap.sh
#
# Optional:
#   INFRA_ENV         default test. Must name an existing infra/<env>/
#                     directory, and selects both the backend.config written
#                     and the state key inside the container.
#   STORAGE_ACCOUNT   default apnhtfstate for test, apnhtfstateprod for prod
#                     (3-24 chars, lowercase alphanumeric, globally unique
#                     across Azure)
#   CONTAINER         default tfstate
#   LOCATION          default westus2
#   CI_PRINCIPAL_ID   object id of the workload-identity service principal, to
#                     grant alongside your own identity

set -euo pipefail

INFRA_ENV="${INFRA_ENV:-test}"
CONTAINER="${CONTAINER:-tfstate}"
LOCATION="${LOCATION:-westus2}"

die() {
  echo "Error: $*" >&2
  exit 1
}

[[ -n "${SUBSCRIPTION_ID:-}" ]] || die 'SUBSCRIPTION_ID is required.'
[[ -n "${RESOURCE_GROUP:-}" ]] || die 'RESOURCE_GROUP is required (must already exist).'

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INFRA_DIR="${REPO_ROOT}/infra/${INFRA_ENV}"

[[ -d "$INFRA_DIR" ]] ||
  die "INFRA_ENV='${INFRA_ENV}' has no infra/${INFRA_ENV}/ directory. Existing environments: $(cd "${REPO_ROOT}/infra" && echo */ | tr -d /)."

# Defaulted per environment rather than globally, so forgetting to pass it
# cannot point one environment's backend at another's account.
if [[ -z "${STORAGE_ACCOUNT:-}" ]]; then
  case "$INFRA_ENV" in
    test) STORAGE_ACCOUNT='apnhtfstate' ;;
    prod) STORAGE_ACCOUNT='apnhtfstateprod' ;;
    *) die "no default STORAGE_ACCOUNT for INFRA_ENV='${INFRA_ENV}'; pass one explicitly." ;;
  esac
fi

command -v az >/dev/null 2>&1 || die 'the Azure CLI (az) is required.'

echo "==> Environment $INFRA_ENV"
echo "==> Subscription $SUBSCRIPTION_ID, resource group $RESOURCE_GROUP"

# ---------------------------------------------------------------------------
# Tenant check
# ---------------------------------------------------------------------------
# `az account show --subscription X` works for any subscription az holds a
# token for, across tenants -- but every `az ad` command below runs against the
# ACTIVE tenant, not the target subscription's. With two accounts logged in,
# that mismatch is invisible and total: the script read the wrong directory's
# signed-in user, tried to grant that foreign object id here, and the grant
# failed into a message saying it was probably already assigned. The state
# storage came out with no data-plane role on it whatsoever.

TARGET_TENANT="$(az account show --subscription "$SUBSCRIPTION_ID" --query tenantId --output tsv 2>/dev/null)" ||
  die "cannot read subscription '$SUBSCRIPTION_ID'. Run: az login"
ACTIVE_TENANT="$(az account show --query tenantId --output tsv 2>/dev/null)" ||
  die 'no active az context. Run: az login'

if [[ "$TARGET_TENANT" != "$ACTIVE_TENANT" ]]; then
  die "$(
    cat <<MSG
the active az context is in tenant $ACTIVE_TENANT, but subscription
       $SUBSCRIPTION_ID belongs to tenant $TARGET_TENANT.

       Directory lookups (az ad ...) would resolve against the wrong tenant and
       the role grants would silently do nothing. Point az at the right one:

           az account set --subscription $SUBSCRIPTION_ID
MSG
  )"
fi

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

# An existing assignment is the only tolerated failure, and it is recognised by
# name rather than assumed. Everything else aborts: a swallowed grant failure
# here produces state storage nobody can read, which only surfaces much later
# as an opaque permission error from `tofu init`.
grant() {
  local principal="$1" scope="$2" label="$3" type="$4" output
  echo "==> Granting Storage Blob Data Contributor to $label"

  if output="$(
    az role assignment create \
      --assignee-object-id "$principal" \
      --assignee-principal-type "$type" \
      --role 'Storage Blob Data Contributor' \
      --scope "$scope" \
      --output none 2>&1
  )"; then
    echo '    granted'
  elif grep -qiE 'RoleAssignmentExists|already exists' <<<"$output"; then
    echo '    already assigned'
  else
    echo "$output" >&2
    die "could not grant Storage Blob Data Contributor to $label ($principal). Without it nothing can read this state."
  fi
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

BACKEND_CONFIG="${INFRA_DIR}/backend.config"
cat >"$BACKEND_CONFIG" <<EOF
resource_group_name  = "${RESOURCE_GROUP}"
storage_account_name = "${STORAGE_ACCOUNT}"
container_name       = "${CONTAINER}"
key                  = "${INFRA_ENV}.tfstate"
subscription_id      = "${SUBSCRIPTION_ID}"
EOF

echo
echo "==> Wrote ${BACKEND_CONFIG}"
echo "==> Next: cp infra/${INFRA_ENV}/terraform.tfvars.example infra/${INFRA_ENV}/terraform.tfvars"
echo "          then fill it in and run \`make tf-plan INFRA_ENV=${INFRA_ENV}\`"
