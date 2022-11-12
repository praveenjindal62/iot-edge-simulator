
terraform {
  required_providers {
    shell = {
      source  = "scottwinkler/shell"
      version = "1.7.7"
    }
  }
}

provider "azurerm" {
  features {}
}


variable "number_of_edge_devices" {
  type    = number
  default = 3
}

resource "azurerm_resource_group" "rg" {
  name     = "iot-hub-rg"
  location = "eastus2"
}

resource "random_string" "random_suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

resource "azurerm_iothub" "iothub" {
  name                = "iot-hub-pj62-${random_string.random_suffix.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  sku {
    name     = "F1"
    capacity = "1"
  }
}

resource "azurerm_storage_account" "storageaccount" {
  name                     = "storageacc${random_string.random_suffix.result}"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "GRS"
}

resource "azurerm_storage_table" "storage_table" {
  name                 = "IOTDATA"
  storage_account_name = azurerm_storage_account.storageaccount.name
}

resource "azurerm_storage_table_entity" "entity" {
  storage_account_name = azurerm_storage_account.storageaccount.name
  table_name           = azurerm_storage_table.storage_table.name

  partition_key = "PartitionKey"
  row_key       = "RowKey"

  entity = {

  }
}



resource "azurerm_stream_analytics_job" "stream_analytics_job" {
  name                = "stream-analytics-job-${random_string.random_suffix.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  output_error_policy = "Drop"
  streaming_units     = 3

  transformation_query = <<QUERY
WITH machineEvent AS (
SELECT
    event.timeCreated,
    machineReading.PropertyName,
    machineReading.PropertyValue
FROM [iot-hub-input-01] AS event
CROSS APPLY GetRecordProperties(event.machine) AS machineReading
),
ambientEvent AS (
SELECT
    event.timeCreated,
    ambientReading.PropertyName,
    ambientReading.PropertyValue
FROM [iot-hub-input-01] AS event
CROSS APPLY GetRecordProperties(event.ambient) AS ambientReading
),
device AS (
SELECT
    event.timeCreated,
    device.PropertyName,
    device.PropertyValue
FROM [iot-hub-input-01] AS event
CROSS APPLY GetRecordProperties(event.IotHub) AS device
)
SELECT me1.PropertyValue AS MachineTemperature,
       me2.PropertyValue AS MachinePressure,
       ae1.PropertyValue AS AmbientTemperaturem,
       ae2.PropertyValue AS AmbientHumidity,
       device.PropertyValue AS ${azurerm_storage_table_entity.entity.partition_key},
       me1.timeCreated AS ${azurerm_storage_table_entity.entity.row_key}
INTO [output-01]
FROM machineEvent AS me1
JOIN machineEvent AS me2
ON me1.timeCreated = me2.timeCreated 
AND DATEDIFF(minute,me1,me2) BETWEEN 0 AND 0 
JOIN ambientEvent AS ae1
ON me1.timeCreated = ae1.timeCreated 
AND DATEDIFF(minute,me1,ae1) BETWEEN 0 AND 0 
JOIN ambientEvent AS ae2
ON me1.timeCreated = ae2.timeCreated 
AND DATEDIFF(minute,me1,ae2) BETWEEN 0 AND 0 
JOIN device AS device
ON me1.timeCreated = device.timeCreated 
AND DATEDIFF(minute,me1,device) BETWEEN 0 AND 0 
WHERE me1.PropertyName = 'temperature'
AND me2.PropertyName = 'pressure'
AND ae1.PropertyName = 'temperature'
AND ae2.PropertyName = 'humidity'
AND device.PropertyName = 'ConnectionDeviceId'
QUERY

}

