variable "subscription_id" {
  description = "Azure subscription that holds the test environment. Deliberately has no default: test must not be able to fall back to the subscription production lives in."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F-]{36}$", var.subscription_id))
    error_message = "subscription_id must be a GUID."
  }
}

variable "resource_group_name" {
  description = "Existing resource group in the test subscription. Created out of band, so OpenTofu never holds delete authority over the group itself."
  type        = string
}

variable "location" {
  description = "Azure region. Matches production (westus2) so the test environment exercises the same region's behaviour."
  type        = string
  default     = "westus2"
}

variable "static_web_app_name" {
  description = "Name of the test Static Web App."
  type        = string
  default     = "adrianpadilla-net-homepage-test"
}

variable "custom_domain" {
  description = "Hostname the test environment answers on. A subdomain, never an apex: an apex would force the dns-txt-token validation that OpenTofu cannot confirm, and would need an ALIAS record that Azure DNS cannot point at a Static Web App."
  type        = string
  default     = "test.adrianpadilla.net"
}

variable "tags" {
  description = "Tags applied to every resource this configuration owns."
  type        = map(string)
  default = {
    environment = "test"
    managed-by  = "opentofu"
    repository  = "mxwlf/adrianpadilla-net-homepage"
  }
}
