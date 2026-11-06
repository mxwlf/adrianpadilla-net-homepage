# The test environment: test.adrianpadilla.net
#
# WHAT IS NOT HERE, AND WHY
# -------------------------
# No DNS. The adrianpadilla.net zone lives in a different subscription
# (`connectivity`, resource group `dns-prod`) and also serves the apex records
# for the live site plus git, id, ntfy, codenomad, macwolf, ief-replay, the DKIM
# selectors and a Tailscale challenge. Granting this configuration DNS Zone
# Contributor there would let a bad plan delete all of it.
#
# The CNAME the test environment needs is no longer hand-made, though, and the
# reason is the teardown pipeline: a destroyed Static Web App releases its
# *.azurestaticapps.net hostname, and the rebuilt one is assigned a different
# one, so the record moves on every teardown and every restore. Leaving it
# aimed at a released Azure hostname is a dangling-CNAME subdomain takeover.
#
# It is still not managed here. scripts/test-env.sh writes it with `az`, using a
# `DNS Zone Contributor` assignment scoped to the single record set
# (.../dnsZones/adrianpadilla.net/CNAME/test) rather than to the zone. That
# keeps the original objection satisfied -- the identity cannot read, change or
# delete anything else in that zone -- without pretending the record is static.
# Putting it in this configuration would mean a provider that needs zone-level
# read, and a `tofu destroy` that can delete a record set.
#
# Delegating test.adrianpadilla.net as its own zone was considered and rejected:
# it would make the hostname a zone apex, and Azure Static Web Apps then
# requires `dns-txt-token` validation, which the provider documents as not
# waited on ("Terraform does not wait for the validation process to be
# successful"). A zone apex also cannot hold a CNAME, and
# azurerm_dns_a_record.target_resource_id does not accept a Static Web App as an
# ALIAS target. Keeping `test` a subdomain keeps the verifiable path.
#
# No resource group. It is created out of band and referenced, so this
# configuration never holds delete authority over the group. That is also what
# makes `make test-env-teardown` safe to point at `tofu destroy`: the group is
# not in the state file, so there is nothing for destroy to delete. The script
# asserts it rather than trusting it.

data "azurerm_resource_group" "test" {
  name = var.resource_group_name
}

# Free tier is deliberate. It allows two custom domains, and the test
# environment needs one. Production is also Free and already uses both of its
# allowance on adrianpadilla.net and www.adrianpadilla.net; this is a separate
# resource with its own.
#
# No repository_url / branch: linking the app to GitHub would make Azure write
# its own deploy workflow into the repository, which is exactly the publishing
# path this work is replacing. Deployment happens from the release package
# instead, authenticated by a token fetched at deploy time.
resource "azurerm_static_web_app" "test" {
  name                = var.static_web_app_name
  resource_group_name = data.azurerm_resource_group.test.name
  location            = var.location

  sku_tier = "Free"
  sku_size = "Free"

  tags = var.tags
}

# `cname-delegation` is the validation the provider actually polls, which is why
# the hostname has to stay a subdomain. The CNAME it validates against is the
# hand-made record described above; it must already resolve to
# azurerm_static_web_app.test.default_host_name before this can succeed.
#
# On a first apply the Static Web App does not exist yet, so its default
# hostname is not known and the CNAME cannot have been created. Apply in two
# steps the first time -- `make tf-apply` prints the record to create when it
# reaches this point. Later applies are a single pass.
resource "azurerm_static_web_app_custom_domain" "test" {
  static_web_app_id = azurerm_static_web_app.test.id
  domain_name       = var.custom_domain
  validation_type   = "cname-delegation"

  timeouts {
    create = "30m"
    delete = "30m"
  }
}
