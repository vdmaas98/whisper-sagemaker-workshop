# Self-host Whisper on a GPU you rent — and win the challenge

One hour. You deploy `openai/whisper-large-v3` to **your own** SageMaker endpoint on an
NVIDIA T4, then use it to solve a puzzle. No model files touch your laptop.

The point isn't the transcript. It's that when you self-host, the whole pipeline is
yours to control — and the scoreboard measures how well you control it.

---

## Do this BEFORE the session — 2 minutes, and it will not work if you skip it

```bash
git clone https://github.com/vdmaas98/whisper-sagemaker-workshop
cd whisper-sagemaker-workshop
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt          # ~50 MB, no model weights
```

I will send you a block of four `export` lines privately. Put them in a file called
`.env` in this directory — **not** straight into your terminal, because those vanish the
moment you close the tab.

```bash
nano .env          # paste the four lines I sent you, then save
chmod 600 .env
```

`.env` is in `.gitignore`, so it will not be committed. That matters: this repo is public
and you will be pushing a branch to it.

Load it into your shell. **You must do this in every new terminal tab:**

```bash
source .env
```

Prove it works:

```bash
aws sts get-caller-identity        # should print your workshop user, not root
echo $SAGEMAKER_ROLE_ARN           # must not be empty
```

Both have to be right. `deploy.py` exits immediately if `SAGEMAKER_ROLE_ARN` is unset,
and that is the single most common way to lose ten minutes.

**If either errors, message me before the session starts, not during it.**

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
endpoint as-is it scores about **5%**.

```bash
python src/transcribe.py audio/challenge.wav > attempt.txt
python src/score.py attempt.txt
```

Work out what was done and undo it. Score is word-level match against the undamaged
reference, which is embedded in `score.py` so scoring works offline. It is the answer key,
not the answer — it tells you nothing about what was done to the audio.

No tools are provided. Working out what was done, and writing the thing that undoes it,
is the entire exercise. `ffmpeg`, `sox`, Audacity, numpy, or twenty lines of Python —
whatever you like.

Worth knowing:

* **Listen to the file first.** Thirty seconds of actually hearing it beats an hour of
  guessing. It is plainly speech and you should be able to tell what is wrong with it.
* **Nothing was added and nothing was removed.** Every sample of the original is still
  in there, at the same amplitude, in a 16 kHz mono WAV. So this is not noise, and no
  amount of denoising, filtering or EQ will help you.
* Whatever was done is exactly reversible, and more than one thing was done.
* Near-zero is the normal state until you are close. Partial credit appears late, so
  sweep systematically rather than hill-climbing from a bad score.
* `--words` and `--lang` exist and may or may not help. Measure, don't assume.

**Ties break on who got there first**, so tell me your score as soon as you have it.

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

The challenge recipe lives in `~/whisper-workshop-solution.md`, also outside this repo.
Keep the scoreboard on your own screen:

```bash
python3 -m http.server 3001 -d scoreboard   # then open http://localhost:3001
```

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
