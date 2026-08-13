#!/usr/bin/env bash
# Do I actually have GPU quota? Run this before you rely on anything.
#
#   bash setup/check-gpu-quota.sh
#
# Service Quotas will happily report "1" for an instance type whose real,
# enforced limit is 0. On this account it did exactly that for 49 GPU rows
# across 17 regions - every one of them was actually 0.
#
# So this does not read the quota table. It asks SageMaker to create an
# endpoint and reads what comes back. If it succeeds, quota is real and the
# endpoint is deleted within a second. Nothing else is authoritative.

set -uo pipefail

ROLE_ARN="${SAGEMAKER_ROLE_ARN:-}"
if [ -z "$ROLE_ARN" ]; then
  ACC=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) || {
    echo "not authenticated"; exit 1; }
  ROLE_ARN="arn:aws:iam::${ACC}:role/WorkshopSageMakerExecutionRole"
fi

REGIONS="${REGIONS:-eu-central-1 eu-north-1 eu-west-1 us-east-1}"
INSTANCES="${INSTANCES:-ml.g4dn.xlarge ml.g5.xlarge}"

echo "probing real (enforced) quota - not the quota table"
echo "role: $ROLE_ARN"
echo
printf "%-14s %-18s %s\n" REGION INSTANCE RESULT

FOUND=0
for R in $REGIONS; do
  for I in $INSTANCES; do
    TAG="quotaprobe-$(echo "$I" | tr '.' '-')"
    IMG=$(python3 -c "
from sagemaker import image_uris
print(image_uris.retrieve('huggingface',region='$R',version='4.49',
      base_framework_version='pytorch2.6',py_version='py312',
      instance_type='$I',image_scope='inference'))" 2>/dev/null | tail -1)
    case "$IMG" in
      *.dkr.ecr.*) ;;
      *) printf "%-14s %-18s could not resolve container image\n" "$R" "$I"; continue ;;
    esac

    aws sagemaker create-model --region "$R" --model-name "$TAG" \
      --execution-role-arn "$ROLE_ARN" \
      --primary-container "Image=$IMG,Environment={HF_MODEL_ID=openai/whisper-tiny,HF_TASK=automatic-speech-recognition}" \
      >/dev/null 2>&1 || { printf "%-14s %-18s create-model failed\n" "$R" "$I"; continue; }
    aws sagemaker create-endpoint-config --region "$R" --endpoint-config-name "$TAG" \
      --production-variants "VariantName=v,ModelName=$TAG,InitialInstanceCount=1,InstanceType=$I" \
      >/dev/null 2>&1

    ERR=$(aws sagemaker create-endpoint --region "$R" \
            --endpoint-name "$TAG" --endpoint-config-name "$TAG" 2>&1)
    if echo "$ERR" | grep -q "ResourceLimitExceeded"; then
      LIM=$(echo "$ERR" | sed -n 's/.*limit .* is \([0-9]*\) Instances.*/\1/p')
      printf "%-14s %-18s blocked, real limit %s\n" "$R" "$I" "${LIM:-0}"
    elif echo "$ERR" | grep -qi "EndpointArn"; then
      printf "%-14s %-18s *** QUOTA AVAILABLE *** (deleting probe)\n" "$R" "$I"
      aws sagemaker delete-endpoint --endpoint-name "$TAG" --region "$R" >/dev/null 2>&1
      FOUND=1
    else
      printf "%-14s %-18s %s\n" "$R" "$I" "$(echo "$ERR" | head -1 | cut -c1-60)"
    fi

    aws sagemaker delete-endpoint-config --endpoint-config-name "$TAG" --region "$R" >/dev/null 2>&1
    aws sagemaker delete-model --model-name "$TAG" --region "$R" >/dev/null 2>&1
  done
done

echo
if [ "$FOUND" -eq 1 ]; then
  echo "You have real GPU quota somewhere above. Deploy there."
else
  echo "No usable GPU quota. Check your open cases:"
  echo "  aws service-quotas list-requested-service-quota-change-history \\"
  echo "      --service-code sagemaker --region eu-north-1 \\"
  echo "      --query 'RequestedQuotas[].[QuotaName,DesiredValue,Status]' --output table"
fi
