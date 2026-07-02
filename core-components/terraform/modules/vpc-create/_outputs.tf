output "vpc_id" {
  value = aws_vpc.cassandra-vpc.id
}

output "vpc_cidr" {
  value = aws_vpc.cassandra-vpc.cidr_block
}

output "data_subnet_ids" {
  value = aws_subnet.cassandra-vpc-data.*.id
}

output "data_subnet_cidr_blocks" {
  value = aws_subnet.cassandra-vpc-data.*.cidr_block
}

output "ingress_subnet_ids" {
  value = aws_subnet.cassandra-vpc-ingress.*.id
}

output "ingress_subnet_cidr_blocks" {
  value = aws_subnet.cassandra-vpc-ingress.*.cidr_block
}
