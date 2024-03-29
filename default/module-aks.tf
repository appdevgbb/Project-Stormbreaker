/* 
 * This Terraform code creates an Azure user-assigned managed identity and assigns it to 
 * various roles in different scopes. It also creates an Azure proximity placement group 
 * and deploys an AKS cluster using a custom module. The AKS cluster is deployed with a 
 * a ACR, and multiple node pools with different configurations. 
 */
resource "azurerm_user_assigned_identity" "managed-id" {
  resource_group_name = azurerm_resource_group.default.name
  location            = azurerm_resource_group.default.location

  name = "aks-user-assigned-managed-id"
}

# cluster
#

resource "azurerm_role_assignment" "aks-mi-roles-vnet-rg" {
  scope                = azurerm_resource_group.default.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.managed-id.principal_id
}

/* Network */
resource "azurerm_role_assignment" "aks-mi-roles-default-vnet" {
  scope                = azurerm_virtual_network.stormbreaker-vnet.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.managed-id.principal_id
}

/* Proximity Placement Group */
resource "azurerm_proximity_placement_group" "dev" {
  name                = "proximity-group-dev"
  resource_group_name = azurerm_resource_group.default.name
  location            = azurerm_resource_group.default.location
}

module "aks" {
  source = "./modules/aks"

  prefix = local.prefix
  suffix = local.suffix

  user_assigned_identity  = azurerm_user_assigned_identity.managed-id
  log_analytics_workspace = azurerm_log_analytics_workspace.aks.id

  # aks_admin_group_object_ids = var.aks_admin_group_object_ids

  admin_username = var.admin_username

  subnet_id      = azurerm_subnet.stormbreaker-cluster.id
  resource_group = azurerm_resource_group.default

 # ACR
  container_registry_id = azurerm_container_registry.default.id
  acr_subnet_id  = azurerm_subnet.acr.id
  acr_private_dns_zone_ids = [
    azurerm_private_dns_zone.acr.id
  ]
  
  cluster_name        = "stormbreaker-cluster"
  aks_settings = {
    kubernetes_version      = "1.28.3"
    private_cluster_enabled = false
    identity                = "UserAssigned"
    outbound_type           = "loadBalancer"
    network_plugin          = "azure"
    network_plugin_mode     = "overlay"
    network_policy          = null
    load_balancer_sku       = "standard"
    service_cidr            = "10.174.128.0/17"
    dns_service_ip          = "10.174.128.10"
    admin_username          = var.admin_username
    ssh_key                 = "~/.ssh/id_rsa.pub"
    blob_driver_enabled     = true
  }

  default_node_pool = {
    name                         = "system"
    enable_auto_scaling          = true
    node_count                   = 2
    min_count                    = 2
    max_count                    = 3
    vm_size                      = "standard_d4_v5"
    type                         = "VirtualMachineScaleSets"
    os_disk_size_gb              = 30
    only_critical_addons_enabled = true
    zones                        = [1, 2]
    proximity_placement_group_id = azurerm_proximity_placement_group.dev.id
  }

  user_node_pools = {
    "hecras" = {
      vm_size                      = "standard_d4_v5"
      node_count                   = 0
      node_labels                  = null
      node_taints                  = ["layer=hec-ras:NoSchedule"]
      proximity_placement_group_id = azurerm_proximity_placement_group.dev.id
      zones                        = [3]
      ultra_ssd_enabled            = false
    }

    "hecraswin" = {
      vm_size                      = "standard_d4_v5"
      node_count                   = 0
      node_labels                  = null
      node_taints                  = ["layer=hec-ras-win:NoSchedule"]
      os_type			                 = "Windows"
      proximity_placement_group_id = azurerm_proximity_placement_group.dev.id
      zones                        = [3]
      ultra_ssd_enabled            = false
    }

    "adcirchpc" = {
      vm_size                      = "Standard_HB120-16rs_v3"
      node_count                   = 1
      node_labels                  = null
      node_taints                  = null
      proximity_placement_group_id = azurerm_proximity_placement_group.dev.id
      zones                        = [3]
      ultra_ssd_enabled            = false
    }
  }
}
