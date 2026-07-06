## [Unreleased]

### Fixed

- Terraform: migrated deprecated `aws_launch_configuration`, `template_file`/`template_cloudinit_config`, `map()`, and `aws_subnet_ids` usages to their current equivalents (`aws_launch_template`, `templatefile()`+`hashicorp/cloudinit`, `tomap()`, `aws_subnets`); pinned provider versions; made `role_arn` optional throughout for same-account deploys.
- Terraform: added a scoped NAT Gateway + dedicated route table for the private "Data" subnets, which previously had no outbound path to AWS APIs.
- `terraform.sh`: fixed whitespace corruption of credentials parsed from `~/.aws/credentials`, and stopped exporting an empty `AWS_SESSION_TOKEN` (the AWS SDK treats a present-but-empty session token as invalid and fails STS `AssumeRole`, breaking cross-account backend/remote-state config).
- Packer/bootstrap scripts: added IMDSv2 token headers to all EC2 metadata `curl` calls (required now that `HttpTokens=required` is enforced), fixed `/etc/cassandra` vs `/etc/cassandra/conf` path bugs, and rewrote `enable_eth1.sh` to support Amazon Linux 2023's `amazon-ec2-net-utils` networking (predictable `ensN` interface naming) alongside the legacy AL2/RHEL `ifup`/`ifdown` path.
- `bake-ami.sh`: tightened the base AL2023 AMI lookup filter (was matching the `ecs-neuron-hvm` specialty variant instead of the plain base image).
- `cas_ebs_mgr.py`: added support for `gp3` EBS volumes (previously only `gp2`/`io1` were handled, causing a crash on `gp3`).
- IAM: added the missing `ssm:GetParameter` (singular) action needed by `bootstrap.sh`'s keystore/truststore password retrieval.
- Cassandra AMI bake: switched Java installation to Zulu (`java_use_zulu: true` in `bake-cassandra.yml`, with `cassandra_version` passed through so the `axonops.axonops.java` role selects Zulu 8) — the prior `java-1.8.0-openjdk-headless` package name doesn't resolve on AL2023, silently leaving Java 17 as the system default and crashing Cassandra 3.11 (`ThreadPriorityPolicy=42` rejected by JDK17's stricter flag validation).
- `cassandra-3.11.19-1.yaml` template: removed five Cassandra 4.x-only config keys (`allocate_tokens_for_local_replication_factor`, `aggregated_request_timeout_in_ms`, `native_transport_keepalive`, `concurrent_materialized_view_builders`, `native_transport_address`) that Cassandra 3.11.19 rejects at startup.

### Removed

- Removed DataStax OpsCenter support and DataStax Enterprise (DSE); repo now provisions Apache Cassandra 3.11.x clusters.

# v1.0.0 (Thu Jun 18 2020)

#### Initial Revision

- [1.0.0](https://github.com/intuit/dse-pronto/releases/tag/1.0.0): added changelog + other docs

#### Authors: @bencovi
