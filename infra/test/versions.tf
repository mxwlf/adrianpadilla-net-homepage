# Provider and tooling versions for the test environment.
#
# .terraform.lock.hcl is committed (the template's .gitignore excluded it; that
# was corrected). The lock file is what makes `tofu init` resolve identical
# provider builds in every clone and every CI run, which is the point of
# pinning at all.

terraform {
  required_version = ">= 1.8.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id

  # Keeps the provider from trying to register resource providers on the
  # subscription, which needs rights the deploy identity is not given.
  resource_provider_registrations = "none"

  features {}
}
