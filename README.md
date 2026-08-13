# Self-host Whisper on a GPU you rent — and win the challenge

One hour. You deploy `openai/whisper-large-v3` to **your own** SageMaker endpoint on an
NVIDIA T4, then use it to solve a puzzle. No model files touch your laptop.

The point isn't the transcript. It's that when you self-host, the whole pipeline is
yours to control — and the scoreboard measures how well you control it.

---

## Before you start — the evening before, 2 minutes

```bash
git clone https://github.com/vdmaas98/whisper-sagemaker-workshop
cd whisper-sagemaker-workshop
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt          # ~50 MB, no model weights
```

Then paste the four lines you were sent privately:

```bash
export AWS_ACCESS_KEY_ID=AKIA...
export AWS_SECRET_ACCESS_KEY=...
export AWS_DEFAULT_REGION=eu-central-1
export SAGEMAKER_ROLE_ARN=arn:aws:iam::<account>:role/WorkshopSageMakerExecutionRole
```

Keep them in your shell or a local `.env` you source — **never in this repo.**

Prove it works:

```bash
aws sts get-caller-identity        # should print your workshop user
```

**If that errors, message me the night before, not at 09:00.**

Everyone is in `eu-central-1` — that is where the GPU quota is. `eu-north-1` has room
for two endpoints and everywhere else has none.

---

## The session

### 1. Deploy — first thing, takes 7–13 minutes

```bash
export ENDPOINT_NAME=whisper-$USER
python src/deploy.py
```

Leave it running. It is pulling a ~10 GB container and your 2.7 GB model archive onto
a machine you are now paying for. Come back when the talk is done.

Measured on `ml.g4dn.xlarge`, whisper-large-v3:

| weights from | time to InService |
|---|---|
| Hugging Face (`HF_MODEL_ID`) | **34 min** — snapshot-downloads the whole 24.7 GB repo |
| S3 (what this repo does) | **7–13 min** |

### 2. Check it's alive

```bash
python src/transcribe.py audio/hello.wav          # 12s sanity check
python src/transcribe.py audio/hello.wav --words  # word-level timestamps
```

### 3. The challenge

`audio/challenge.wav` is a 75-second reading with something done to it. Sent to your
endpoint as-is it scores **0%**.

```bash
python src/transcribe.py audio/challenge.wav > attempt.txt
python src/score.py attempt.txt
```

Work out what was done and undo it. Score is word-level match against the undamaged
reference, which is not in this repo. **Highest score at the end wins.**

Two tools are provided. Whether you need one, both or neither is for you to work out:

```bash
python src/tools.py flip   in.wav out.wav        # invert the spectrum
python src/tools.py segrev in.wav out.wav 250    # reverse every N ms block
```

Both are their own inverse. Ignore them and use ffmpeg, sox or Audacity if you prefer.

Worth knowing:

* **Listen to the file first.** Thirty seconds with headphones beats an hour of guessing.
* Partial credit is real — a near-miss on a parameter scores well above zero, so sweep it.
* The scoring landscape is not smooth. There is at least one decoy that scores well
  without being right.
* `--words` and `--lang` exist and may or may not help. Measure, don't assume.

### 4. Clean up — not optional

```bash
python src/cleanup.py
```

An idle T4 costs about **$0.92/hour** whether you use it or not. That is the always-on
tax from the talk, now on your own bill.

---

## Cost

| | |
|---|---|
| `ml.g4dn.xlarge`, eu-central-1 | $0.92/hour |
| Five people, ~2 hours | **≈ $9** |

---

## For the organiser

```bash
bash setup/check-gpu-quota.sh   # probe REAL quota - the table lies, see below
bash setup/setup-iam.sh         # once. role, policy, group, 5 users + keys
bash setup/teardown.sh          # after. deletes endpoints everywhere, then the IAM
```

`setup-iam.sh` writes keys to `~/whisper-workshop-credentials.txt` (mode 0600,
**outside this repo** — this repo is public). Hand them out privately.

---

## Things that cost an hour each, so you don't repeat them

**Service Quotas lies.** It reported `ml.g4dn.xlarge for endpoint usage = 1` in all 17
enabled regions. The enforced limit was **0** in every one tested — `CreateEndpoint`
returns `ResourceLimitExceeded ... is 0 Instances`. Reading the table is not a check,
which is why `check-gpu-quota.sh` attempts a real deploy instead.

**The SDK v2/v3 split.** `pip install sagemaker` gets 3.x, which deleted
`sagemaker.huggingface` and `sagemaker.model`. Hence the `<3` pin in requirements.txt.

**`HF_MODEL_ID` downloads the entire repo.** whisper-large-v3 ships Flax, fp32 `.bin`,
fp32 safetensors *and* fp16 safetensors — 24.7 GB to run a 3 GB model. Staging
fp16-only weights to S3 took deploy from 34 minutes down to 12.

**The stock ASR handler takes no parameters.** Send it JSON and it passes your `inputs`
string to `open()` as a filename, so timestamps and language forcing are unreachable.
Hence `src/code/inference.py`. Two traps when writing one: the pipeline wants a numpy
array (use `ffmpeg_read`), and `transform_fn` must return the body **only** — returning
`(body, accept)` serialises the tuple and you get `["{...}", "application/json"]`.

**The handler must live inside `model.tar.gz` under `code/`.** Pointing
`SAGEMAKER_SUBMIT_DIRECTORY` at a separate S3 tarball is silently ignored — the log says
`No inference script implementation was found` and it falls back to the default handler.

**Whisper large-v3 is extremely robust to ordinary damage**, which is why the challenge
uses invertible structural damage rather than noise. Measured on a 30s clip: 1.37× speed
with pitch shift, telephone band-limiting, pink noise and gain loss *stacked together*
still scored 97.6% — and every attempt to clean it up made things worse. Pink noise
degrades gracefully to about 0.30 amplitude then collapses to 0% at 0.35. Robust until a
cliff, with no usable middle.

---

*Audio: "The Art of Badminton" from LibriVox, public domain.*
