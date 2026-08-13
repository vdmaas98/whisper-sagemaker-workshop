"""
Step 1 - put Whisper on a GPU you rent.

    python src/deploy.py

Deploys openai/whisper-large-v3 to your own SageMaker real-time endpoint on an
ml.g4dn.xlarge (one NVIDIA T4, 16 GB). No model files touch your laptop - the
container pulls the weights from Hugging Face on the endpoint itself.

Takes 5-10 minutes. Start it, then go and listen to the talk.
"""

import os
import sys
import time

os.environ.setdefault("SAGEMAKER_SUPPRESS_V2_WARNING", "1")

import boto3
import sagemaker
from sagemaker.huggingface import HuggingFaceModel

MODEL_DATA = os.environ.get("MODEL_DATA")  # s3://.../model.tar.gz
INSTANCE = os.environ.get("INSTANCE_TYPE", "ml.g4dn.xlarge")
ROLE_ARN = os.environ.get("SAGEMAKER_ROLE_ARN")
NAME = os.environ.get("ENDPOINT_NAME", "whisper-" + os.environ.get("USER", "you"))

if not ROLE_ARN:
    sys.exit("SAGEMAKER_ROLE_ARN is not set - see the README, it's printed by setup-iam.sh")

region = boto3.Session().region_name
if not region:
    sys.exit("No AWS region configured. Run: aws configure set region <your-region>")

account = boto3.client("sts").get_caller_identity()["Account"]
if not MODEL_DATA:
    MODEL_DATA = f"s3://sagemaker-{region}-{account}/whisper/model.tar.gz"

print(f"region    : {region}")
print(f"model     : {MODEL_DATA}")
print(f"instance  : {INSTANCE}  (1x T4, 16 GB)")
print(f"endpoint  : {NAME}")
print()

model = HuggingFaceModel(
    role=ROLE_ARN,
    # validated: resolves to huggingface-pytorch-inference:2.6-transformers4.49
    #            -gpu-py312-cu124-ubuntu22.04 in every region we use
    transformers_version="4.49",
    pytorch_version="2.6",
    py_version="py312",
    model_data=MODEL_DATA,
    env={
        # our own handler, shipped inside model.tar.gz as code/inference.py
        "SAGEMAKER_PROGRAM": "inference.py",
        # The handler MUST live inside model.tar.gz under code/. Pointing
        # SAGEMAKER_SUBMIT_DIRECTORY at a separate S3 tarball is silently ignored -
        # the log just says "No inference script implementation was found" and it
        # falls back to the default handler.
        "SAGEMAKER_SUBMIT_DIRECTORY": "/opt/ml/model/code",
        "SAGEMAKER_MODEL_SERVER_TIMEOUT": "3600",
        "SAGEMAKER_TS_RESPONSE_TIMEOUT": "3600",
    },
    sagemaker_session=sagemaker.Session(),
)

start = time.time()
print("deploying - this is the slow bit, 5-10 min. Leave it running.\n")

model.deploy(
    initial_instance_count=1,
    instance_type=INSTANCE,
    endpoint_name=NAME,
    container_startup_health_check_timeout=900,
    wait=True,
)

print(f"\nendpoint live after {int(time.time() - start)}s")
print(f"\n  export ENDPOINT_NAME={NAME}")
print("  python src/transcribe.py audio/sample.mp3")
print("\nRemember: it bills until you run src/cleanup.py")
