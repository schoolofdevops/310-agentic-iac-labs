variable "environment" {
  type        = string
  description = "Environment name, used in resource Name tags"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC-wide CIDR block, must not overlap with any other environment's block"
}

variable "az_count" {
  type        = number
  description = "Number of availability zones this environment spans, one public + one private subnet per AZ"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "One CIDR per AZ for the public subnets, length must equal az_count"
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "One CIDR per AZ for the private subnets, length must equal az_count"
}

variable "nat_strategy" {
  type        = string
  description = "\"single\" shares one NAT gateway across all private subnets, \"per_az\" gives every AZ its own so one NAT outage never takes down another AZ"

  validation {
    condition     = contains(["single", "per_az"], var.nat_strategy)
    error_message = "nat_strategy must be \"single\" or \"per_az\"."
  }
}

variable "tags" {
  type        = map(string)
  description = "Extra tags merged onto every resource, on top of Environment and ManagedBy"
  default     = {}
}
