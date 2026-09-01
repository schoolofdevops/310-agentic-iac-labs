locals {
  nat_count = var.nat_strategy == "per_az" ? var.az_count : 1

  common_tags = merge(var.tags, {
    Environment = var.environment
    ManagedBy   = "vpc-environment-scaffold-skill"
    Owner       = lookup(var.tags, "Owner", "platform-team")
  })
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(local.common_tags, { Name = "${var.environment}-vpc" })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.common_tags, { Name = "${var.environment}-igw" })
}

resource "aws_subnet" "public" {
  count                   = var.az_count
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  map_public_ip_on_launch = true
  tags                    = merge(local.common_tags, { Name = "${var.environment}-public-${count.index}" })
}

resource "aws_subnet" "private" {
  count      = var.az_count
  vpc_id     = aws_vpc.this.id
  cidr_block = var.private_subnet_cidrs[count.index]
  tags       = merge(local.common_tags, { Name = "${var.environment}-private-${count.index}" })
}

resource "aws_eip" "nat" {
  count  = local.nat_count
  domain = "vpc"
  tags   = merge(local.common_tags, { Name = "${var.environment}-nat-eip-${count.index}" })
}

resource "aws_nat_gateway" "this" {
  count         = local.nat_count
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  tags          = merge(local.common_tags, { Name = "${var.environment}-nat-${count.index}" })
  depends_on    = [aws_internet_gateway.this]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.common_tags, { Name = "${var.environment}-public-rt" })
}

resource "aws_route" "public_igw" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id              = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count          = var.az_count
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# One private route table per NAT gateway. With nat_strategy = "single" there's
# exactly one, and every private subnet routes through it. With "per_az" there's
# one per AZ, and each private subnet routes only through its own AZ's NAT.
resource "aws_route_table" "private" {
  count  = local.nat_count
  vpc_id = aws_vpc.this.id
  tags   = merge(local.common_tags, { Name = "${var.environment}-private-rt-${count.index}" })
}

resource "aws_route" "private_nat" {
  count                  = local.nat_count
  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[count.index].id
}

resource "aws_route_table_association" "private" {
  count          = var.az_count
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[var.nat_strategy == "per_az" ? count.index : 0].id
}
