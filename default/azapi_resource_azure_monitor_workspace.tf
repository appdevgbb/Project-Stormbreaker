/* 
 * azapi will be used to create an Azure Monitor Workspace (Preview)
 * Currently locations during the preview are: 
 *   eastus,centralindia,centralus,eastus2,northeurope,southcentralus,
 *   southeastasia,uksouth,westeurope,westus,westus2.
 */
# resource "azurerm_resource_group" "rg_azure_monitor_workspace" {
#   name     = "rg-${var.prefix}-azure-monitor-workspace-${var.suffix}"
#   location = "westus2"
# }

# resource "azapi_resource" "azure_monitor_workspace" {
#   type      = "microsoft.monitor/accounts@2021-06-03-preview"
#   name      = "${var.prefix}-azure-monitor-workspace"
#   location  = azurerm_resource_group.default.location
#   parent_id = azurerm_resource_group.default.id

#   body = {
#     properties = {}
#   }
# }


resource "azurerm_monitor_workspace" "stormbreaker_azure_monitor_workspace" {
  name                = "${var.prefix}-azure-monitor-workspace"
  resource_group_name = azurerm_resource_group.default.name
  location            = azurerm_resource_group.default.location
}