# Pending Decisions

Tracks deferred architectural decisions — things identified as improvements but
intentionally not actioned, with the reasoning so we don't re-litigate them
without cause.

## Cassandra config templating: envsubst+vals vs. reusing the ansible collection

**Status:** partially implemented — envsubst done, `vals` still pending.

**Context:** `configurations/{default-account,axonops}/packer-resources/cassandra/configs/3.11.19-1/cassandra-3.11.19-1.yaml`
is a hand-maintained copy of `cassandra.yaml`, tokenized with `${VAR}`
(envsubst syntax, converted from the old `##PLACEHOLDER##` style). It's baked
into the AMI as `/opt/cassandra/scripts/cassandra.yaml.tmpl`
(`core-components/packer/cassandra/cassandra-ami.json`) and rendered at boot
by `bootstrap.sh:update_cassandra_config()` via a whitelisted `envsubst` call,
replacing the RPM-shipped default `/etc/cassandra/conf/cassandra.yaml`.
Ansible was explicitly ruled out for boot-time rendering (no Ansible install
on customer production nodes — security/footprint concern), so the
"reuse the ansible collection at boot" alternative below is dead; envsubst is
the chosen mechanism.

**Why envsubst was safe here (unlike the `.j2` alternative considered
earlier):** this repo's hand-rolled yaml has no Jinja2 control flow — just
flat `${VAR}` substitutions — so plain `envsubst` handles it correctly. The
`axonops-ansible-collection` template (`roles/cassandra/templates/3.11.x/cassandra.yaml.j2`)
still has live `{% if %}`/`{% else %}` blocks and remains unsuitable for
envsubst; that idea stays shelved.

**Still pending: `vals`.** `bootstrap.sh` currently passes `keystore_pass` /
`truststore_pass` (fetched via `aws ssm get-parameter --with-decryption`) into
`envsubst` as plain exported shell vars — no `vals` involved yet, and they're
exposed in `set -x` trace output like the sed commands they replaced (a
pre-existing exposure, not a regression). Revisit: pull these through `vals`
(`ref+awsssm://...`) instead of raw `aws ssm` + shell export, and disable
`set -x` around the secret-bearing lines either way.

**Revisit when:** picking up the `vals` integration for secret resolution.

## `sg_ops_nodes_to_cas` stubbed out (no ops-access security group)

**Status:** deferred, not scheduled.

**Context:** `core-components/terraform/modules/vpc-shared` was called from
`layers/vpc-resources/main.tf` and expected to produce an
`sg_ops_nodes_to_cas` security group ID (consumed by
`layers/cluster-resources/main.tf` and threaded into the cassandra module's
`enis.tf`/`instances.tf` security group lists, alongside the bastion SG). The
module only ever had `_variables.tf` (`vpc_id`, `region`, `account_id`) and an
empty `_outputs.tf` — no security group resource was ever implemented.

**What's in place now:** `vpc-shared/_outputs.tf` outputs
`sg_ops_nodes_to_cas = ""`, and the cassandra module's security group lists
use `compact([...])` so the empty value is dropped rather than passed to AWS
as an invalid security group ID. Functionally, no "ops nodes" ingress path
into Cassandra exists today beyond the bastion SG and the client/internode
SGs.

**Why deferred:** implementing the real security group requires a design
decision this repo doesn't have an answer for yet — what should count as an
"ops node" (a specific CIDR range, an existing monitoring/jump-host SG, a VPN
range?) and which ports it should reach on Cassandra. Guessing this wrong
means silently opening or missing access to a database security group.

**Revisit when:** there's a concrete definition of what "ops nodes" means for
this deployment (e.g. a monitoring host SG, VPN CIDR) — then implement the
resource in `modules/vpc-shared`, restore its real output, and drop the
`compact()` workaround in the cassandra module.
