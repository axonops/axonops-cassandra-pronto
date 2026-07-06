# Existing/shared VPCs (TERRAFORM_MANAGED_VPC=false) are only read via
# modules/vpc-info -- nothing provisions a NAT path for the data subnets in
# that path, unlike modules/vpc-create's from-scratch VPC. Data subnet
# instances have no public IP, so without this they have no route to any AWS
# API (EC2/SSM/S3/STS) despite an IGW route being present on the VPC's main
# table.
#
# Scoped on purpose: a dedicated route table is associated only to the data
# subnets, rather than touching the (likely shared) main route table those
# subnets currently fall back to.

resource "aws_eip" "cassandra-nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "cassandra" {
  allocation_id = aws_eip.cassandra-nat.id
  subnet_id     = var.ingress_subnet_ids[0]
}

resource "aws_route_table" "data-nat" {
  vpc_id = var.vpc_id

  tags = {
    Name = "cassandra-data-nat"
  }
}

resource "aws_route" "data-natgw" {
  route_table_id         = aws_route_table.data-nat.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.cassandra.id
}

resource "aws_route_table_association" "data-nat-assoc" {
  count          = length(var.data_subnet_ids)
  subnet_id      = var.data_subnet_ids[count.index]
  route_table_id = aws_route_table.data-nat.id
}
