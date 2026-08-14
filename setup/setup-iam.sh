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
# Credentials are written OUTSIDE this repo, to ~/whisper-workshop-credentials.txt
# with 0600 perms. This repo goes to GitHub - nothing secret ever lands in it.
# Hand the keys out over something private, not a public Slack channel.

set -euo pipefail

ROLE=WorkshopSageMakerExecutionRole
POLICY=WorkshopSageMakerParticipant
GROUP=sagemaker-workshop
COUNT=${COUNT:-6}          # eu-central-1 quota is 6 endpoints, so 6 is the ceiling
REGION=${REGION:-eu-central-1}
OUT="${HOME}/whisper-workshop-credentials.txt"

# A secret access key can be read exactly once, at creation. If this script
# truncates OUT and then skips users that already exist, their keys are gone
# for good - you cannot re-read them, only delete and reissue. So refuse to
# clobber an existing file.
if [ -s "$OUT" ] && [ "${FORCE:-0}" != "1" ]; then
  echo "$OUT already exists and is not empty."
  echo "Re-running would wipe it while skipping users that already exist,"
  echo "and their secret keys cannot be recovered."
  echo "To add more people, raise COUNT and run with FORCE=1, or create the"
  echo "user by hand. To start over, run setup/teardown.sh first."
  exit 1
fi

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
          \"iam:GetUser\",\"sts:GetCallerIdentity\"],\"Resource\":\"*\"},
        {\"Sid\":\"SageMakerDefaultBucket\",\"Effect\":\"Allow\",\"Action\":[
          \"s3:CreateBucket\",\"s3:ListBucket\",\"s3:GetBucketLocation\",\"s3:GetBucketCors\",
          \"s3:PutBucketCors\",\"s3:GetObject\",\"s3:PutObject\",\"s3:DeleteObject\",
          \"s3:AbortMultipartUpload\",\"s3:ListBucketMultipartUploads\"],
         \"Resource\":[\"arn:aws:s3:::sagemaker-*\",\"arn:aws:s3:::sagemaker-*/*\"]}
      ]}" >/dev/null
  echo "created policy $POLICY"
fi

# ---------------------------------------------------------------- group
aws iam create-group --group-name "$GROUP" >/dev/null 2>&1 || echo "group $GROUP already exists"
aws iam attach-group-policy --group-name "$GROUP" --policy-arn "$POLICY_ARN"

# ---------------------------------------------------------------- users + keys
: > "$OUT"
chmod 600 "$OUT"
{
  echo "# Workshop credentials - delete these after the session"
  echo "# execution role: $ROLE_ARN"
  echo
} >> "$OUT"

# Quota is NOT uniform. Probed 13 Aug 2026: eu-central-1 = 6 endpoints,
# eu-north-1 = 2, everywhere else 0. So everyone goes to Frankfurt, and COUNT
# must not exceed the endpoint quota there - a participant over the limit gets
# ResourceLimitExceeded, which reads like a broken setup rather than a full one.
for i in $(seq 1 "$COUNT"); do
  U="workshop${i}"
  R="$REGION"
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
    echo "  SAGEMAKER_ROLE_ARN=$ROLE_ARN"
    echo "  AWS_ACCESS_KEY_ID=$ID"
    echo "  AWS_SECRET_ACCESS_KEY=$SECRET"
    echo "  AWS_DEFAULT_REGION=$R"
    echo
  } >> "$OUT"
  echo "created $U  ->  $R"
done

echo
echo "execution role ARN : $ROLE_ARN"
echo "credentials written: $OUT   (0600, outside the repo - hand out privately)"
echo
echo "Put this in the README so participants can copy it:"
echo "  SAGEMAKER_ROLE_ARN=$ROLE_ARN"
