# The deploy workflow reads these to know what it is deploying to, so the
# Static Web App's name and resource group are never duplicated in workflow YAML.

output "static_web_app_name" {
  description = "Name of the test Static Web App, for `az staticwebapp` calls."
  value       = azurerm_static_web_app.test.name
}

output "resource_group_name" {
  description = "Resource group holding the test Static Web App."
  value       = data.azurerm_resource_group.test.name
}

output "default_host_name" {
  description = "Azure-assigned hostname. This is the CNAME target for test.adrianpadilla.net — create that record by hand, once."
  value       = azurerm_static_web_app.test.default_host_name
}

output "custom_domain" {
  description = "Hostname the test environment answers on."
  value       = azurerm_static_web_app_custom_domain.test.domain_name
}

output "cname_record_to_create" {
  description = "The DNS record the connectivity subscription must hold. Deliberately not managed here — see main.tf."
  value       = "${var.custom_domain}. CNAME ${azurerm_static_web_app.test.default_host_name}."
}

# The deployment token is fetched at deploy time with
# `az staticwebapp secrets list`, authenticated by workload identity
# federation, rather than read from here. Keeping it out of outputs keeps it out
# of anything that renders them, and out of the state file's output section.
