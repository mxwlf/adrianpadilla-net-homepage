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

# NO CUSTOM DOMAIN BINDING HERE, AND THIS ONE IS NOT A PREFERENCE
# ---------------------------------------------------------------
# There used to be an `azurerm_static_web_app_custom_domain` resource here. It
# cannot be created by the deploy identity, and the reason is a scope rather
# than a role: after the PUT, the provider polls
#
#   /subscriptions/<sub>/providers/Microsoft.Web/locations/<region>
#     /staticSitesOperationStatuses/<guid>
#
# which is a SUBSCRIPTION-level path. The identity holds `Contributor` on this
# resource group and nothing wider, so the poll comes back
# `403 AuthorizationFailed: ... does not have authorization to perform action
# 'Microsoft.Web/locations/staticSitesOperationStatuses/read'`. Release v1.3.2
# is where that surfaced: it was the first restore after a real teardown, so it
# was the first time CI had to create the binding rather than find it already
# there.
#
# The fix was a choice between widening the identity to subscription scope and
# moving the binding out of this configuration. Widening lost: the whole design
# of this environment is that the deploy identity's authority stops at this
# resource group plus one DNS record set, and a subscription-scoped assignment
# would be the first exception to that.
#
# scripts/test-env.sh now binds it with `az staticwebapp hostname set
# --no-wait`, which issues the same PUT and declines to poll, then waits on
# `az staticwebapp hostname show` instead -- a GET on
# .../resourceGroups/<rg>/providers/Microsoft.Web/staticSites/<app>, which is
# inside the grant. Same validation (`cname-delegation`), same end state, no new
# permission.
#
# WHAT THIS COSTS, STATED PLAINLY: this configuration no longer describes the
# binding, so `tofu plan` will not notice if it goes missing, and infra/prod/
# still manages its `www` binding as a resource. The asymmetry is about who
# applies, not about what the environments are: only a human with broader rights
# ever applies prod, while CI applies test on every release. `tofu destroy`
# still removes the binding, because deleting the Static Web App takes its
# custom domains with it -- the dispatched teardown that preceded v1.3.2 did
# exactly that under this identity and succeeded, which is also the evidence
# that DELETE does not poll the path CREATE does.
#
# `cname-delegation` still requires the hostname to be a subdomain, and the
# CNAME must already resolve to azurerm_static_web_app.test.default_host_name
# before the binding can validate. That ordering now lives entirely in
# scripts/test-env.sh, which is also why restore is a single `tofu apply` again
# rather than the two targeted passes it used to need.
