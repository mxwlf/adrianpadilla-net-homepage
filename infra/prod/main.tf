# Production: adrianpadilla.net and www.adrianpadilla.net
#
# WHY THIS EXISTS AT ALL
# ----------------------
# Production used to be a hand-made resource, and it stopped accepting token
# deploys: the content server answered "No matching Static Web App was found or
# the api key was invalid" to a freshly fetched key, in CI and from a laptop
# alike, while the OpenTofu-created test app accepted the identical command.
# Two rounds of diagnosis found no cause -- only differences we could enumerate
# but not account for: a stale GitHub source-control link, no tags, an unset
# publicNetworkAccess. Rebuilding from the configuration that demonstrably
# works was the cheaper answer than continuing to understand the one that does
# not, and it leaves production described in a file rather than in a portal.
#
# WHAT IS NOT HERE, AND WHY
# -------------------------
# No DNS, exactly as in infra/test. The adrianpadilla.net zone lives in another
# subscription and also serves git, id, ntfy, codenomad, macwolf, ief-replay,
# the DKIM selectors and a Tailscale challenge. Giving this configuration DNS
# Zone Contributor there would let a bad plan take out the lot, so the deploy
# identity holds no DNS permissions at all and the records are made by hand.
#
# Note that an Azure DNS ALIAS record *can* target a Static Web App -- the apex
# record this replaces did exactly that, and an earlier comment in this repo
# wrongly said it could not. The reason DNS stays out of here is blast radius,
# not capability.
#
# No apex custom domain binding. An apex must validate by `dns-txt-token`, and
# the provider documents that path as one it does not wait on: it marks the
# resource created without confirming, and the token has to reach a TXT record
# out of band. Only `cname-delegation` is polled. So the www binding is managed
# here and the apex binding is made by hand, once, and recorded in
# docs/deployment.md.
#
# No resource group, and no repository_url on the app -- linking it to GitHub is
# what the retired pull-based deploy did, and is the first difference we found
# on the app this replaces.

data "azurerm_resource_group" "prod" {
  name = var.resource_group_name
}

resource "azurerm_static_web_app" "prod" {
  name                = var.static_web_app_name
  resource_group_name = data.azurerm_resource_group.prod.name
  location            = var.location

  # Free allows two custom domains. Production needs exactly two, the apex and
  # www, so this is at the limit by design rather than by accident.
  sku_tier = "Free"
  sku_size = "Free"

  # Off, and this is the one setting here with a scar behind it. The retired
  # workflow's header recorded staging environments that Azure created from
  # branch pushes and never tore down; they filled the Free plan's three
  # environment slots and broke production deploys outright. Nothing in the
  # current pipeline wants a preview environment -- promotion always deploys
  # `--env production` -- so the capacity to create one is pure downside.
  preview_environments_enabled = false

  tags = var.tags
}

# www only. The CNAME it validates against is made by hand and must already
# resolve to azurerm_static_web_app.prod.default_host_name before this can
# succeed -- and a hostname can only be bound to one Static Web App at a time,
# so during a cutover it has to be released from the old app first.
resource "azurerm_static_web_app_custom_domain" "www" {
  static_web_app_id = azurerm_static_web_app.prod.id
  domain_name       = var.www_domain
  validation_type   = "cname-delegation"

  timeouts {
    create = "30m"
    delete = "30m"
  }
}
