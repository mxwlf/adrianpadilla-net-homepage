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
  description = "Azure-assigned hostname, and the CNAME target for test.adrianpadilla.net. scripts/test-env.sh reads this to write that record: a rebuilt app is given a new hostname, so the value changes on every teardown and restore."
  value       = azurerm_static_web_app.test.default_host_name
}

# No `custom_domain` output. It used to read the bound hostname off the
# azurerm_static_web_app_custom_domain resource, and scripts/test-env.sh treated
# a non-empty value as "the binding exists". Now that the binding is made with
# `az` (see main.tf), the only honest answer to that question comes from Azure,
# so the script asks `az staticwebapp hostname show` instead. An output echoing
# var.custom_domain back would have been worse than none: always non-empty, and
# therefore always claiming a binding that may not be there.

output "cname_record_to_create" {
  description = "The DNS record the connectivity subscription must hold. Deliberately not managed here — see main.tf. `make test-env-restore` writes it; this output is what to create by hand on a first-ever apply, before that target can run."
  value       = "${var.custom_domain}. CNAME ${azurerm_static_web_app.test.default_host_name}."
}

# The deployment token is fetched at deploy time with
# `az staticwebapp secrets list`, authenticated by workload identity
# federation, rather than read from here. Keeping it out of outputs keeps it out
# of anything that renders them, and out of the state file's output section.
