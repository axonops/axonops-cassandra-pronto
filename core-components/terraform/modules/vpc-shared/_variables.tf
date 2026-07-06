variable "vpc_id" { type = string }
variable "region" {}
variable "account_id" {}

# NAT gateway placement: one NAT in the first ingress subnet (already has IGW
# egress via a public IP), routed to from a dedicated table scoped to only the
# data subnets -- the shared/default VPC's main route table is left untouched.
variable "ingress_subnet_ids" { type = list(string) }
variable "data_subnet_ids" { type = list(string) }
