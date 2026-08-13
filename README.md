# Self-host Whisper on a GPU you rent

One hour. You deploy `openai/whisper-large-v3` to your own SageMaker endpoint on an
NVIDIA T4, send it audio, and get a transcript with word-level timestamps back.
No model files touch your laptop.

The point isn't the transcript. It's that an open-weights model on rented GPU is a
deployable thing, and you can reason about what it costs.

---

## Before you start

You need three env vars and about two minutes. **Do this the evening before.**

```bash
git clone <this repo> && cd whisper-sagemaker-workshop
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt          # ~50 MB, no model weights

# credentials you were sent privately
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_DEFAULT_REGION=...            # yours, from the table below
export SAGEMAKER_ROLE_ARN=...            # sent with your credentials

# prove it works
aws sts get-caller-identity
```

If `get-caller-identity` returns your user, you're ready. **If it errors, say so the
night before, not in the session.**

### Your region

Quota is one GPU endpoint per region, so we each get our own.

| Who | Region | |
|---|---|---|
| 1 | `eu-north-1` | Stockholm |
| 2 | `eu-west-1` | Ireland |
| 3 | `eu-central-1` | Frankfurt |
| 4 | `eu-west-2` | London |
| 5 | `eu-west-3` | Paris |

That regional split is not decoration — it's the first thing you learn. Quota is
per-region, and it is the binding constraint on self-hosting far more often than money is.

---

## The session

### 1. Deploy — do this first, it takes 7–13 minutes

```bash
export ENDPOINT_NAME=whisper-$USER
python src/deploy.py
```

Leave it running and come back. While it provisions, the container pulls a ~10 GB
image and your 2.7 GB model archive onto a machine you're now paying for.

Measured, `ml.g4dn.xlarge`, whisper-large-v3:

| weights from | time to InService |
|---|---|
| Hugging Face (`HF_MODEL_ID`) | **34 min** — it snapshot-downloads the whole 24.7 GB repo |
| S3 (what this repo does) | **7–13 min** |

### 2. Transcribe

```bash
python src/transcribe.py audio/sample.wav
python src/transcribe.py audio/sample.wav --words        # word-level timestamps
python src/transcribe.py audio/sample.wav --lang nl      # force Dutch
```

### 3. Then actually poke at it

Pick whichever you find interesting — these are the reason we're here:

- **Time it.** Transcribe a 60-second clip. Now work out the cost per audio-hour at
  `$0.78–0.92/hr` for the instance. Compare with Azure Speech batch at **€0.158/audio-hour**
  and AOAI Whisper batch at **€0.417**. At what volume does renting the GPU win?
- **Break the language.** Run Dutch audio without `--lang nl`. Does it detect correctly?
  Does forcing it change the output?
- **Find the ceiling.** How long an audio file before it fails or times out? Why?
- **Check the timestamps.** Are the word-level ones actually accurate, or plausible-looking?
  This is what WhisperX's forced alignment exists to fix.
- **Swap the model.** `HF_MODEL_ID=openai/whisper-small python src/deploy.py` under a
  different `ENDPOINT_NAME` — wait, you only have quota for one. So: what would you
  *have* to give up to compare two models?

### 4. Clean up — not optional

```bash
python src/cleanup.py
```

An idle T4 endpoint costs about **$0.85/hour** whether or not you use it. This is the
always-on tax in the deck, and now it's your bill.

---

## Cost

| | |
|---|---|
| `ml.g4dn.xlarge` endpoint | $0.78–0.92/hour depending on region |
| Five people, ~2 hours | **≈ $9** |
| Weights, S3, logs | rounding error |

---

## For the organiser

**First, check you actually have GPU quota.** Service Quotas will report `1` for
instance types whose enforced limit is `0` — on this account it did that for 49 GPU
rows across 17 regions. Don't trust the table; probe it:

```bash
bash setup/check-gpu-quota.sh
```

```bash
bash setup/setup-iam.sh     # once, before. Creates role, policy, group, 5 users + keys
bash setup/teardown.sh      # after. Deletes endpoints in all 5 regions, then the IAM
```

`setup-iam.sh` writes keys to `~/whisper-workshop-credentials.txt` (0600, **outside this
repo** — this repo is public and never contains secrets). Hand them out privately.

**Tested end to end** on 13 Aug 2026 in eu-north-1: deploy (7 min), plain transcript
(3.0s), word timestamps (5.8s, 29 chunks), forced Dutch (2.0s), cleanup. Total cost of
building and testing this: about $5.

### Three things that cost an hour each, so you don't repeat them

**The SDK v2/v3 split.** `pip install sagemaker` gets you 3.x, which deleted
`sagemaker.huggingface` and `sagemaker.model`. Hence the `<3` pin in requirements.txt.

**The stock ASR handler takes no parameters.** Send it JSON and it passes your
`inputs` string to `open()` as a filename. Word timestamps and language forcing are
unreachable without a custom handler — that's why `src/code/inference.py` exists. Two
traps in writing one: the pipeline wants a numpy array (use `ffmpeg_read`, not raw
bytes), and `transform_fn` must return the body *only* — returning `(body, accept)`
gets the tuple serialised and you receive `["{...}", "application/json"]`.

**The handler must live inside `model.tar.gz` under `code/`.** Pointing
`SAGEMAKER_SUBMIT_DIRECTORY` at a separate S3 tarball is silently ignored — the log
says `No inference script implementation was found` and it falls back to the default.
So iterating on the handler means re-uploading the whole archive.
