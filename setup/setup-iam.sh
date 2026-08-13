#!/usr/bin/env bash
# One-time IAM setup for the workshop. Run this ONCE, as the account owner.
#
#   bash setup/setup-iam.sh
#
# Creates:
#   role   WorkshopSageMakerExecutionRole   - the role SageMaker endpoints run as
#   policy WorkshopSageMakerParticipant     - what participants are allowed to do
#   group  sagemaker-workshop               - participants live here
#   users  workshop1 .. workshop5           - one per participant, with access keys
#
# Everything is tagged purpose=whisper-workshop so teardown.sh can find it.
# Credentials are written to ./credentials-OUT.txt which is gitignored. Hand them
# out over something private, not Slack-in-a-public-channel.

set -euo pipefail

ROLE=WorkshopSageMakerExecutionRole
POLICY=WorkshopSageMakerParticipant
GROUP=sagemaker-workshop
COUNT=${COUNT:-5}
OUT="$(cd "$(dirname "$0")/.." && pwd)/credentials-OUT.txt"

ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
echo "account: $ACCOUNT"

# ---------------------------------------------------------------- execution role
if aws iam get-role --role-name "$ROLE" >/dev/null 2>&1; then
  echo "role $ROLE already exists, reusing"
else
  aws iam create-role --role-name "$ROLE" \
    --assume-role-policy-document '{
      "Version":"2012-10-17",
      "Statement":[{"Effect":"Allow","Principal":{"Service":"sagemaker.amazonaws.com"},"Action":"sts:AssumeRole"}]}' \
    --tags Key=purpose,Value=whisper-workshop >/dev/null
  echo "created role $ROLE"
fi
aws iam attach-role-policy --role-name "$ROLE" \
  --policy-arn arn:aws:iam::aws:policy/AmazonSageMakerFullAccess
ROLE_ARN="arn:aws:iam::${ACCOUNT}:role/${ROLE}"

# ---------------------------------------------------------------- participant policy
POLICY_ARN="arn:aws:iam::${ACCOUNT}:policy/${POLICY}"
if aws iam get-policy --policy-arn "$POLICY_ARN" >/dev/null 2>&1; then
  echo "policy $POLICY already exists, reusing"
else
  aws iam create-policy --policy-name "$POLICY" \
    --description "Deploy and invoke a SageMaker endpoint during the workshop" \
    --policy-document "{
      \"Version\":\"2012-10-17\",
      \"Statement\":[
        {\"Sid\":\"Endpoints\",\"Effect\":\"Allow\",\"Action\":[
          \"sagemaker:CreateModel\",\"sagemaker:DeleteModel\",\"sagemaker:DescribeModel\",
          \"sagemaker:CreateEndpointConfig\",\"sagemaker:DeleteEndpointConfig\",\"sagemaker:DescribeEndpointConfig\",
          \"sagemaker:CreateEndpoint\",\"sagemaker:DeleteEndpoint\",\"sagemaker:DescribeEndpoint\",
          \"sagemaker:UpdateEndpoint\",\"sagemaker:InvokeEndpoint\",\"sagemaker:List*\"],
         \"Resource\":\"*\"},
        {\"Sid\":\"PassExecutionRole\",\"Effect\":\"Allow\",\"Action\":\"iam:PassRole\",
         \"Resource\":\"${ROLE_ARN}\",
         \"Condition\":{\"StringEquals\":{\"iam:PassedToService\":\"sagemaker.amazonaws.com\"}}},
        {\"Sid\":\"ReadLogs\",\"Effect\":\"Allow\",\"Action\":[
          \"logs:GetLogEvents\",\"logs:DescribeLogStreams\",\"logs:DescribeLogGroups\"],
         \"Resource\":\"*\"},
        {\"Sid\":\"SeeYourself\",\"Effect\":\"Allow\",\"Action\":[
          \"iam:GetUser\",\"sts:GetCallerIdentity\"],\"Resource\":\"*\"}
      ]}" >/dev/null
  echo "created policy $POLICY"
fi

# ---------------------------------------------------------------- group
aws iam create-group --group-name "$GROUP" >/dev/null 2>&1 || echo "group $GROUP already exists"
aws iam attach-group-policy --group-name "$GROUP" --policy-arn "$POLICY_ARN"

# ---------------------------------------------------------------- users + keys
: > "$OUT"
{
  echo "# Workshop credentials - delete these after the session"
  echo "# execution role: $ROLE_ARN"
  echo
} >> "$OUT"

REGIONS=(eu-north-1 eu-west-1 eu-central-1 eu-west-2 eu-west-3)
for i in $(seq 1 "$COUNT"); do
  U="workshop${i}"
  R="${REGIONS[$((i-1))]}"
  if aws iam get-user --user-name "$U" >/dev/null 2>&1; then
    echo "user $U already exists, skipping key creation"
    continue
  fi
  aws iam create-user --user-name "$U" --tags Key=purpose,Value=whisper-workshop >/dev/null
  aws iam add-user-to-group --user-name "$U" --group-name "$GROUP"
  KEY=$(aws iam create-access-key --user-name "$U" --output json)
  ID=$(echo "$KEY"     | python3 -c 'import sys,json;print(json.load(sys.stdin)["AccessKey"]["AccessKeyId"])')
  SECRET=$(echo "$KEY" | python3 -c 'import sys,json;print(json.load(sys.stdin)["AccessKey"]["SecretAccessKey"])')
  {
    echo "[$U]  region=$R"
    echo "  AWS_ACCESS_KEY_ID=$ID"
    echo "  AWS_SECRET_ACCESS_KEY=$SECRET"
    echo "  AWS_DEFAULT_REGION=$R"
    echo
  } >> "$OUT"
  echo "created $U  ->  $R"
done

echo
echo "execution role ARN : $ROLE_ARN"
echo "credentials written: $OUT   (gitignored - hand out privately)"
echo
echo "Put this in the README so participants can copy it:"
echo "  SAGEMAKER_ROLE_ARN=$ROLE_ARN"
