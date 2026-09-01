vpc_cidr             = "10.12.0.0/16"
az_count             = 3
public_subnet_cidrs  = ["10.12.0.0/24", "10.12.1.0/24", "10.12.2.0/24"]
private_subnet_cidrs = ["10.12.10.0/24", "10.12.11.0/24", "10.12.12.0/24"]
nat_strategy         = "per_az"
