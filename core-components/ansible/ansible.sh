#!/bin/bash
set -e

ROOT=$(git rev-parse --show-toplevel)
CONFIGS="$ROOT/configurations"

usage() {
  echo "Usage: $0 -o <operation> -p <aws_profile> -r <region> -b <tfstate_bucket> -a <account_name> -v <vpc_name> -c <cluster_name> -i <account_id> -n <role_name> [-h <host_ip>]"
}

while getopts ":o:p:r:b:a:v:c:i:n:h:" opt; do
  case "${opt}" in
    o)
      OPERATION=${OPTARG};;
    p)
      PROFILE=${OPTARG};;
    r)
      REGION=${OPTARG};;
    b)
      BUCKET=${OPTARG};;
    c)
      CLUSTER_NAME=${OPTARG};;
    v)
      VPC_NAME=${OPTARG};;
    a)
      ACCOUNT_NAME=${OPTARG};;
    i)
      ACCOUNT_ID=${OPTARG};;
    n)
      ROLE_NAME=${OPTARG};;
    h)
      HOST_IP=${OPTARG};;
    *)
      usage; exit 1;;
  esac
done
shift "$((OPTIND-1))"

if [[ -z "${OPERATION// }" ]]; then usage; exit 1; fi
if [[ -z "${PROFILE// }" ]]; then usage; exit 1; fi
if [[ -z "${REGION// }" ]]; then usage; exit 1; fi
if [[ -z "${BUCKET// }" ]]; then usage; exit 1; fi
if [[ -z "${CLUSTER_NAME// }" ]]; then usage; exit 1; fi
if [[ -z "${VPC_NAME// }" ]]; then usage; exit 1; fi
if [[ -z "${ACCOUNT_NAME// }" ]]; then usage; exit 1; fi
if [[ -z "${ACCOUNT_ID// }" ]]; then usage; exit 1; fi
if [[ -z "${HOST_IP// }" ]]; then HOST_IP="all"; fi

if [[ -z "${ROLE_NAME// }" ]]; then
  if [[ "${OPERATION}" = "restack" ]]; then
    echo "The 'role_name' parameter (-n option) is required for the 'restack' operation. It will be used to remotely terminate the old node."
    usage
    exit 1
  fi
fi

HOST_FILE="./hosts"
SSH_ARGS="-F ./ssh_config"

function parse_ssm_param()
{
  echo "${1}" | jq -r '."'${2}'"'
}

function get_inputs()
{
  # variables to fetch from ssm parameter store (max 10)
  param_key_prefix="/cassandra/${ACCOUNT_NAME}/${VPC_NAME}/${CLUSTER_NAME}"
  declare -a param_keys=(
      "${param_key_prefix}/dc_name"
      "${param_key_prefix}/cassandra_seed_node_ips"
      "${param_key_prefix}/cassandra_non_seed_node_ips"
      "${param_key_prefix}/keyspace"
      "${param_key_prefix}/availability_zones"
  )

  # get them all at once, convert to key:value map
  param_values=$(aws ssm get-parameters --names ${param_keys[@]} --output json --profile ${PROFILE} --region ${REGION} | jq '.Parameters|map({(.Name):.Value})|add')

  # cluster info
  datacenter=$(        parse_ssm_param "${param_values}" "${param_key_prefix}/dc_name")
  seed_list=$(         parse_ssm_param "${param_values}" "${param_key_prefix}/cassandra_seed_node_ips")
  non_seed_list=$(     parse_ssm_param "${param_values}" "${param_key_prefix}/cassandra_non_seed_node_ips")
  key_space=$(         parse_ssm_param "${param_values}" "${param_key_prefix}/keyspace")
  num_azs=$(           parse_ssm_param "${param_values}" "${param_key_prefix}/availability_zones" | awk -F, '{print NF}')

  # non_seed_list may be empty (no non-seeds exist, "null" exported to SSM from terraform)
  if [[ "${non_seed_list}" = "null" ]]; then non_seed_list=""; fi

  declare -a param_keys=(
      "${param_key_prefix}/commitlog_size"
      "${param_key_prefix}/iops"
      "${param_key_prefix}/data_volume_size"
      "${param_key_prefix}/volume_type"
      "${param_key_prefix}/number_of_stripes"
      "${param_key_prefix}/raid_level"
      "${param_key_prefix}/raid_block_size"
  )

  # get them all at once, convert to key:value map
  param_values=$(aws ssm get-parameters --names ${param_keys[@]} --output json --profile ${PROFILE} --region ${REGION} | jq '.Parameters|map({(.Name):.Value})|add')

  # volume info
  commitlog_size=$(    parse_ssm_param "${param_values}" "${param_key_prefix}/commitlog_size")
  iops=$(              parse_ssm_param "${param_values}" "${param_key_prefix}/iops")
  data_volume_size=$(  parse_ssm_param "${param_values}" "${param_key_prefix}/data_volume_size")
  volume_type=$(       parse_ssm_param "${param_values}" "${param_key_prefix}/volume_type")
  number_of_stripes=$( parse_ssm_param "${param_values}" "${param_key_prefix}/number_of_stripes")
  raid_level=$(        parse_ssm_param "${param_values}" "${param_key_prefix}/raid_level")
  raid_block_size=$(   parse_ssm_param "${param_values}" "${param_key_prefix}/raid_block_size")
}

