<p align="center">
  <a href="https://axonops.com">
    <img src="https://digitalis-marketplace-assets.s3.us-east-1.amazonaws.com/axonops-small-logo.png" alt="AxonOps" width="300">
  </a>
</p>

<p align="center">
  <em>Built and maintained by <a href="https://axonops.com">AxonOps</a></em>
</p>

> [!WARNING]
> ## IN DEVELOPMENT — DO NOT USE IN PRODUCTION
> This repository is currently under active development and should be considered unstable.
> Interfaces, behavior, configuration, and supporting components may change without notice.

## About this fork

This repository is a fork of the original [Intuit dse-pronto](https://github.com/intuit/dse-pronto).

The original project appears to have been inactive for some time, so this fork is intended as a respectful continuation for users who still find the project valuable and want to keep it usable in current environments.

The goals of this fork are to:
- update and maintain the project for modern usage,
- improve compatibility where needed, and
- add support for managing clusters with **AxonOps**.

This work builds on the original foundation created by the Intuit team, and credit for that foundation belongs to them.

# Cassandra Pronto

An automation suite for deploying and managing [Apache Cassandra](https://cassandra.apache.org/doc/latest/)
clusters in AWS.

[![pronto](./docs/images/pronto-logo.png)](https://github.intuit.com/pages/open-source/logo-generator/)

This repository collects Intuit's Cassandra automation.  We've taken all of our learning for managing Cassandra in AWS and
condensed it into a single package for others to leverage.  It uses standard tools
([Packer](https://packer.io/docs/index.html), [Terraform](https://www.terraform.io/docs/index.html), and
[Ansible](https://docs.ansible.com/ansible/latest/index.html)) and can be run from a laptop.  That said, we have a hard
preference for automated deployments using a CICD orchestrator along the lines of [Jenkins](https://jenkins.io/),
[CodeBuild](https://aws.amazon.com/codebuild/)/[CodeDeploy](https://aws.amazon.com/codedeploy/),
[Bamboo](https://www.atlassian.com/software/bamboo), [GitLab](https://about.gitlab.com/), or [Spinnaker](https://www.spinnaker.io/).

The tools in this repo can take you from an empty AWS account to a fully-functional Apache Cassandra cluster, but you should have an
understanding of AWS resources, Cassandra cluster management, and at least a passing familiarity with Packer, Terraform,
and Ansible.

**This is not a "managed" Cassandra solution.**  If you need one of those, [AWS has you covered](https://aws.amazon.com/keyspaces/).

On the other hand, if what you're looking for is an open source framework to help you _manage your own_ Apache Cassandra cluster...
then welcome to Cassandra Pronto!

## Notes and Features

* Support for every phase of deployment, from an empty account to production:
  * Baking an AMI
  * Deploying a new VPC
  * Creating account-wide resources (like IAM roles) and VPC-wide resources (like a bastion host for SSH)
  * Launching a cluster
  * Runtime operations
    * Restacking and resizing a cluster
    * Bringing nodes up and down
* Transparent restacking operations, to keep in compliance with latest baseline images
  * Data stored on persistent EBS volumes, static EIP for predictable address, both located (using EC2 tags) and reattached
    during restack
* Apache Cassandra 3.11.x supported (3.11.19)
* Latest Amazon Linux 2023 & Python 3 in use
* [More FAQs and details here](docs/MORE_DETAILS.md)

## Tools Required

* **On MacOS:** `brew install awscli coreutils packer ansible tfenv jq && tfenv install 0.12.24`
  * The scripts in this repo require a minimum of `aws-cli/1.16.280` and `botocore/1.13.16`.  Type `aws --version` to verify.
    * Everything has also been tested with `aws-cli/2.0.0` and associated prerequisites.
  * Some scripts also require Python 3 ([installation](https://docs.python-guide.org/starting/install3/osx/)).
* **In Docker:** the included [Dockerfile](./Dockerfile) will produce a suitable Docker image, including all tools needed.
* Elsewhere:
  * Install Packer: https://www.packer.io/intro/getting-started/install.html
  * Install Terraform (0.12.24): https://www.terraform.io/intro/getting-started/install.html
  * install Ansible: https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html
* **Why Terraform 0.12.24?** Go [here](docs/MORE_DETAILS.md) to find out!

## Key Technical Details

### Java Installation

The Cassandra AMI bake uses **Zulu 8** Java (configured via `java_use_zulu: true` in `bake-cassandra.yml`). This ensures Cassandra 3.11.19 runs on Amazon Linux 2023, which lacks the legacy OpenJDK package names. The `axonops.axonops.java` role handles Zulu selection automatically based on the `cassandra_version` variable.

### Terraform Deployment

Use `core-components/terraform/terraform.sh` to run all three layers sequentially. The `-r` flag for cross-account assumes-role is **optional** — only needed if deploying into a different AWS account than your current credentials.

#### Example: Same-account deployment
```bash
./core-components/terraform/terraform.sh \
  -a <account_name> \
  -v <vpc_name> \
  -c <cluster_name> \
  -l account-resources \
  -t plan \
  -d ~/.aws/credentials \
  -i <account_id> \
  -b <tfstate_bucket> \
  -o <ami_owner_account>
```

#### Example: Cross-account deployment
```bash
./core-components/terraform/terraform.sh \
  -r <assumed_role_name> \
  -a <account_name> \
  -v <vpc_name> \
  -c <cluster_name> \
  -l cluster-resources \
  -t apply \
  -d ~/.aws/credentials \
  -i <account_id> \
  -b <tfstate_bucket> \
  -o <ami_owner_account>
```

Deploy in this order: `account-resources`, then `vpc-resources`, then `cluster-resources`.

### AMI Baking

Bake Cassandra AMIs with:
```bash
./core-components/bake-ami.sh -a <account_name> -v <vpc_name> -t cassandra
```

The script auto-discovers the base Amazon Linux 2023 AMI. To specify a particular base image:
```bash
./core-components/bake-ami.sh -a <account_name> -v <vpc_name> -t cassandra -i ami-xxxxxxxxx
```

### SSM Parameter Store Configuration

Cluster runtime configuration is split between two SSM Parameter Store paths:

#### Non-secret config (plain String parameters)
Path: `/cassandra/<account_name>/<vpc_name>/<cluster_name>/`

Retrieve with: `aws ssm get-parameters-by-path`

Parameters read by bootstrap.sh:
- `axon_agent_server_host` — AxonOps server hostname (defaults to `agents.axonops.cloud` if not set)
- `axon_agent_server_port` — AxonOps server port (defaults to `443` if not set)
- `cassandra_seed_node_ips` — comma-separated seed node IP addresses
- `data_volume_size` — primary data EBS volume size (GB)
- `volume_type` — primary data volume type (`gp3`, `gp2`, `io1`)
- `iops` — primary data IOPS
- `num_tokens` — Cassandra `num_tokens` setting (default: 16)
- `max_heap_size` — JVM heap size (GB)
- Plus additional storage/tuning parameters: `commitlog_*`, `number_of_stripes`, `raid_*`, `native_transport_*`, `aio_enabled`

**Example:** Set the AxonOps self-hosted server (overrides SaaS default)
```bash
aws ssm put-parameter \
  --name "/cassandra/<account>/<vpc>/<cluster>/axon_agent_server_host" \
  --type String \
  --value "axon-server.mycompany.com" \
  --region <region>

aws ssm put-parameter \
  --name "/cassandra/<account>/<vpc>/<cluster>/axon_agent_server_port" \
  --type String \
  --value "9001" \
  --region <region>
```

#### Secret config (base64-encoded SecureString parameters)
Path: `/cassandra/<account_name>/<vpc_name>/<cluster_name>/secrets/`

Retrieve with: `aws ssm get-parameter --with-decryption`

Secrets managed by bootstrap.sh:
- `keystore_pass` — TLS keystore password (base64-encoded)
- `truststore_pass` — TLS truststore password (base64-encoded)
- `axon_agent_org` — AxonOps organization/tenant name (base64-encoded, optional)
- `axon_agent_key` — AxonOps authentication key (base64-encoded, optional)

**Setup:** Use the interactive script:
```bash
./core-components/scripts/secrets/init-secrets.sh \
  -a <account_name> \
  -v <vpc_name> \
  -c <cluster_name>
```

This prompts for keystore, truststore, and cassandra DB user passwords, base64-encodes them, and stores them as SecureString parameters.

**Manual setup (for AxonOps agent credentials):**
```bash
# Encode the value to base64
ENCODED_ORG=$(echo -n "your-org-name" | base64)

aws ssm put-parameter \
  --name "/cassandra/<account>/<vpc>/<cluster>/secrets/axon_agent_org" \
  --type SecureString \
  --value "$ENCODED_ORG" \
  --region <region>
```

**Important:** If `axon_agent_org` and `axon_agent_key` are not set in SSM, the agent is installed but not configured. Nodes will contact the AxonOps SaaS server (`agents.axonops.cloud:443`) by default.

### SSH Access

Nodes are accessed via a bastion host using ProxyJump. The ansible SSH key is at `~/.ssh/ansible_id_rsa`.

Generate the key (one-time):
```bash
./core-components/scripts/ssh/init-ansible-key.sh \
  -a <account_name> \
  -v <vpc_name> \
  -c <cluster_name>
```

SSH into a node (via bastion):
```bash
ssh -J ansible@<bastion-public-ip> ansible@<node-private-ip>
```

### VPC Modes and NAT

This repo supports both managed and existing VPCs:
- **Managed VPC** (`TERRAFORM_MANAGED_VPC=true`): Creates VPC, subnets, and a NAT Gateway for private "Data" subnets to reach AWS APIs and package repositories.
- **Existing VPC** (`TERRAFORM_MANAGED_VPC=false`): Uses an existing VPC; still creates a NAT Gateway if the Data subnets are private.

### Cluster Health Verification

After deployment, verify cluster health via SSH:
```bash
ssh -J ansible@<bastion> ansible@<node-private-ip>
sudo nodetool status
```

All nodes should show `UN` (Up, Normal):
```
UN  10.0.1.100  100.0 GB  256     33.3%  uuid-1
UN  10.0.2.101  100.0 GB  256     33.3%  uuid-2
UN  10.0.3.102  100.0 GB  256     33.3%  uuid-3
```

## 1. Initial Setup

There's a bunch of **one-time** setup you'll need to do before you start baking AMIs or deploying clusters.

Please follow [all of the steps here](docs/1.INITIAL_SETUP.md) before proceeding.

## 2. Baking AMIs

Instructions for baking AWS images with Packer are [here](docs/2.PACKER.md).

## 3. Deploying

Instructions for deploying AWS resources with Terraform are [here](docs/3.TERRAFORM.md).

## 4. Runtime Operations

Instructions for running playbooks with Ansible are [here](docs/4.ANSIBLE.md).

## 5. Debugging

If you're having trouble getting anything to work, go [here](docs/MORE_DETAILS.md) for tips on debugging!

## 6. Cleaning Up

Instructions for deleting everything deployed by this repo are [here](docs/CLEANUP.md).

## Support

This project is maintained by [AxonOps](https://axonops.com). For support, visit [axonops.com/contact](https://axonops.com/contact).

### Links

* [Contributing](.github/CONTRIBUTING.md)
* [License](LICENSE)

---
Copyright 2020 Intuit Inc.
