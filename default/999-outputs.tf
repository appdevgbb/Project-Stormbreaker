/*
 * Outputs:
 * - resource_group_name: The name of the resource group created for the Refinitiv on Azure deployment.
 * - aks_cluster_name: The name of the AKS cluster created for the Refinitiv on Azure deployment.
 * - aks_managed_id: The client ID and name of the user-assigned managed identity for the AKS cluster.
 * - kubeconfig: The kubeconfig file for the AKS cluster.
 * - grafana_resource_id: The resource ID of the Grafana dashboard.
 * - azure_monitor_workspace_id: The ID of the Azure Monitor workspace.
 * - acr: The Azure Container Registry created for the Refinitiv on Azure deployment.
 */

output "azure_subscription" {
  value = data.azurerm_subscription.current
}
output "resource_group_name" {
  value = azurerm_resource_group.default.name
}

output "aks_cluster_name" {
  value = module.aks.cluster_name
}

output "aks_oidc_url" {
  value = module.aks.oidc_url
}

output "user_assigned_identity" {
  value = {
    client_id = azurerm_user_assigned_identity.managed-id.client_id
    name      = azurerm_user_assigned_identity.managed-id.name
  }
}

output "stormbreaker-cluster-agentpool-identity" {
  value = module.aks.stormbreaker-cluster-agentpool-mi
}

output "kubeconfig" {
  value     = module.aks.kube_config
  sensitive = true
}

output "grafana_resource_id" {
  value = azurerm_dashboard_grafana.stormbreaker-grafana.id
}

output "acr" {
  value     = azurerm_container_registry.default
  sensitive = true
}

output "storage_account_name" {
  value = azurerm_storage_account.stormbreaker.name
}

output "container_name" {
  value = var.enable_filesystem_creation ? azurerm_storage_data_lake_gen2_filesystem.filesystem[0].name : null
}

output "azure_monitor_workspace_id" {
  value = azurerm_monitor_workspace.stormbreaker_azure_monitor_workspace
}

output "servicebus_name" {
  value = azurerm_servicebus_namespace.stormbreaker-servicebus.name
}

