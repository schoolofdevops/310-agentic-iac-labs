module "vpc" {
  source = "../../modules/vpc"

  environment          = "staging"
  vpc_cidr             = var.vpc_cidr
  az_count             = var.az_count
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  nat_strategy         = var.nat_strategy
  tags                 = { Owner = "platform-team" }
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "nat_gateway_ids" {
  value = module.vpc.nat_gateway_ids
}
