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

### 1. Deploy — do this first, it takes 5–10 minutes

```bash
export ENDPOINT_NAME=whisper-$USER
python src/deploy.py
```

Leave it running and come back. While it provisions, the container is pulling ~3 GB
of weights onto a machine you're now paying for.

### 2. Transcribe

```bash
python src/transcribe.py audio/sample.mp3
python src/transcribe.py audio/sample.mp3 --words        # word-level timestamps
python src/transcribe.py audio/sample.mp3 --lang nl      # force Dutch
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

```bash
bash setup/setup-iam.sh     # once, before. Creates role, policy, group, 5 users + keys
bash setup/teardown.sh      # after. Deletes endpoints in all 5 regions, then the IAM
```

`setup-iam.sh` writes keys to `~/whisper-workshop-credentials.txt` (0600, **outside this
repo** — this repo is public and never contains secrets). Hand them out privately.

**Test the whole path yourself first.** Deploy, transcribe, clean up. If `deploy.py`
fails on the HF container version or the payload shape, you want to find that tonight,
not in front of the room.
