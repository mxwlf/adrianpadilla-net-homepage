# State lives in Blob Storage in the test subscription.
#
# No account keys: `use_azuread_auth` makes the provider authenticate to the
# blob endpoint with the caller's own Entra identity — your `az login` locally,
# the workload identity federation token in CI — so there is no storage key to
# store, rotate or leak. The identity needs `Storage Blob Data Contributor` on
# the container, which `scripts/tf-bootstrap.sh` grants.
#
# The values below are deliberately absent: a backend block cannot interpolate
# variables, and the storage account name is environment-specific. They are
# supplied by `make tf-init`, which reads them from infra/test/backend.config
# (written by `make tf-bootstrap`, and git-ignored).

terraform {
  backend "azurerm" {
    use_azuread_auth = true
  }
}
