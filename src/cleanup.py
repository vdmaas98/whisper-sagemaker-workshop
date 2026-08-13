"""
Step 3 - give the GPU back.

    python src/cleanup.py

Deletes your endpoint, its config and the model. An idle ml.g4dn.xlarge still
costs ~$0.85/hour, so this is not optional.
"""
import os, sys, boto3

name = os.environ.get("ENDPOINT_NAME") or (sys.argv[1] if len(sys.argv) > 1 else None)
if not name:
    sys.exit("No endpoint. Set ENDPOINT_NAME or pass it as an argument.")

sm = boto3.client("sagemaker")
for label, fn, kw in [
    ("endpoint",        sm.delete_endpoint,        {"EndpointName": name}),
    ("endpoint config", sm.delete_endpoint_config, {"EndpointConfigName": name}),
]:
    try:
        fn(**kw); print(f"deleted {label}: {name}")
    except Exception as e:
        print(f"{label}: {type(e).__name__} - {str(e)[:90]}")

try:
    models = sm.list_models(NameContains=name)["Models"]
    for m in models:
        sm.delete_model(ModelName=m["ModelName"])
        print(f"deleted model: {m['ModelName']}")
except Exception as e:
    print(f"models: {str(e)[:90]}")

left = sm.list_endpoints()["Endpoints"]
print(f"\nendpoints still running in this region: {len(left)}")
for e in left:
    print(f"  {e['EndpointName']}  {e['EndpointStatus']}")
