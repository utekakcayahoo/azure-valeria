##### Main #####

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=4.1.0"
    }
    databricks = {
      source  = "databricks/databricks"
      version = "1.62.0"
    }
    random  = "~> 3.6"
  }
}

provider "azurerm" {
  features {}
  subscription_id = "312a5e10-2a96-4a34-9a06-ac047e929ffa"
}

provider "databricks" {
}

##### Variables #####

variable "region" {
  type    = string
  default = "westeurope"
}
variable "cidr" {
  type        = string
  default     = "10.179.0.0/20"
  description = "Network range for created virtual network."
}

variable "no_public_ip" {
  type        = bool
  default     = true
  description = "Defines whether Secure Cluster Connectivity (No Public IP) should be enabled."
}

##### Azure Datalake #####

resource "azurerm_resource_group" "mason" {
  name     = "mason-storage"
  location = "West Europe"
}

resource "azurerm_storage_account" "mason" {
  name                     = "masonpond"
  resource_group_name      = azurerm_resource_group.mason.name
  location                 = azurerm_resource_group.mason.location
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"
  is_hns_enabled           = true
}

resource "azurerm_storage_data_lake_gen2_filesystem" "mason" {
  name               = "manualupload"
  storage_account_id = azurerm_storage_account.mason.id
}

resource "azurerm_role_assignment" "devs_blob_data_reader" {
  scope                = azurerm_storage_account.mason.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = data.azuread_group.devs.object_id
}

resource "azurerm_role_assignment" "devs_blob_data_contributor" {
  scope                = azurerm_storage_account.mason.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azuread_group.devs.object_id
}

data "azuread_group" "devs" {
  display_name = "Devs"
}

##### Azure Databricks #####

# Workspace
data "azurerm_client_config" "current" {
}

data "external" "me" {
  program = ["az", "account", "show", "--query", "user"]
}

locals {
  prefix = "mason-databricks"
  tags = {
    Environment = "mason-databricks"
    Owner       = lookup(data.external.me.result, "name")
  }
}

resource "azurerm_resource_group" "this" {
  name     = "${local.prefix}"
  location = var.region
  tags     = local.tags
}

resource "azurerm_virtual_network" "this" {
  name                = "${local.prefix}-vnet"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  address_space       = [var.cidr]
  tags                = local.tags
}

resource "azurerm_network_security_group" "this" {
  name                = "${local.prefix}-nsg"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.tags
}

resource "azurerm_subnet" "public" {
  name                 = "${local.prefix}-public"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [cidrsubnet(var.cidr, 3, 0)]

  delegation {
    name = "databricks"
    service_delegation {
      name = "Microsoft.Databricks/workspaces"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/action",
        "Microsoft.Network/virtualNetworks/subnets/prepareNetworkPolicies/action",
        "Microsoft.Network/virtualNetworks/subnets/unprepareNetworkPolicies/action"
      ]
    }
  }
}

resource "azurerm_subnet_network_security_group_association" "public" {
  subnet_id                 = azurerm_subnet.public.id
  network_security_group_id = azurerm_network_security_group.this.id
}

resource "azurerm_subnet" "private" {
  name                 = "${local.prefix}-private"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [cidrsubnet(var.cidr, 3, 1)]

  delegation {
    name = "databricks"
    service_delegation {
      name = "Microsoft.Databricks/workspaces"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/action",
        "Microsoft.Network/virtualNetworks/subnets/prepareNetworkPolicies/action",
        "Microsoft.Network/virtualNetworks/subnets/unprepareNetworkPolicies/action"
      ]
    }
  }
}

resource "azurerm_subnet_network_security_group_association" "private" {
  subnet_id                 = azurerm_subnet.private.id
  network_security_group_id = azurerm_network_security_group.this.id
}

resource "azurerm_databricks_workspace" "this" {
  name                        = "${local.prefix}-workspace"
  resource_group_name         = azurerm_resource_group.this.name
  location                    = azurerm_resource_group.this.location
  sku                         = "premium"
  managed_resource_group_name = "${local.prefix}-workspace"
  tags                        = local.tags

  custom_parameters {
    no_public_ip                                         = var.no_public_ip
    virtual_network_id                                   = azurerm_virtual_network.this.id
    private_subnet_name                                  = azurerm_subnet.private.name
    public_subnet_name                                   = azurerm_subnet.public.name
    public_subnet_network_security_group_association_id  = azurerm_subnet_network_security_group_association.public.id
    private_subnet_network_security_group_association_id = azurerm_subnet_network_security_group_association.private.id
  }
}

output "databricks_host" {
  value = "https://${azurerm_databricks_workspace.this.workspace_url}/"
}

# All Purpose Cluster

# data "databricks_spark_version" "latest_lts" {
#   long_term_support = true
# }

resource "databricks_cluster" "shared_autoscaling" {
  cluster_name            = "Shared Non-ML"
  spark_version           = "16.1.x-scala2.12" # data.databricks_spark_version.latest_lts.id
  node_type_id            = "Standard_F4"
  driver_node_type_id     = "Standard_F4"
  autotermination_minutes = 20
  autoscale {
    min_workers = 1
    max_workers = 3
  }
}

# # SQL Warehouse
# resource "databricks_sql_endpoint" "this" {
#   name                        = "Serverless Starter Warehouse"
#   cluster_size                = "2X-Small"
#   max_num_clusters            = 1
#   auto_stop_mins              = 5
#   enable_photon               = false
#   enable_serverless_compute   = true
#   channel {
#     name = "CHANNEL_NAME_PREVIEW"
#   }
#   tags {
#     custom_tags {
#       key   = "Owner"
#       value = lookup(data.external.me.result, "name")
#     }
#   }
# }
