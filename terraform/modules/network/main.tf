variable "name" {}
variable "azs" { type = list(string) }
variable "cidr" { default = "10.0.0.0/16" }
variable "single_nat" { default = true }

locals {
  n     = length(var.azs)
  nat_n = var.single_nat ? 1 : length(var.azs)
}

resource "aws_vpc" "this" {
  cidr_block           = var.cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = var.name }
}
resource "aws_internet_gateway" "this" { vpc_id = aws_vpc.this.id }

resource "aws_subnet" "public" {
  count                   = local.n
  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.cidr, 8, count.index)
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.name}-public-${count.index}" }
}
resource "aws_subnet" "app" {
  count             = local.n
  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.cidr, 8, 10 + count.index)
  availability_zone = var.azs[count.index]
  tags              = { Name = "${var.name}-app-${count.index}" }
}
resource "aws_subnet" "data" {
  count             = local.n
  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.cidr, 8, 20 + count.index)
  availability_zone = var.azs[count.index]
  tags              = { Name = "${var.name}-data-${count.index}" }
}

resource "aws_eip" "nat" {
  count  = local.nat_n
  domain = "vpc"
}
resource "aws_nat_gateway" "this" {
  count         = local.nat_n
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  depends_on    = [aws_internet_gateway.this]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
}
resource "aws_route_table_association" "public" {
  count          = local.n
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table" "app" {
  count  = local.n
  vpc_id = aws_vpc.this.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[var.single_nat ? 0 : count.index].id
  }
}
resource "aws_route_table_association" "app" {
  count          = local.n
  subnet_id      = aws_subnet.app[count.index].id
  route_table_id = aws_route_table.app[count.index].id
}
# Data subnets: no default route at all, so no internet in or out
resource "aws_route_table" "data" { vpc_id = aws_vpc.this.id }
resource "aws_route_table_association" "data" {
  count          = local.n
  subnet_id      = aws_subnet.data[count.index].id
  route_table_id = aws_route_table.data.id
}

output "vpc_id" { value = aws_vpc.this.id }
output "public_subnet_ids" { value = aws_subnet.public[*].id }
output "app_subnet_ids" { value = aws_subnet.app[*].id }
output "data_subnet_ids" { value = aws_subnet.data[*].id }
