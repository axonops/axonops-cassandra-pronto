output "bastion_profile_arn" {
  value = aws_iam_instance_profile.bastion-profile.arn
}

output "cassandra_profile_arn" {
  value = aws_iam_instance_profile.cassandra-profile.arn
}
