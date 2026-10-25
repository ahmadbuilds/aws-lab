#!/usr/bin/env bash
# Run from AWS CloudShell, WSL, Linux or Git Bash with configured AWS CLI.
# Writes every section even if an individual AWS CLI command fails.
if [ "$#" -ne 3 ]; then
  echo 'Usage: ./collect-evidence.sh <bucket-name> <ec2-base-url> <lambda-base-url>'
  exit 1
fi
BUCKET="$1"
EC2_URL="${2%/}"
LAMBDA_URL="${3%/}"
ROLL="23l-3104"
EC2_ROLE="cv-ec2-role-23l-3104"
EC2_POLICY="cv-ec2-role-23l-3104Policy"
LAMBDA_POLICY="cv-lambda-s3-read-23l-3104"
LAMBDA_POLICY="cv-lambda-read-23l-3104"
FN="cv-func-23l-3104"
REGION="$(aws configure get region 2>/dev/null || true)"
[ -n "$REGION" ] || REGION="${AWS_DEFAULT_REGION:-${AWS_REGION:-}}"
: > evidence.txt
section() { printf '\n== %s ==\n' "$1" >> evidence.txt; }
run() {
  # Commands are recorded in the result; failures do not abort later sections.
  "$@" >> evidence.txt 2>&1
  code=$?
  [ "$code" -eq 0 ] || printf 'COMMAND_FAILED exit=%d\n' "$code" >> evidence.txt
}
section caller
run aws sts get-caller-identity
section public-access
run aws s3api get-public-access-block --bucket "$BUCKET"
section versioning
run aws s3api get-bucket-versioning --bucket "$BUCKET"
section objects
run aws s3 ls "s3://${BUCKET}/site/" --recursive
section ec2-policy
run aws iam get-role-policy --role-name "$EC2_ROLE" --policy-name "$EC2_POLICY"
section lambda-policy
run aws iam list-attached-role-policies --role-name "$LAMBDA_ROLE"
run aws iam get-role-policy --role-name "$LAMBDA_ROLE" --policy-name "$LAMBDA_POLICY"
INSTANCE_ID=$(aws ec2 describe-instances --filters \
 "Name=tag:Name,Values=cv-ec2-${ROLL}" 'Name=instance-state-name,Values=running' \
 --query 'Reservations[].Instances[].InstanceId' --output text 2>> evidence.txt | awk '{print $1}')
SG_ID=''
if [ -n "$INSTANCE_ID" ]; then
  SG_ID=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[].Instances[].SecurityGroups[].GroupId' --output text 2>> evidence.txt | awk '{print $1}')
fi
section security-group
if [ -n "$SG_ID" ]; then run aws ec2 describe-security-groups --group-ids "$SG_ID"; else echo 'COMMAND_FAILED instance or security group not found' >> evidence.txt; fi
section instance
if [ -n "$INSTANCE_ID" ]; then
  run aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
     --query 'Reservations[].Instances[].{InstanceId:InstanceId,Type:InstanceType,Metadata:MetadataOptions,Profile:IamInstanceProfile,PublicIP:PublicIpAddress,Tags:Tags}'
else
  echo 'COMMAND_FAILED instance not found by Name tag' >> evidence.txt
fi
section endpoints
probe() {
  url="$1"
  printf 'URL: %s\n' "$url" >> evidence.txt
  curl --location --silent --show-error --max-time 15 --output /dev/null \
       --write-out 'HTTP=%{http_code} CONTENT_TYPE=%{content_type}\n' "$url" >> evidence.txt 2>&1
  code=$?
  [ "$code" -eq 0 ] || printf 'COMMAND_FAILED exit=%s\n' "$code" >> evidence.txt
}
probe "${EC2_URL}/"
probe "${EC2_URL}/style.css"
probe "${EC2_URL}/cv.pdf"
probe "${LAMBDA_URL}/"
probe "${LAMBDA_URL}/style.css"
probe "${LAMBDA_URL}/cv.pdf"
probe "${LAMBDA_URL}/anything"
if [ -n "$REGION" ]; then
 probe "https://${BUCKET}.s3.${REGION}.amazonaws.com/site/index.html"
else
 echo 'COMMAND_FAILED could not determine region for S3 direct URL' >> evidence.txt
fi
section lambda-logs
run aws logs tail "/aws/lambda/${FN}" --since 1h --format short
section log-retention
run aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/${FN}" \
 --query 'logGroups[].{Name:logGroupName,Retention:retentionInDays}'
echo DONE
