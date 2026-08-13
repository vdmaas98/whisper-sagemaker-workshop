#!/usr/bin/env bash
# Delete everything the workshop created. Run this AFTER the session.
#
#   bash setup/teardown.sh
#
# Endpoints bill by the second until deleted, so this matters. It sweeps every
# region we use, then removes the IAM users, group, policy and role.
#
# Deliberately NOT silent on the endpoint sweep: an expired token must look like
# a failure, not like "nothing to delete". The whole point of this script is to
# stop the meter, so it verifies at the end and exits non-zero if anything is left.

set -uo pipefail

ROLE=WorkshopSageMakerExecutionRole
POLICY=WorkshopSageMakerParticipant
GROUP=sagemaker-workshop
COUNT=${COUNT:-5}
REGIONS=(eu-central-1 eu-north-1 eu-west-1 eu-west-2 eu-west-3)

# --- fail loudly if we are not authenticated, rather than "deleting" nothing ---
if ! ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>&1); then
  echo "NOT AUTHENTICATED - refusing to run."
  echo "  $ACCOUNT"
  echo "Log in and re-run, or your endpoints keep billing."
  exit 1
fi
echo "account: $ACCOUNT"

echo
echo "=== 1. SageMaker endpoints (this is the part that costs money) ==="
for R in "${REGIONS[@]}"; do
  EPS=$(aws sagemaker list-endpoints --region "$R" --query 'Endpoints[].EndpointName' --output text) || {
    echo "  $R: LIST FAILED - check manually"; continue; }
  if [ -z "$EPS" ]; then echo "  $R: none"; continue; fi
  for E in $EPS; do
    if aws sagemaker delete-endpoint --endpoint-name "$E" --region "$R"; then
      echo "  $R: deleted endpoint $E"
    else
      echo "  $R: FAILED to delete $E  <-- still billing, fix this"
    fi
  done
done

echo
echo "=== 2. endpoint configs + models (free, but tidy) ==="
for R in "${REGIONS[@]}"; do
  for C in $(aws sagemaker list-endpoint-configs --region "$R" --query 'EndpointConfigs[].EndpointConfigName' --output text 2>/dev/null); do
    aws sagemaker delete-endpoint-config --endpoint-config-name "$C" --region "$R" >/dev/null 2>&1 \
      && echo "  $R: config $C"
  done
  for M in $(aws sagemaker list-models --region "$R" --query 'Models[].ModelName' --output text 2>/dev/null); do
    aws sagemaker delete-model --model-name "$M" --region "$R" >/dev/null 2>&1 \
      && echo "  $R: model $M"
  done
done

echo
echo "=== 3. IAM users ==="
for i in $(seq 1 "$COUNT"); do
  U="workshop${i}"
  aws iam get-user --user-name "$U" >/dev/null 2>&1 || continue
  for K in $(aws iam list-access-keys --user-name "$U" --query 'AccessKeyMetadata[].AccessKeyId' --output text 2>/dev/null); do
    aws iam delete-access-key --user-name "$U" --access-key-id "$K"
  done
  aws iam remove-user-from-group --user-name "$U" --group-name "$GROUP" 2>/dev/null
  aws iam delete-user --user-name "$U" && echo "  deleted $U"
done

echo
echo "=== 4. group, policy, role ==="
POLICY_ARN="arn:aws:iam::${ACCOUNT}:policy/${POLICY}"
aws iam detach-group-policy --group-name "$GROUP" --policy-arn "$POLICY_ARN" 2>/dev/null
aws iam delete-group --group-name "$GROUP" 2>/dev/null && echo "  deleted group"
aws iam delete-policy --policy-arn "$POLICY_ARN" 2>/dev/null && echo "  deleted policy"
aws iam detach-role-policy --role-name "$ROLE" \
  --policy-arn arn:aws:iam::aws:policy/AmazonSageMakerFullAccess 2>/dev/null
aws iam delete-role --role-name "$ROLE" 2>/dev/null && echo "  deleted role"

rm -f "${HOME}/whisper-workshop-credentials.txt"

# --- verify. deleting is async, so anything still listed is either mid-delete or stuck ---
echo
echo "=== 5. verification ==="
LEFT=0
for R in "${REGIONS[@]}"; do
  OUT=$(aws sagemaker list-endpoints --region "$R" --query 'Endpoints[].[EndpointName,EndpointStatus]' --output text 2>&1)
  if [ -z "$OUT" ]; then
    echo "  $R: clear"
  else
    echo "  $R: STILL PRESENT ->"; echo "$OUT" | sed 's/^/      /'
    LEFT=1
  fi
done

if [ "$LEFT" -eq 1 ]; then
  echo
  echo "Something is still listed. 'Deleting' status is fine - re-run in a minute."
  echo "Anything else is still costing you money."
  exit 1
fi
echo
echo "All clear. Meter stopped."