function prep_cassandra_action() {
  # Generate ansible host inventory
  ./scripts/refresh_inventory.py -f ${HOST_FILE} -r ${REGION} -p ${PROFILE} -a ${ACCOUNT_ID} -c ${CLUSTER_NAME}
  export ANSIBLE_HOST_KEY_CHECKING=false
}

get_inputs

case ${OPERATION} in
  "mount")
    prep_cassandra_action
    time ansible-playbook \
      -b -i ${HOST_FILE} -T 600 --ssh-common-args="${SSH_ARGS}" \
      -e "volume_size=${data_volume_size} stripes=${number_of_stripes} block_size=${raid_block_size} raid_level=${raid_level} \
      host_list=${HOST_IP}" \
      ./playbooks/cluster-mount-volumes.yml
  ;;

  "unmount")
    prep_cassandra_action
    time ansible-playbook \
      -b -i ${HOST_FILE} -T 600 --ssh-common-args="${SSH_ARGS}" -e "host_list=${HOST_IP}" \
      ./playbooks/cluster-unmount-volumes.yml
  ;;

  "start")
    prep_cassandra_action
    time ansible-playbook \
      -b -i ${HOST_FILE} -T 600 --ssh-common-args="${SSH_ARGS}" -e "host_list=${HOST_IP}" \
      ./playbooks/cluster-start.yml
  ;;

  "stop")
    prep_cassandra_action
    time ansible-playbook \
      -b -i ${HOST_FILE} -T 600 --ssh-common-args="${SSH_ARGS}" -e "host_list=${HOST_IP}" \
      ./playbooks/cluster-stop.yml
  ;;

  "restart")
    prep_cassandra_action
    time ansible-playbook \
      -b -i ${HOST_FILE} -T 600 --ssh-common-args="${SSH_ARGS}" -e "host_list=${HOST_IP}" \
      ./playbooks/cluster-restart.yml \
      
  ;;

  "restack")
    prep_cassandra_action
    time ansible-playbook ./playbooks/cluster-restack.yml \
      -i ${HOST_FILE} -T 600 --ssh-common-args="${SSH_ARGS}" \
      -e "account=${ACCOUNT_ID} role_name=${ROLE_NAME} region=${REGION} cluster=${CLUSTER_NAME} host_list=${HOST_IP}"
  ;;

  "init")
     first_seed=$(echo ${seed_list} | awk -F "," '{print $1}')
     secret_location="/cassandra/${ACCOUNT_NAME}/${VPC_NAME}/${CLUSTER_NAME}/secrets"
     prep_cassandra_action
     time ansible-playbook ./playbooks/cluster-init.yml \
       -i ./hosts -l ${first_seed} -T 600 --ssh-common-args="${SSH_ARGS}" \
       -e "secrets_ssm_location=${secret_location} region=${REGION}"
  ;;

  *)
    echo "Operation '${OPERATION}' not recognized!"
    exit 0
  ;;
esac
