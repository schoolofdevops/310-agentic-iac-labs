vpc_cidr             = "10.11.0.0/16"
az_count             = 2
public_subnet_cidrs  = ["10.11.0.0/24", "10.11.1.0/24"]
private_subnet_cidrs = ["10.11.10.0/24", "10.11.11.0/24"]
nat_strategy         = "single"
