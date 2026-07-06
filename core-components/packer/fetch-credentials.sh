#!/bin/bash

if ! type jq; then
  sudo yum install -y jq
fi

# IMDSv2 is enforced (HttpTokens=required) - metadata requests must carry a session token
IMDS_TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
REGION=$(curl -s -H "X-aws-ec2-metadata-token: ${IMDS_TOKEN}" http://169.254.169.254/latest/meta-data/placement/availability-zone/ | sed 's/[a-z]$//')
PROFILE=$(curl -s -H "X-aws-ec2-metadata-token: ${IMDS_TOKEN}" http://169.254.169.254/latest/meta-data/iam/security-credentials/)
CREDS=$(curl -s -H "X-aws-ec2-metadata-token: ${IMDS_TOKEN}" http://169.254.169.254/latest/meta-data/iam/security-credentials/${PROFILE})

ACCESS_KEY=$(echo ${CREDS} | jq -r '.AccessKeyId')
SECRET_KEY=$(echo ${CREDS} | jq -r '.SecretAccessKey')
TOKEN=$(echo ${CREDS} | jq -r '.Token')

AWS_DIR="/home/ec2-user/.aws"
mkdir -p ${AWS_DIR}

cat > ${AWS_DIR}/credentials << EOM
[default]
aws_access_key_id=${ACCESS_KEY}
aws_secret_access_key=${SECRET_KEY}
aws_session_token=${TOKEN}
EOM

cat > ${AWS_DIR}/config << EOM
[default]
region=${REGION}
output=json
EOM
