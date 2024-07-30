# Purpose: Create a Windows virtual machine in Azure with Terraform

# Declare the required providers
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">=2.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = ">=2.0"
    }
  }
}

# Get HashiCorp Vault stored secrets
provider "vault" {
  address = "http://127.0.0.1:8200"
}

data "vault_kv_secret" "azure" {
  path = "secret/azure"
}

data "vault_kv_secret" "ad" {
  path = "secret/ad"
}

# Define local variables
locals {
  client_id         = data.vault_kv_secret.azure.data["client_id"]
  client_secret     = data.vault_kv_secret.azure.data["client_secret"]
  subscription_id   = data.vault_kv_secret.azure.data["subscription_id"]
  tenant_id         = data.vault_kv_secret.azure.data["tenant_id"]
  ad_admin_username = data.vault_kv_secret.ad.data["ad_admin_username"]
  ad_admin_password = data.vault_kv_secret.ad.data["ad_admin_password"]
}

# Configure the Azure provider
provider "azurerm" {
  features {}
  client_id       = local.client_id
  client_secret   = local.client_secret
  subscription_id = local.subscription_id
  tenant_id       = local.tenant_id
}

# Create a resource group
resource "azurerm_resource_group" "rg" {
  name     = "workstations-rg"
  location = "East US"
}

# Create a virtual network, subnet, and network security group
resource "azurerm_virtual_network" "vnet" {
  name                = "workstations-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# Create a subnet
resource "azurerm_subnet" "subnet" {
  name                 = "workstations-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Create a network security group and security rules
resource "azurerm_network_security_group" "nsg" {
  name                = "workstations-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "allow-rdp"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "allow-powerhsell-remoting"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5985-5986"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Create a network interface and connect it to a public IP address
resource "azurerm_network_interface" "nic" {
  count               = var.workstation_count
  name                = "workstation-nic-${count.index}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.public_ip[count.index].id
  }
}

# Create a public IP address
resource "azurerm_public_ip" "public_ip" {
  count               = var.workstation_count
  name                = "workstation-pip-${count.index}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Dynamic"
}

# Create a Windows virtual machine
resource "azurerm_windows_virtual_machine" "vm" {
  count                 = var.workstation_count
  name                  = "workstation-${count.index}"
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  network_interface_ids = [azurerm_network_interface.nic[count.index].id]
  size                  = "Standard_D2s_v3"

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsDesktop"
    offer     = "Windows-11"
    sku       = "win11-21h2-pro"
    version   = "latest"
  }

  admin_username = local.ad_admin_username
  admin_password = local.ad_admin_password
}

# Configure WinRM on the Windows virtual machine
resource "azurerm_virtual_machine_extension" "winrm_config" {
  count                      = var.workstation_count
  name                       = "winrm-config-${count.index}"
  virtual_machine_id         = azurerm_windows_virtual_machine.vm[count.index].id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.9"
  auto_upgrade_minor_version = true

  settings = <<SETTINGS
  {
    "fileUris": ["https://raw.githubusercontent.com/AlbanAndrieu/ansible-windows/master/files/ConfigureRemotingForAnsible.ps1"], "commandToExecute": "powershell -ExecutionPolicy Unrestricted -File ConfigureRemotingForAnsible.ps1"
  }
  SETTINGS

  depends_on = [
    azurerm_windows_virtual_machine.vm
  ]
}
