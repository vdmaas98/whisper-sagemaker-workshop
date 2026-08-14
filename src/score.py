"""
Score your transcript against the reference.

    python src/score.py my_transcript.txt
    python src/transcribe.py audio/attempt.wav > out.txt && python src/score.py out.txt

Word-level scoring: lowercased, punctuation stripped, matched against the
reference with difflib. Your score is the fraction of reference words recovered
in order. 100% means you have fully undone what was done to challenge.wav.
"""

import base64
import difflib
import re
import sys
import zlib

_R = "eJxtVEEO00AM/IofUPoHbnBCQkicncRJTDfrsN40lNcz3iRFSEg9JF5nPDOebZ25UhFO6UW+aXWadaGeM81Cg8WbSxrpx+ZVe6GKcj9bPNpITIX7h1RSj5MioxVBdeFapVA16oS2PEip/JBMu9YZ4OXA+blx0qriZ+MgrkUG0tynbRDqDN1Jp7lmcSfOA622A3eftZ8pYDRjmkt2oWWrW5PBufJkWYMwXl4kv2qRJfCfkmxdJNcgHxQsCyXhQfMUJJh6K0V8tdxKzn3R8RTb+kNlYxJviq6nDhiL6V5pUO/tGcLDJVvWYouCWic4DHchrv71tJO6C1xBt0d/HpP2NeYW+blpcM7V7/RJQmkz2TIEruauXZLACgo912sxKiOOFZ+dJvlsWwpLx7RJhpAZKMcC7/StDQ4fO06M0xvtEn7fGpzPvEoT6/r7bcGMQkKn1wKq+N1ay2Q20G7lsXD2WdeGfuH+k5XJsHGmZBC68wsqdi6DIzSP0G4FTyWwoflOX22b5gjnKu0c00AypQ8n9HDBLoBqIRo1o8reljuKpIBqMWqbQbT1HXmFvV+ga7cTxkM6rsThHrzi/oxV0y78VAmCrxtp22CAXlRgishCvK5FeuXu/Oqarflt4J0+Y4amFJUcvIVdjysDA3XdEpZ6CxrYcywcNyB0gH3EmePylAANZzPZ1lwu5BaVY4s0RkHKMwLchhvWjb3ZQ658nEk7LtadPrZkh+X0/xHhsuNxIOT8BWm1Rhg0/H+ce223a9BxRG7zMRq0mgsBpMuaWrTv9L3JC1MmLCRmwYaWlrcJarkFf6SnVlw0fG34N2lhXeJ2X3pOJX8Abh3BBw=="


def words(t):
    return re.sub(r"[^\w\s]", "", t.lower()).split()


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: python src/score.py <transcript.txt>   (or - for stdin)")
    raw = sys.stdin.read() if sys.argv[1] == "-" else open(sys.argv[1]).read()

    ref = words(zlib.decompress(base64.b64decode(_R)).decode())
    hyp = words(raw)
    if not hyp:
        sys.exit("no words found in your transcript")

    sm = difflib.SequenceMatcher(a=ref, b=hyp)
    ok = sum(b.size for b in sm.get_matching_blocks())
    pct = ok / len(ref)

    print()
    print(f"  words recovered : {ok} / {len(ref)}")
    print(f"  score           : {pct:.1%}")
    print(f"  {'#' * int(pct * 40):<40}|")
    print()
    if pct > 0.98:
        print("  Solved. Put your name on the board.")
    elif pct > 0.80:
        print("  Very close.")
    elif pct > 0.30:
        print("  Something is working.")
    else:
        print("  Nothing yet.")


if __name__ == "__main__":
    main()
