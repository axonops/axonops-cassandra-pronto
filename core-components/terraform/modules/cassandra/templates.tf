data "template_file" "cassandra-init" {
  template = file("${path.module}/files/cassandra-init.tpl")

  vars = {
    dc_name              = var.datacenter
    auto_start_cassandra = var.auto_start_cassandra
    region               = var.region
    ssh_bucket           = var.tfstate_bucket
    ssh_prefix           = "${local.cluster_key}/files/ssh/ec2-user/user-keys.yaml"
    ec2_tag_map          = jsonencode(merge(var.ec2_tags, local.required_ec2_tags))
  }
}

data "template_cloudinit_config" "cassandra" {
  gzip          = false
  base64_encode = false

  part {
    content_type = "text/cloud-config"
    content = file(
      "${path.module}/../../../../configurations/${local.cluster_key}/user-keys.yaml",
    )
  }

  part {
    filename     = "cassandra-init.sh"
    content_type = "text/x-shellscript"
    content      = data.template_file.cassandra-init.rendered
  }
}

