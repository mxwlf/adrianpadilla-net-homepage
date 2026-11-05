variable "subscription_id" {
  description = "Azure subscription that holds production. Deliberately has no default: the one thing worse than a missing value here is a wrong one."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F-]{36}$", var.subscription_id))
    error_message = "subscription_id must be a GUID."
  }
}

variable "resource_group_name" {
  description = "Existing resource group in the production subscription. Created out of band, so OpenTofu never holds delete authority over the group itself."
  type        = string
}

variable "location" {
  description = "Azure region. Matches test so the two environments differ in as little as possible."
  type        = string
  default     = "westus2"
}

variable "static_web_app_name" {
  description = "Name of the production Static Web App."
  type        = string
  default     = "adrianpadilla-net-homepage-prod"
}

variable "www_domain" {
  description = "The www hostname. A subdomain, so it validates by cname-delegation, which is the path the provider actually polls."
  type        = string
  default     = "www.adrianpadilla.net"
}

variable "apex_domain" {
  description = "The apex hostname, recorded for the outputs only. Its binding is NOT managed here -- see main.tf."
  type        = string
  default     = "adrianpadilla.net"
}

variable "tags" {
  description = "Tags applied to every resource this configuration owns. The hand-made app this replaced had none, which is part of why its drift was invisible."
  type        = map(string)
  default = {
    environment = "production"
    managed-by  = "opentofu"
    repository  = "mxwlf/adrianpadilla-net-homepage"
  }
}
