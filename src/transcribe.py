"""
Step 2 - send audio to the GPU you just rented.

    python src/transcribe.py audio/sample.mp3
    python src/transcribe.py audio/sample.mp3 --words     # word-level timestamps
    python src/transcribe.py audio/sample.mp3 --lang nl   # force Dutch

Sends raw audio bytes to your endpoint and prints what comes back, plus the
round-trip time. Nothing clever - the point is that you are now the one holding
the GPU.
"""

import argparse
import json
import os
import sys
import time

import boto3

p = argparse.ArgumentParser()
p.add_argument("audio", help="path to an audio file (mp3/wav/m4a/flac)")
p.add_argument("--words", action="store_true", help="ask for word-level timestamps")
p.add_argument("--chunks", action="store_true", help="ask for chunk-level timestamps")
p.add_argument("--lang", default=None, help="force a language, e.g. nl")
p.add_argument("--endpoint", default=os.environ.get("ENDPOINT_NAME"))
args = p.parse_args()

if not args.endpoint:
    sys.exit("No endpoint. Set ENDPOINT_NAME or pass --endpoint")
if not os.path.exists(args.audio):
    sys.exit(f"No such file: {args.audio}")

rt = boto3.client("sagemaker-runtime")
raw = open(args.audio, "rb").read()
print(f"endpoint : {args.endpoint}")
print(f"audio    : {args.audio}  ({len(raw)/1_000_000:.1f} MB)")

# The HF inference toolkit accepts raw audio bytes directly. To pass generate
# parameters it wants JSON, so we only switch to JSON when we need to.
params = {}
if args.words:
    params["return_timestamps"] = "word"
elif args.chunks:
    params["return_timestamps"] = True
if args.lang:
    params["generate_kwargs"] = {"language": args.lang}

start = time.time()
if params:
    import base64

    body = json.dumps({"inputs": base64.b64encode(raw).decode(), "parameters": params})
    content_type = "application/json"
else:
    body = raw
    content_type = "audio/x-audio"

resp = rt.invoke_endpoint(
    EndpointName=args.endpoint, ContentType=content_type, Accept="application/json", Body=body
)
elapsed = time.time() - start
out = json.loads(resp["Body"].read())

print(f"took     : {elapsed:.1f}s\n")

if isinstance(out, dict) and "text" in out:
    print(out["text"].strip())
    marks = out.get("chunks") or []
    if marks:
        print(f"\n--- {len(marks)} timestamped segments ---")
        for c in marks[:40]:
            ts = c.get("timestamp") or [None, None]
            a = f"{ts[0]:.2f}" if ts[0] is not None else "?"
            b = f"{ts[1]:.2f}" if ts[1] is not None else "?"
            print(f"  [{a:>7} - {b:>7}]  {c.get('text','').strip()}")
        if len(marks) > 40:
            print(f"  ... and {len(marks)-40} more")
else:
    print(json.dumps(out, indent=2, ensure_ascii=False)[:4000])
