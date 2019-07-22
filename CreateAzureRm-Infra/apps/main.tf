# Providers (Infra & Apps)

provider "azurerm" {
  subscription_id = var.subscription_id
  client_id       = var.service_principals[1]["Application_Id"]
  client_secret   = var.service_principals[1]["Application_Secret"]
  tenant_id       = var.tenant_id
  alias           = "service_principal_apps"
}

# Module

####################################################
##########           Infra                ##########
####################################################

## Prerequisistes Inventory
data "azurerm_resource_group" "Infr" {
  name     = var.rg_infr_name
  provider = azurerm.service_principal_apps
}

data "azurerm_storage_account" "Infr" {
  name                = var.sa_infr_name
  resource_group_name = var.rg_infr_name
  provider            = azurerm.service_principal_apps
}

####################################################
##########              Apps              ##########
####################################################

## Prerequisistes Inventory
data "azurerm_resource_group" "MyApps" {
  name     = var.rg_apps_name
  provider = azurerm.service_principal_apps
}

data "azurerm_route_table" "Infr" {
  name                = "jdld-infr-core-rt1"
  resource_group_name = data.azurerm_resource_group.Infr.name
  provider            = azurerm.service_principal_apps
}

data "azurerm_network_security_group" "Infr" {
  name                = "jdld-infr-snet-apps-nsg1"
  resource_group_name = var.rg_infr_name
  provider            = azurerm.service_principal_apps
}

## Core Network components
module "Az-NetworkSecurityGroup-Apps" {
  source                  = "git::https://github.com/JamesDLD/terraform.git//module/Az-NetworkSecurityGroup?ref=master"
  nsgs                    = var.apps_nsgs
  nsg_prefix              = "${var.app_name}-${var.env_name}-"
  nsg_suffix              = "-nsg1"
  nsg_location            = data.azurerm_resource_group.MyApps.location
  nsg_resource_group_name = data.azurerm_resource_group.MyApps.name
  nsg_tags                = data.azurerm_resource_group.MyApps.tags
  providers = {
    azurerm = azurerm.service_principal_apps
  }
}

module "Az-Subnet-Apps" {
  source                     = "git::https://github.com/JamesDLD/terraform.git//module/Az-Subnet?ref=master"
  subscription_id            = var.subscription_id
  subnet_resource_group_name = var.rg_infr_name
  snet_list                  = var.apps_snets
  vnet_names                 = ["infra-jdld-infr-apps-net1"]
  nsgs_ids                   = [data.azurerm_network_security_group.Infr.id]
  route_table_ids            = [data.azurerm_route_table.Infr.id]
  providers = {
    azurerm = azurerm.service_principal_apps
  }
}

## Virtual Machines components

module "Az-LoadBalancer-Apps" {
  source                 = "git::https://github.com/JamesDLD/terraform.git//module/Az-LoadBalancer?ref=master"
  Lbs                    = var.Lbs
  lb_prefix              = "${var.app_name}-${var.env_name}-"
  lb_suffix              = "-lb1"
  lb_location            = data.azurerm_resource_group.MyApps.location
  lb_resource_group_name = data.azurerm_resource_group.MyApps.name
  Lb_sku                 = var.Lb_sku
  subnets_ids            = module.Az-Subnet-Apps.subnets_ids
  lb_tags                = data.azurerm_resource_group.MyApps.tags
  LbRules                = var.LbRules
  providers = {
    azurerm = azurerm.service_principal_apps
  }
}

module "Az-Vm-Apps" {
  source                             = "git::https://github.com/JamesDLD/terraform.git//module/Az-Vm?ref=feature/nomoreusingnull_resource"
  sa_bootdiag_storage_uri            = data.azurerm_storage_account.Infr.primary_blob_endpoint
  nsgs_ids                           = module.Az-NetworkSecurityGroup-Apps.nsgs_ids
  public_ip_ids                      = ["null"]
  internal_lb_backend_ids            = module.Az-LoadBalancer-Apps.lb_backend_ids
  public_lb_backend_ids              = ["null"]
  key_vault_id                       = ""
  disable_log_analytics_dependencies = "true"
  workspace_resource_group_name      = ""
  workspace_name                     = ""
  subnets_ids                        = module.Az-Subnet-Apps.subnets_ids
  vms                                = var.vms
  linux_storage_image_reference      = var.linux_storage_image_reference
  windows_storage_image_reference    = var.windows_storage_image_reference #If no need just fill "windows_storage_image_reference = []" in the tfvars file
  vm_location                        = data.azurerm_resource_group.MyApps.location
  vm_resource_group_name             = data.azurerm_resource_group.MyApps.name
  vm_prefix                          = "${var.app_name}-${var.env_name}-"
  admin_username                     = var.app_admin
  admin_password                     = var.pass
  ssh_key                            = var.ssh_key
  vm_tags                            = data.azurerm_resource_group.MyApps.tags
  providers = {
    azurerm = azurerm.service_principal_apps
  }
}

# Infra cross services for Apps
module "Az-RecoveryServicesBackupProtection-Apps" {
  source          = "git::https://github.com/JamesDLD/terraform.git//module/Az-RecoveryServicesBackupProtection?ref=master"
  subscription_id = var.subscription_id
  bck_vms_names = concat(
    module.Az-Vm-Apps.linux_vms_names,
    module.Az-Vm-Apps.windows_vms_names,
  ) #Names of the resources to backup
  bck_vms_resource_group_names = concat(
    module.Az-Vm-Apps.linux_vms_resource_group_names,
    module.Az-Vm-Apps.windows_vms_resource_group_names,
  ) #Resource Group Names of the resources to backup
  bck_vms                     = concat(var.vms)
  bck_rsv_name                = var.bck_rsv_name
  bck_rsv_resource_group_name = data.azurerm_resource_group.Infr.name
  providers = {
    azurerm = azurerm.service_principal_apps
  }
}

## Infra common services
#N/A