resource "azurerm_stream_analytics_stream_input_iothub" "stream_analytics_job_input" {
  name                         = "iot-hub-input-01"
  stream_analytics_job_name    = azurerm_stream_analytics_job.stream_analytics_job.name
  resource_group_name          = azurerm_stream_analytics_job.stream_analytics_job.resource_group_name
  endpoint                     = "messages/events"
  eventhub_consumer_group_name = "$Default"
  iothub_namespace             = azurerm_iothub.iothub.name
  shared_access_policy_key     = azurerm_iothub.iothub.shared_access_policy[0].primary_key
  shared_access_policy_name    = "iothubowner"

  serialization {
    type     = "Json"
    encoding = "UTF8"
  }
}

resource "azurerm_stream_analytics_output_table" "stream_analytics_job_output" {
  name                      = "output-01"
  stream_analytics_job_name = azurerm_stream_analytics_job.stream_analytics_job.name
  resource_group_name       = azurerm_stream_analytics_job.stream_analytics_job.resource_group_name
  storage_account_name      = azurerm_storage_account.storageaccount.name
  storage_account_key       = azurerm_storage_account.storageaccount.primary_access_key
  table                     = azurerm_storage_table.storage_table.name
  partition_key             = azurerm_storage_table_entity.entity.partition_key
  row_key                   = azurerm_storage_table_entity.entity.row_key
  batch_size                = 5
}

resource "shell_script" "register_iot_edge_device" {
  lifecycle_commands {
    create = "$script create"
    read   = "$script read"
    delete = "$script delete"
  }
  for_each = toset(local.edge_device_list)
  environment = {
    iot_hub_name                 = azurerm_iothub.iothub.name
    iot_edge_device_name         = each.value
    iot_module_settings_filepath = "./iot-device-module-settings.json"
    script                       = "./iot-device-lifecycle.sh"
  }
}


resource "azurerm_virtual_network" "vnet" {
  name                = "example-network"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "subnet" {
  name                 = "internal"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_network_security_group" "ssh" {
  name                = "ssh-allow"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "ssh"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "ssh" {
  subnet_id                 = azurerm_subnet.subnet.id
  network_security_group_id = azurerm_network_security_group.ssh.id
}

module "vm" {
  for_each         = toset(local.edge_device_list)
  source           = "./modules/vm"
  rgname           = azurerm_resource_group.rg.name
  location         = azurerm_resource_group.rg.location
  name             = each.value
  subnet_id        = azurerm_subnet.subnet.id
  enable_public_ip = false
  custom_data      = replace(local.custom_data, "#CONNECTION_STRING_HERE", shell_script.register_iot_edge_device[each.value].output.connectionString)
}

locals {
  custom_data = <<CUSTOM_DATA
  #!/bin/bash
  wget https://packages.microsoft.com/config/ubuntu/20.04/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
  sudo dpkg -i packages-microsoft-prod.deb
  rm packages-microsoft-prod.deb
  sudo apt-get update -y
  sudo apt-get install moby-engine -y
  sudo apt-get install aziot-edge defender-iot-micro-agent-edge -y
  sudo iotedge config mp --connection-string '#CONNECTION_STRING_HERE'
  sudo iotedge config apply
  CUSTOM_DATA

  edge_device_list = [for i in range(0, var.number_of_edge_devices) : "iot-edge-device-${i}"]
}

resource "null_resource" "start_stream_analytics_job" {
  depends_on = [
    azurerm_stream_analytics_output_table.stream_analytics_job_output,
    azurerm_stream_analytics_stream_input_iothub.stream_analytics_job_input,
    azurerm_stream_analytics_job.stream_analytics_job
  ]
  triggers = {
    create_trigger = random_string.random_suffix.id
    rg_name = azurerm_resource_group.rg.name
    stream_analytics_job_name = azurerm_stream_analytics_job.stream_analytics_job.name
  }
  provisioner "local-exec" {
    command = "az stream-analytics job start --job-name ${self.triggers.stream_analytics_job_name} --resource-group ${self.triggers.rg_name}"
    when = create
  }

  provisioner "local-exec" {
    command = "az stream-analytics job stop --job-name ${self.triggers.stream_analytics_job_name} --resource-group ${self.triggers.rg_name}"
    when = destroy
  }
}