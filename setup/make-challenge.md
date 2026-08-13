# Rebuilding the challenge

The answer (`audio/clean.wav`) is deliberately not in this repo. To regenerate the
whole thing from a source recording:

```bash
# 1. a 75s clip. Public domain only - LibriVox, a ministry PDF reading, your own voice.
ffmpeg -ss 35 -t 75 -i source.mp3 -ar 16000 -ac 1 audio/clean.wav

# 2. transcribe it with the deployed endpoint - that transcript IS the reference
python src/transcribe.py audio/clean.wav > /tmp/ref.txt

# 3. apply the two layers. Change 250 to move the answer.
python src/tools.py segrev audio/clean.wav /tmp/a.wav 250
python src/tools.py flip   /tmp/a.wav      audio/challenge.wav

# 4. embed the new reference in the scorer
python - <<'PY'
import zlib, base64, pathlib, re
ref = open('/tmp/ref.txt').read().strip()
blob = base64.b64encode(zlib.compress(ref.encode())).decode()
p = pathlib.Path('src/score.py')
p.write_text(re.sub(r'_R = "[^"]*"', f'_R = "{blob}"', p.read_text()))
PY

# 5. verify: 0% as given, 100% when both layers are undone
python src/transcribe.py audio/challenge.wav > /tmp/t.txt && python src/score.py /tmp/t.txt
```

Order matters: segrev THEN flip when building, so solvers must flip THEN segrev.

Why these two operations and not noise: whisper-large-v3 shrugs off noise, band-limiting,
speed and pitch changes - stacked together they still scored 97.6%. It stays robust until
it collapses to 0% with no usable middle. Invertible structural damage is the only kind
that produces a real scoring gradient.

Measured gradient for segment size (true value 250 ms):

| guess | 150 | 200 | 225 | 240 | **250** | 260 | 300 | 400 |
|---|---|---|---|---|---|---|---|---|
| score | 11% | 81% | 87% | 84% | **100%** | 78% | 42% | 22% |
