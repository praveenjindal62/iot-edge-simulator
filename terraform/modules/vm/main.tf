

resource "azurerm_network_interface" "nic" {
  name                = "${var.name}-nic"
  location            = var.location
  resource_group_name = var.rgname

  ip_configuration {
    name                          = "${var.name}-ipconfig"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = var.enable_public_ip ? azurerm_public_ip.pip.0.id : null
  }
}

resource "azurerm_linux_virtual_machine" "main" {
  name                  = "${var.name}"
  location              = var.location
  resource_group_name   = var.rgname
  network_interface_ids = [azurerm_network_interface.nic.id]
  size                  = var.sku

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal-daily"
    sku       = "20_04-daily-lts"
    version   = "latest"
  }
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  admin_username      = "azureuser"
  admin_ssh_key {
    username   = "azureuser"
    public_key = file("~/.ssh/id_rsa.pub")
  }
}

resource "azurerm_public_ip" "pip" {
  count = var.enable_public_ip ? 1 : 0
  name                = "${var.name}-PIP"
  location            = var.location
  resource_group_name = var.rgname
  sku                 = "Basic"
  allocation_method   = "Dynamic"
}

resource "azurerm_virtual_machine_extension" "custom_script" {
  count = var.custom_data == null ? 0 : 1
  name                 = "custom_script"
  virtual_machine_id   = azurerm_linux_virtual_machine.main.id
  publisher            = "Microsoft.Azure.Extensions"
  type                 = "CustomScript"
  type_handler_version = "2.0"

  settings = <<SETTINGS
 {
  "script": "${base64encode(var.custom_data)}"
 }
SETTINGS
}