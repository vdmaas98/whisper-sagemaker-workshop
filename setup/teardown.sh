#!/usr/bin/env bash
# Delete everything the workshop created. Run this AFTER the session.
#
#   bash setup/teardown.sh
#
# Endpoints bill by the second until deleted, so this matters. It sweeps every
# region we use, then removes the IAM users, group, policy and role.

set -uo pipefail

ROLE=WorkshopSageMakerExecutionRole
POLICY=WorkshopSageMakerParticipant
GROUP=sagemaker-workshop
COUNT=${COUNT:-5}
REGIONS=(eu-north-1 eu-west-1 eu-central-1 eu-west-2 eu-west-3)
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)

echo "=== 1. deleting SageMaker endpoints (this is the part that costs money) ==="
for R in "${REGIONS[@]}"; do
  for E in $(aws sagemaker list-endpoints --region "$R" --query 'Endpoints[].EndpointName' --output text 2>/dev/null); do
    echo "  $R: deleting endpoint $E"
    aws sagemaker delete-endpoint --endpoint-name "$E" --region "$R" 2>/dev/null
  done
  for C in $(aws sagemaker list-endpoint-configs --region "$R" --query 'EndpointConfigs[].EndpointConfigName' --output text 2>/dev/null); do
    aws sagemaker delete-endpoint-config --endpoint-config-name "$C" --region "$R" 2>/dev/null
  done
  for M in $(aws sagemaker list-models --region "$R" --query 'Models[].ModelName' --output text 2>/dev/null); do
    aws sagemaker delete-model --model-name "$M" --region "$R" 2>/dev/null
  done
done

echo "=== 2. deleting IAM users ==="
for i in $(seq 1 "$COUNT"); do
  U="workshop${i}"
  aws iam get-user --user-name "$U" >/dev/null 2>&1 || continue
  for K in $(aws iam list-access-keys --user-name "$U" --query 'AccessKeyMetadata[].AccessKeyId' --output text 2>/dev/null); do
    aws iam delete-access-key --user-name "$U" --access-key-id "$K"
  done
  aws iam remove-user-from-group --user-name "$U" --group-name "$GROUP" 2>/dev/null
  aws iam delete-user --user-name "$U" && echo "  deleted $U"
done

echo "=== 3. group, policy, role ==="
POLICY_ARN="arn:aws:iam::${ACCOUNT}:policy/${POLICY}"
aws iam detach-group-policy --group-name "$GROUP" --policy-arn "$POLICY_ARN" 2>/dev/null
aws iam delete-group --group-name "$GROUP" 2>/dev/null && echo "  deleted group"
aws iam delete-policy --policy-arn "$POLICY_ARN" 2>/dev/null && echo "  deleted policy"
aws iam detach-role-policy --role-name "$ROLE" \
  --policy-arn arn:aws:iam::aws:policy/AmazonSageMakerFullAccess 2>/dev/null
aws iam delete-role --role-name "$ROLE" 2>/dev/null && echo "  deleted role"

rm -f "$(cd "$(dirname "$0")/.." && pwd)/credentials-OUT.txt"

echo
echo "done. verify nothing is still running:"
for R in "${REGIONS[@]}"; do
  N=$(aws sagemaker list-endpoints --region "$R" --query 'length(Endpoints)' --output text 2>/dev/null)
  echo "  $R endpoints remaining: ${N:-0}"
done
