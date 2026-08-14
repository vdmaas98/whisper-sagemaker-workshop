"""
Audio tools for the challenge. These are the only two operations you need -
figuring out how many times to apply each, in what order, and with what
parameters is the whole point.

    python src/tools.py flip    in.wav out.wav         # invert the spectrum
    python src/tools.py segrev  in.wav out.wav <ms>    # reverse every N ms block

Both are their own inverse when applied with the same parameter.
"""
import sys, wave, numpy as np

def rd(p):
    w = wave.open(p); a = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16)
    return a, w.getframerate()

def wr(a, sr, p):
    w = wave.open(p, "wb"); w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr)
    w.writeframes(np.clip(a, -32768, 32767).astype(np.int16).tobytes()); w.close()

def flip(a):
    return a * (np.arange(len(a)) % 2 * 2 - 1)

def segrev(a, sr, ms):
    n = int(sr * ms / 1000)
    if n < 1: raise SystemExit("block size too small")
    m = len(a) // n * n
    return np.concatenate([a[:m].reshape(-1, n)[:, ::-1].ravel(), a[m:]])

if __name__ == "__main__":
    if len(sys.argv) < 4: raise SystemExit(__doc__)
    op, src, dst = sys.argv[1], sys.argv[2], sys.argv[3]
    a, sr = rd(src)
    if op == "flip":
        wr(flip(a), sr, dst)
    elif op == "segrev":
        wr(segrev(a, sr, float(sys.argv[4])), sr, dst)
    else:
        raise SystemExit(__doc__)
    print(f"wrote {dst}")
