variable "cluster_name" {
  type = string
}

variable "network_cidr" {
  type = string
}

variable "subnet_cidr" {
  type = string
}

variable "network_zone" {
  type = string
}

variable "labels" {
  type    = map(string)
  default = {}
}
