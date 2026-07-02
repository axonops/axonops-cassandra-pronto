#!/usr/bin/env bash
#
# bake-ami.sh - Packer wrapper to bake Cassandra AMIs on AWS.
#
# Usage:
#   bake-ami.sh -a <account_name> -v <vpc_name> -t cassandra [-i <base_ami_id>]
#
# Options:
#   -a  [Required] account name (matches configurations/<account_name>/)
#   -v  [Required] vpc name (matches configurations/<account_name>/<vpc_name>/)
#   -t  [Required] ami type -> cassandra
#   -i  base AMI id to build from (default: auto-discovered from
#       PACKER_BASE_AMI_ID in variables.yaml, or latest Amazon Linux 2 AMI)
#
# Dependencies: bash, packer, aws-cli, curl, git, python3 (for portable relpath)
#
# Exit codes: 0 success, 1 general/config/AWS error, 2 usage error.

set -uo pipefail
# NOTE: set -e is intentionally NOT enabled globally. Several pipelines below
# (parse/get_tfvar grep, security-group IP grep) legitimately return nonzero
# when a value is absent -- that is expected control flow, not a fault. Every
# command whose failure IS fatal is checked explicitly with `if ! cmd; then`.

ROOT=$(git rev-parse --show-toplevel) || { echo "ERROR: not inside a git repository" >&2; exit 1; }
CORE="$ROOT/core-components"
CONFIGS="$ROOT/configurations"

# Portable replacement for `realpath --relative-to`, which is GNU-only and
# absent on stock macOS (BSD realpath has no --relative-to flag at all, and
# the previous `grealpath` shim only worked if Homebrew coreutils was
# installed). Requires python3, already a toolchain dependency.
relpath() {
  local target="$1" base="${2:-$PWD}"
  python3 - "${target}" "${base}" <<'PY'
import os, sys
print(os.path.relpath(sys.argv[1], sys.argv[2]))
PY
}

# Extract a value from the account's variables.yaml (empty if absent -- callers
# that require the value must check for emptiness themselves, e.g. noconfig()).
parse() {
  grep "^$1" "${INPUT_VAR_FILE}" 2>/dev/null | awk '{print $NF}' | tr -d '"' || true
}

# Extract a value from a terraform .tfvars file (empty if absent).
get_tfvar() {
  grep "^${1}" "${terraform_var_file}" 2>/dev/null | tr -d '" ' | awk -F'=' '{print $NF}' || true
}

# Print a standard "missing required config key" error and exit.
noconfig() {
  echo "ERROR: No '${1}' found in:  ${INPUT_VAR_FILE}" >&2
  echo "  -> This is required when baking ${ami_type} AMIs!" >&2
  usage; exit 1
}

usage() {
  echo "Usage:"
  echo "  bake-ami.sh"
  echo "    -a : [Required] account name"
  echo "    -v : [Required] vpc name"
  echo "    -t : [Required] ami type -> cassandra"
  echo "    -i : base ami_id"
}

while getopts ":i:t:a:v:" opt; do
  case "${opt}" in
    i) BASE_AMI_ID=${OPTARG} ;;
    a) account_name=${OPTARG} ;;
    v) vpc_name=${OPTARG} ;;
    t) ami_type=${OPTARG} ;;
    *) usage; exit 2 ;;
  esac
done

if [[ -z "${ami_type// }" ]]; then usage; exit 2; fi
if [[ -z "${account_name// }" ]]; then usage; exit 2; fi
if [[ -z "${vpc_name// }" ]]; then usage; exit 2; fi

INPUT_VAR_FILE="${CONFIGS}/${account_name}/variables.yaml"

if ! command -v packer > /dev/null 2>&1; then
  echo "ERROR: packer is required but not found in PATH." >&2
  exit 1
fi

if ! command -v python3 > /dev/null 2>&1; then
  echo "ERROR: python3 is required (used for portable relative-path resolution)." >&2
  exit 1
fi

