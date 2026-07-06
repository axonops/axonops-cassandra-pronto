#############################################
# LC and ASG for bastion nodes
#############################################

data "aws_ami" "bastion-ami" {
  count       = length(var.existing_bastion_sg_id) == 0 ? 1 : 0
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["${var.ami_prefix}*"]
  }

  # ami_prefix matches both x86_64 and arm64 AMI variants; pin to x86_64 to match instance_type default (t3.micro)
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

resource "aws_launch_template" "bastion-lt" {
  count       = length(var.existing_bastion_sg_id) == 0 ? 1 : 0
  name_prefix = "bastion-lt-"
  image_id    = data.aws_ami.bastion-ami[0].id

  instance_type = var.instance_type

  placement {
    tenancy = "default"
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups = [
      aws_security_group.bastion-sg[0].id,
      aws_security_group.bastion-ssh-ingress[0].id,
    ]
  }

  # base64_encode = true on the cloudinit_config data source, so this is already base64
  user_data = data.cloudinit_config.bastion-init[0].rendered

  iam_instance_profile {
    arn = var.bastion_role_arn
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "bastion-asg" {
  count                     = length(var.existing_bastion_sg_id) == 0 ? 1 : 0
  depends_on                = [aws_launch_template.bastion-lt]
  name_prefix               = "bastion-asg-"
  max_size                  = 1
  min_size                  = 1
  health_check_grace_period = 600
  health_check_type         = "EC2"
  desired_capacity          = 1

  launch_template {
    id      = aws_launch_template.bastion-lt[0].id
    version = "$Latest"
  }

  vpc_zone_identifier = var.ingress_subnet_ids
  target_group_arns   = [aws_lb_target_group.bastion-targets[0].id]

  lifecycle {
    create_before_destroy = true
  }


  tag {
    key                 = "Name"
    value               = "bastion"
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = merge(var.ec2_tags, local.required_ec2_tags)

    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}

