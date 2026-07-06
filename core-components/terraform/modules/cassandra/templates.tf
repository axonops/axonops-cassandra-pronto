locals {
  cassandra-init-rendered = templatefile("${path.module}/files/cassandra-init.tpl", {
    dc_name              = var.datacenter
    auto_start_cassandra = var.auto_start_cassandra
    region               = var.region
    ssh_bucket           = var.tfstate_bucket
    ssh_prefix           = "${local.cluster_key}/files/ssh/ec2-user/user-keys.yaml"
    ec2_tag_map          = jsonencode(merge(var.ec2_tags, local.required_ec2_tags))
  })
}

data "cloudinit_config" "cassandra" {
  gzip = false
  # launch templates require base64-encoded user_data (unlike the retired launch configuration)
  base64_encode = true

  part {
    content_type = "text/cloud-config"
    content = file(
      "${path.module}/../../../../configurations/${local.cluster_key}/user-keys.yaml",
    )
  }

  part {
    filename     = "cassandra-init.sh"
    content_type = "text/x-shellscript"
    content      = local.cassandra-init-rendered
  }
}

