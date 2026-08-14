"""
Step 3 - give the GPU back.

    python src/cleanup.py

Deletes your endpoint, its config and the model behind it. An idle
ml.g4dn.xlarge still costs ~$0.92/hour, so this is not optional.

Order matters: the endpoint config is the only thing that knows which model
you deployed (the SDK names it huggingface-pytorch-inference-<timestamp>, not
after your endpoint), so read that out before deleting the config.
"""
import os, sys, boto3

name = os.environ.get("ENDPOINT_NAME") or (sys.argv[1] if len(sys.argv) > 1 else None)
if not name:
    sys.exit("No endpoint. Set ENDPOINT_NAME or pass it as an argument.")

sm = boto3.client("sagemaker")

# 1. which model does this endpoint use? ask before we delete the config.
models = []
try:
    cfg = sm.describe_endpoint_config(EndpointConfigName=name)
    models = [v["ModelName"] for v in cfg.get("ProductionVariants", [])]
except Exception as e:
    print(f"endpoint config lookup: {type(e).__name__} - {str(e)[:90]}")

# 2. the endpoint is the only thing that costs money - kill it first.
for label, fn, kw in [
    ("endpoint",        sm.delete_endpoint,        {"EndpointName": name}),
    ("endpoint config", sm.delete_endpoint_config, {"EndpointConfigName": name}),
]:
    try:
        fn(**kw); print(f"deleted {label}: {name}")
    except Exception as e:
        print(f"{label}: {type(e).__name__} - {str(e)[:90]}")

for m in models:
    try:
        sm.delete_model(ModelName=m); print(f"deleted model: {m}")
    except Exception as e:
        print(f"model {m}: {type(e).__name__} - {str(e)[:90]}")

left = sm.list_endpoints()["Endpoints"]
print(f"\nendpoints still running in this region: {len(left)}")
for e in left:
    print(f"  {e['EndpointName']}  {e['EndpointStatus']}")
if left:
    print("\n'Deleting' is fine, it takes a minute. Anything else is still costing money.")
