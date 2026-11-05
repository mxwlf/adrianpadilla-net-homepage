# The deploy workflow reads these, so the app's name and resource group are
# never duplicated in workflow YAML.

output "static_web_app_name" {
  description = "Name of the production Static Web App, for `az staticwebapp` calls."
  value       = azurerm_static_web_app.prod.name
}

output "resource_group_name" {
  description = "Resource group holding the production Static Web App."
  value       = data.azurerm_resource_group.prod.name
}

output "default_host_name" {
  description = "Azure-assigned hostname. Deploy here and verify before moving any DNS: it is the one address that works before the cutover."
  value       = azurerm_static_web_app.prod.default_host_name
}

output "static_web_app_id" {
  description = "Resource id, which is what the apex ALIAS A record targets. Azure DNS aliases a Static Web App directly rather than an address."
  value       = azurerm_static_web_app.prod.id
}

output "dns_records_to_create" {
  description = "The records the connectivity subscription must hold. Deliberately not managed here -- see main.tf."
  value = {
    www  = "${var.www_domain}. CNAME ${azurerm_static_web_app.prod.default_host_name}."
    apex = "${var.apex_domain}. A ALIAS -> ${azurerm_static_web_app.prod.id}"
  }
}
