"""
Custom SageMaker inference handler for Whisper.

The stock HuggingFace container's ASR path accepts raw audio bytes and nothing
else - it passes a JSON "inputs" string straight to open(), so you cannot ask for
word-level timestamps or force a language. This handler fixes that.

Accepts either:
  raw bytes   Content-Type: audio/x-audio    -> plain transcript
  JSON        Content-Type: application/json
              {"inputs": "<base64 audio>",
               "parameters": {"return_timestamps": "word",
                              "generate_kwargs": {"language": "nl"}}}

Two things that bit us and are worth keeping in mind if you edit this:
  * the pipeline wants a numpy array, not bytes/bytearray, so we decode with
    ffmpeg_read ourselves rather than hoping the pipeline does it
  * transform_fn must return the body ONLY. Returning (body, accept) gets the
    tuple JSON-serialised and you get ["{...}", "application/json"] back.
"""

import base64
import json

import torch
from transformers import pipeline
from transformers.pipelines.audio_utils import ffmpeg_read

TASK = "automatic-speech-recognition"


def model_fn(model_dir, context=None):
    on_gpu = torch.cuda.is_available()
    pipe = pipeline(
        TASK,
        model=model_dir,
        device=0 if on_gpu else -1,
        torch_dtype=torch.float16 if on_gpu else torch.float32,
        chunk_length_s=30,          # handles audio longer than 30s
    )
    print(f"[inference.py] loaded on {'cuda' if on_gpu else 'cpu'}")
    return pipe


def _to_array(raw, sampling_rate):
    """bytes / bytearray / memoryview -> mono float32 numpy at the model's rate."""
    if isinstance(raw, (bytearray, memoryview)):
        raw = bytes(raw)
    return ffmpeg_read(raw, sampling_rate)


def transform_fn(model, request_body, content_type="application/json", accept="application/json"):
    sampling_rate = model.feature_extractor.sampling_rate
    params = {}

    if content_type and "json" in content_type:
        raw = request_body.decode() if isinstance(request_body, (bytes, bytearray)) else request_body
        payload = json.loads(raw)
        audio = _to_array(base64.b64decode(payload["inputs"]), sampling_rate)
        params = payload.get("parameters") or {}
    else:
        audio = _to_array(request_body, sampling_rate)

    call_kwargs = {}
    if "return_timestamps" in params:
        call_kwargs["return_timestamps"] = params["return_timestamps"]
    if "batch_size" in params:
        call_kwargs["batch_size"] = int(params["batch_size"])
    if params.get("generate_kwargs"):
        call_kwargs["generate_kwargs"] = params["generate_kwargs"]

    try:
        result = model({"raw": audio, "sampling_rate": sampling_rate}, **call_kwargs)
    except Exception as e:
        return json.dumps({"error": f"{type(e).__name__}: {e}",
                           "call_kwargs": {k: str(v) for k, v in call_kwargs.items()}})

    return json.dumps(result, ensure_ascii=False)
