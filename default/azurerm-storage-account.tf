resource "azurerm_storage_account" "stormbreaker" {
  name                     = "stormbreakeracc"
  location                 = azurerm_resource_group.default.location
  resource_group_name      = azurerm_resource_group.default.name
  account_tier             = "Premium"
  account_replication_type = "LRS"
  account_kind             = "BlockBlobStorage"
  is_hns_enabled           = "true"
  nfsv3_enabled            = "true"

  network_rules {
    default_action         = "Deny"
    bypass                 = ["AzureServices"]
    virtual_network_subnet_ids = [azurerm_subnet.stormbreaker-cluster.id]
  }

}

# resource "azurerm_storage_data_lake_gen2_filesystem" "example" {
#   name               = "example"
#   storage_account_id = azurerm_storage_account.stormbreaker.id

#   properties = {
#     hello = "aGVsbG8="
#   }
# }