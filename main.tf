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
  subscription_id = "0000000-0000-00000-000000"

}

resource "azurerm_resource_group" "example" {
  name     = "example-resources"
  location = "West Europe"
}

resource "azurerm_data_share_account" "example" {
  name                = "example-dsa"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name
  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_data_share" "example" {
  name       = "example_ds"
  account_id = azurerm_data_share_account.example.id
  kind       = "CopyBased"
}

resource "azurerm_storage_account" "example" {
  name                     = "examplestr"
  resource_group_name      = azurerm_resource_group.example.name
  location                 = azurerm_resource_group.example.location
  account_kind             = "BlobStorage"
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_data_lake_gen2_filesystem" "example" {
  name               = "example-dlg2fs"
  storage_account_id = azurerm_storage_account.example.id
}

data "azuread_service_principal" "example" {
  display_name = azurerm_data_share_account.example.name
}

resource "azurerm_role_assignment" "example" {
  scope                = azurerm_storage_account.example.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = data.azuread_service_principal.example.object_id
}

resource "azurerm_data_share_dataset_data_lake_gen2" "example" {
  name               = "accexample-dlg2ds"
  share_id           = azurerm_data_share.example.id
  storage_account_id = azurerm_storage_account.example.id
  file_system_name   = azurerm_storage_data_lake_gen2_filesystem.example.name
  file_path          = "myfile.txt"
  depends_on = [
    azurerm_role_assignment.example,
  ]
}