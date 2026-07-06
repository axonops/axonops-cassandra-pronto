#############################################
# User data (cloud-init) from template
#############################################

locals {
  bastion-tpl-rendered = length(var.existing_bastion_sg_id) == 0 ? templatefile("${path.module}/data/bastion-init.tpl", {
    account_id = var.account_id
    region     = var.region
    ssh_bucket = var.tfstate_bucket
    ssh_prefix = "${var.account_name}/${var.vpc_name}/vpc-resources/files/ssh/ec2-user/user-keys.yaml"
  }) : ""
}

data "cloudinit_config" "bastion-init" {
  count = length(var.existing_bastion_sg_id) == 0 ? 1 : 0
  gzip  = false
  # launch templates require base64-encoded user_data (unlike the retired launch configuration)
  base64_encode = true

  part {
    content_type = "text/cloud-config"
    content = file(
      "${path.module}/../../../../configurations/${var.account_name}/${var.vpc_name}/vpc-resources/user-keys.yaml",
    )
  }
  part {
    filename     = "bastion-init.sh"
    content_type = "text/x-shellscript"
    content      = local.bastion-tpl-rendered
  }
}

