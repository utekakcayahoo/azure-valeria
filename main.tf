# We strongly recommend using the required_providers block to set the
# Azure Provider source and version being used
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=4.1.0"
    }
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {}
  subscription_id = "312a5e10-2a96-4a34-9a06-ac047e929ffa"

}

resource "azurerm_resource_group" "exampleu" {
  name     = "exampleu-resources"
  location = "West Europe"
}

resource "azurerm_data_share_account" "exampleu" {
  name                = "exampleu-dsa"
  location            = azurerm_resource_group.exampleu.location
  resource_group_name = azurerm_resource_group.exampleu.name
  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_data_share" "exampleu" {
  name       = "exampleu_ds"
  account_id = azurerm_data_share_account.exampleu.id
  kind       = "CopyBased"
}

resource "azurerm_storage_account" "exampleu" {
  name                     = "exampleustr"
  resource_group_name      = azurerm_resource_group.exampleu.name
  location                 = azurerm_resource_group.exampleu.location
  account_kind             = "BlobStorage"
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_data_lake_gen2_filesystem" "exampleu" {
  name               = "exampleu-dlg2fs"
  storage_account_id = azurerm_storage_account.exampleu.id
}

data "azuread_service_principal" "exampleu" {
  display_name = azurerm_data_share_account.exampleu.name
}

resource "azurerm_role_assignment" "exampleu" {
  scope                = azurerm_storage_account.exampleu.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = data.azuread_service_principal.exampleu.object_id
}

resource "azurerm_data_share_dataset_data_lake_gen2" "exampleu" {
  name               = "accexampleu-dlg2ds"
  share_id           = azurerm_data_share.exampleu.id
  storage_account_id = azurerm_storage_account.exampleu.id
  file_system_name   = azurerm_storage_data_lake_gen2_filesystem.exampleu.name
  file_path          = "myfile.txt"
  depends_on = [
    azurerm_role_assignment.exampleu,
  ]
}