variable "rgname" {
  type = string 
}
variable "location" {
  type = string 
}
variable "name" {
  type = string 
}
variable "sku" {
  type = string
  default = "Standard_DS1_v2"
}

variable "subnet_id" {
  type = string 
}

variable "enable_public_ip" {
    type = bool
    default = false
}

variable "custom_data" {
    type = string
    default = null
}