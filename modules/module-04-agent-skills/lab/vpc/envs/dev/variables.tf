variable "vpc_cidr" {
  type = string
}

variable "az_count" {
  type = number
}

variable "public_subnet_cidrs" {
  type = list(string)
}

variable "private_subnet_cidrs" {
  type = list(string)
}

variable "nat_strategy" {
  type = string
}
