variable "cluster_name" {
  type = string
}

variable "network_cidr" {
  type = string
}

variable "ssh_allowed_cidrs" {
  type = list(string)
}

variable "api_allowed_cidrs" {
  type = list(string)
}

variable "labels" {
  type    = map(string)
  default = {}
}