MY_IP=$(curl -4 -s --max-time 5 --connect-timeout 3 ifconfig.co || true)
count=0
while [[ ! ${MY_IP} =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; do
  if [[ ${count} -lt 20 ]]; then
    echo "Error fetching external IP address; trying again."
    sleep 1
    MY_IP=$(curl -4 -s --max-time 5 --connect-timeout 3 ifconfig.co || true)
    ((count++))
  else
    echo "ERROR: Could not determine external IP address after ${count} attempts." >&2
    exit 1
  fi
done

################################
# Gather and verify input parameters
################################

# cluster specific vars
terraform_var_file="${CONFIGS}/${account_name}/${vpc_name}/vpc-resources/vpc.tfvars"
PROFILE="$(parse PACKER_AWS_PROFILE)"
REGION="$(parse PACKER_AWS_REGION)"
VPC_REGION="$(get_tfvar region)"
if [[ -z ${VPC_REGION} ]]; then
  VPC_REGION=${REGION}
fi
AWS_CMD=(aws --profile "${PROFILE}" --region "${REGION}")

VPC_ID="$(parse PACKER_VPC_ID)"
SUBNET_ID="$(parse PACKER_SUBNET_ID)"
BU="$(parse PACKER_BU)"
ENV="$(parse PACKER_ENVIRONMENT)"

# configured artifact versions
CASSANDRA_VER="$(parse PACKER_CASSANDRA_FULL_VER)"

# make sure pkg versions are specified as needed
if [[ "${ami_type}" == "cassandra" ]]; then
  if [[ -z "${CASSANDRA_VER// }" ]]; then noconfig "PACKER_CASSANDRA_FULL_VER"; fi

  # make sure packer-resources are filled in
  if grep -rq "<<<.*>>>" "${CONFIGS}/${account_name}/packer-resources/cassandra"; then
    echo "Please fill out the variables in your packer-resources dir:"
    echo "  grep -r \"<<<.*>>>\" $(relpath "${CONFIGS}/${account_name}/packer-resources/cassandra" .)"
    exit 1
  fi
fi

################################
# Verify cassandra configs are present
################################

config_path="packer-resources/cassandra/configs/${CASSANDRA_VER}"
cassandra_configs_location="${CONFIGS}/${account_name}/${config_path}"

shopt -s nullglob
cassandra_config_files=("${cassandra_configs_location}"/*.yaml "${cassandra_configs_location}"/*.sh)
shopt -u nullglob

if [[ ! -e "${cassandra_configs_location}" ]] || [[ ${#cassandra_config_files[@]} -eq 0 ]]; then
  echo "WARNING:  No config files (.yaml, .sh) were found at the following location:"
  echo "  DIR: $(relpath "${cassandra_configs_location}" "${ROOT}")"
  echo "Copying from the default config profile!  You should copy your own set of these files for modification."
  echo "  DIR: $(relpath "${CONFIGS}/default-account/${config_path}" "${ROOT}")"
  if [[ ! -e "${CONFIGS}/default-account/${config_path}" ]]; then
    echo "ERROR:  No config files found in the default profile for Cassandra version: ${CASSANDRA_VER}" >&2
    echo "  - Looked in:  ${CONFIGS}/default-account/${config_path}" >&2
    exit 1
  fi
  mkdir -p "${cassandra_configs_location}" || { echo "ERROR: failed to create ${cassandra_configs_location}" >&2; exit 1; }
  cp "${CONFIGS}/default-account/${config_path}"/* "${cassandra_configs_location}/" \
    || { echo "ERROR: failed to copy default config files into ${cassandra_configs_location}" >&2; exit 1; }
fi

# make sure we can find a base AMI to start with
if [[ -z "${BASE_AMI_ID:-}" ]]; then
  echo "Base AMI option (-i) not provided, parsing from $(relpath "${INPUT_VAR_FILE}" .)..."
  BASE_AMI_ID="$(parse PACKER_BASE_AMI_ID)"
fi

if [[ -z "${BASE_AMI_ID:-}" ]]; then
  echo "Base AMI not configured, looking up an appropriate Amazon Linux base AMI..."
  BASE_AMI_ID=$("${AWS_CMD[@]}" ec2 describe-images \
                  --query 'sort_by(Images, &CreationDate)[-1].ImageId' --output text \
                  --filters "Name=owner-alias,Values=amazon" "Name=is-public,Values=true" "Name=state,Values=available" \
                            "Name=name,Values=amzn2-ami-hvm-2.0*x86_64-gp2")
fi

if [[ -z "${BASE_AMI_ID:-}" || "${BASE_AMI_ID}" == "None" ]]; then
  echo "ERROR: No base AMI ID found!" >&2
  exit 1
fi

# get the ami_name from specified ami_id
BASE_AMI_NAME=$("${AWS_CMD[@]}" ec2 describe-images --image-ids "${BASE_AMI_ID}" --query 'Images[0].Name' --output text)
if [[ -z "${BASE_AMI_NAME}" || "${BASE_AMI_NAME}" == "None" ]]; then
  echo "ERROR: Could not resolve AMI name for BASE_AMI_ID=${BASE_AMI_ID} (does it exist in region ${REGION}?)" >&2
  exit 1
fi

echo ""
echo "AWS profile:       ${PROFILE}"
echo "Local IP address:  ${MY_IP}"
echo "VPC ID:            ${VPC_ID}"
echo "Cassandra version: ${CASSANDRA_VER}"
echo "Base AMI:          ${BASE_AMI_NAME}"
echo "Base AMI ID:       ${BASE_AMI_ID}"
echo ""

################################
# Check credentials before starting
################################

if ! "${AWS_CMD[@]}" sts get-caller-identity > /dev/null 2>&1; then
  echo "ERROR: Local AWS credentials are not valid (profile: ${PROFILE})" >&2
  exit 1
fi

pushd "${CORE}/packer" > /dev/null || { echo "ERROR: cannot cd into ${CORE}/packer" >&2; exit 1; }

################################
# Create a security group allowing Packer into the provisioned instance from this IP
################################

PACKER_SG_NAME="packer-ssh-ingress"

GROUP_ID=$("${AWS_CMD[@]}" ec2 describe-security-groups \
  --filters "Name=group-name,Values=${PACKER_SG_NAME}" "Name=vpc-id,Values=${VPC_ID}" \
  --query 'SecurityGroups[0].GroupId' --output text)

if [[ "${GROUP_ID}" == "None" ]]; then
  echo "Creating new SecurityGroup"
  GROUP_ID=$("${AWS_CMD[@]}" ec2 create-security-group \
    --description "Allows SSH ingress for Packer" --group-name "${PACKER_SG_NAME}" --vpc-id "${VPC_ID}" \
    --query 'GroupId' --output text)
fi

IP_EXIST=$("${AWS_CMD[@]}" ec2 describe-security-groups \
  --group-ids "${GROUP_ID}" --query 'SecurityGroups[].IpPermissions[].IpRanges[]' \
  --output text | { grep "${MY_IP}/32" || true; } | wc -l | tr -d "[:space:]")

if [[ "${IP_EXIST}" == 0 ]]; then
  "${AWS_CMD[@]}" ec2 authorize-security-group-ingress \
    --group-id "${GROUP_ID}" --protocol tcp --port 22 --cidr "${MY_IP}/32"
fi

################################
# Create an IAM role for the Packer builder node
################################

PACKER_ROLE_NAME="packer-builder-role"
if ! "${AWS_CMD[@]}" iam get-role --role-name "${PACKER_ROLE_NAME}" > /dev/null 2>&1; then
  echo "Creating IAM role for Packer builder..."
  ./init-packer-instance-profile.sh -p "${PROFILE}" -r "${REGION}" -n "${PACKER_ROLE_NAME}"
fi

################################
# Determine AMI type
################################

pushd "${ami_type}" > /dev/null || { echo "ERROR: cannot cd into ${ami_type}" >&2; popd > /dev/null || true; exit 1; }

echo "Building AMI: ${ami_type}"

case "${ami_type}" in
  "cassandra")
    PACKER_FILE="cassandra-ami.json" ;;
  *)
    usage; exit 2 ;;
esac

################################
# Invoke Packer
################################

AWS_REGION="${REGION}" \
  AWS_PROFILE="${PROFILE}" \
  VPC_REGION="${VPC_REGION}" \
  PACKER_VPC_ID="${VPC_ID}" \
  PACKER_SUBNET_ID="${SUBNET_ID}" \
  PACKER_SG_ID="${GROUP_ID}" \
  PACKER_CASSANDRA_VER="${CASSANDRA_VER}" \
  PACKER_ROLE="${PACKER_ROLE_NAME}" \
  BASE_AMI_ID="${BASE_AMI_ID}" \
  BASE_AMI_NAME="${BASE_AMI_NAME}" \
  PACKER_ENVIRONMENT="${ENV}" \
  PACKER_BU="${BU}" \
  PACKER_CONFIG_PATH="${CONFIGS}/${account_name}/packer-resources" \
    packer build "${PACKER_FILE}"
packer_status=$?

popd > /dev/null || true
popd > /dev/null || true

exit "${packer_status}"
