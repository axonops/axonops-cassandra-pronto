locals {
  cas_ami_tags = {
    "AmiName" = "${data.aws_ami.cassandra.name}"
  }
}

data "aws_ami" "cassandra" {
  most_recent = true
  owners      = [var.ami_owner_id]
  filter {
    name   = "name"
    values = ["${var.ami_prefix}*"]
  }
}

resource "aws_launch_template" "cassandra-config" {
  name_prefix   = "${var.cluster_name}-"
  image_id      = data.aws_ami.cassandra.id
  instance_type = var.instance_type
  ebs_optimized = true

  # base64_encode = true on the cloudinit_config data source, so this is already base64
  user_data = data.cloudinit_config.cassandra.rendered

  placement {
    tenancy = "default"
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups = compact([
      aws_security_group.cas-bastion-access.id,
      aws_security_group.cas-client-access.id,
      aws_security_group.cas-internode.id,
      var.sg_ops_nodes_to_cas,
    ])
  }

  iam_instance_profile {
    arn = var.cassandra_profile_arn
  }

  block_device_mappings {
    device_name = data.aws_ami.cassandra.root_device_name
    ebs {
      volume_type = var.root_volume_type
      volume_size = var.root_volume_size
      # iops is only a valid parameter for gp3/io1/io2 volumes, not gp2
      iops                  = contains(["gp3", "io1", "io2"], var.root_volume_type) ? var.root_volume_iops : null
      delete_on_termination = true
      encrypted             = true
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "cassandra-seed-node" {
  depends_on                = [aws_launch_template.cassandra-config]
  count                     = length(var.availability_zones)
  name                      = "asg-${var.cluster_name}-seed-${count.index}"
  max_size                  = 2
  min_size                  = 1
  health_check_grace_period = 600
  health_check_type         = "EC2"
  desired_capacity          = "1"

  launch_template {
    id      = aws_launch_template.cassandra-config.id
    version = "$Latest"
  }

  vpc_zone_identifier = [element(var.cluster_subnet_ids, count.index)]

  lifecycle {
    create_before_destroy = true
  }

  tag {
    key                 = "Name"
    value               = "${var.cluster_name}-seed-${count.index}"
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = merge(var.ec2_tags, local.required_ec2_tags, local.cas_ami_tags)

    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}

resource "aws_autoscaling_group" "cassandra-non-seed-node" {
  depends_on                = [aws_launch_template.cassandra-config]
  count                     = (var.cassandra_nodes_per_az - 1) * length(var.availability_zones)
  name                      = "asg-${var.cluster_name}-non-seed-${count.index}"
  max_size                  = 2
  min_size                  = 1
  health_check_grace_period = 600
  health_check_type         = "EC2"
  desired_capacity          = "1"

  launch_template {
    id      = aws_launch_template.cassandra-config.id
    version = "$Latest"
  }

  vpc_zone_identifier = [element(var.cluster_subnet_ids, count.index)]

  lifecycle {
    create_before_destroy = true
  }

  tag {
    key                 = "Name"
    value               = "${var.cluster_name}-non-seed-${count.index}"
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = merge(var.ec2_tags, local.required_ec2_tags, local.cas_ami_tags)

    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}

