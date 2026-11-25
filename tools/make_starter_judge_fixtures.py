#!/usr/bin/env python3
"""Compact sound-judge posteriors for the starter regression (sound-judging plan, 2026-11-25).

For each starter phrase, the default voice's recording (p311) in Resources/Starter is decoded the way the app decodes
it (first channel, 48 kHz FLAC, brought to 16 kHz by StarterReferences.resample's Blackman-windowed sinc), zero-padded
to the smallest input bucket that holds it (raw samples, before normalisation, as the app does), normalised
((y - mean) / sqrt(var + 1e-7)) and run through the Core ML judge model. The CTC log-posteriors are kept only for the
blank and the English espeak tokens the GOP reads (the spike's gop.py ENG set), as float16, so CI can run the regression
without the model: AMPipelineTests' StarterJudgeRegressionTests fills every other column with FILL.

This is the one tool here that is not dependency-free: it needs numpy, soundfile and coremltools (the judging spike's
venv). It writes fixtures/starter-judge/<phrase>.json and nothing else.

    python tools/make_starter_judge_fixtures.py --model path/to/LV60Int8.mlpackage --vocab path/to/vocab.json
"""

import argparse
import base64
import json
import math
import os

import coremltools as ct
import numpy as np
import soundfile as sf

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STARTER = os.path.join(ROOT, "Resources", "Starter")
OUT = os.path.join(ROOT, "fixtures", "starter-judge")
VOICE = "p311"
BUCKETS_SECONDS = [2, 4, 6, 8, 10, 12, 15]
SAMPLE_RATE = 16_000
FILL = -10_000.0

# gop.py's lenient classes: every acceptable token of every ARPAbet unit, plus the composites. The GOP denominator
# substitutes each of these, so they and the blank are the only columns the scorer reads.
CLS = {
    "AA": ["ɑː", "ɑ"], "AE": ["æ", "a"], "AH": ["ʌ", "ə", "ɐ"], "AH0": ["ə", "ɐ", "ᵻ", "ɪ", "ʌ"],
    "AO": ["ɔː", "ɔ", "ɑː", "ɑ"], "AW": ["aʊ"], "AY": ["aɪ"], "EH": ["ɛ", "e"], "ER": ["ɜː", "ɚ"], "ER0": ["ɚ", "ə"],
    "EY": ["eɪ", "e"], "IH": ["ɪ", "ᵻ"], "IH0": ["ɪ", "ᵻ", "ə", "i", "iː"], "IY": ["iː", "i"], "IY0": ["i", "iː", "ɪ"],
    "OW": ["oʊ", "o", "oː"], "OY": ["ɔɪ"], "UH": ["ʊ"], "UW": ["uː", "u"], "UW0": ["uː", "u", "ʊ", "ə"],
    "B": ["b"], "CH": ["tʃ"], "D": ["d", "ɾ"], "DH": ["ð"], "F": ["f"], "G": ["ɡ"], "HH": ["h"], "JH": ["dʒ"],
    "K": ["k"], "L": ["l"], "M": ["m"], "N": ["n"], "NG": ["ŋ"], "P": ["p"], "R": ["ɹ"], "S": ["s"], "SH": ["ʃ"],
    "T": ["t", "ɾ", "ʔ"], "TH": ["θ"], "V": ["v"], "W": ["w"], "Y": ["j"], "Z": ["z"], "ZH": ["ʒ"],
}
COMPOSITES = [["ɑːɹ"], ["ɔːɹ", "oːɹ"], ["oːɹ", "ɔːɹ"], ["ɛɹ"], ["ɪɹ"], ["ɪɹ", "iə"], ["ʊɹ"], ["ʊɹ"], ["aɪɚ"]]
ENGLISH = sorted({t for v in list(CLS.values()) + COMPOSITES for t in v} | {"ɑːɹ", "əl", "ʔ"})


def resample(samples, source_rate, target_rate):
    """StarterReferences.resample: integer-factor decimation through a Blackman-windowed sinc at 0.45 x target."""
    if source_rate == target_rate:
        return samples.astype(np.float32)
    ratio = source_rate / target_rate
    assert ratio > 1 and ratio == round(ratio), f"unsupported rate {source_rate}"
    factor = int(ratio)
    taps = 32 * factor + 1
    cutoff = 0.45 / ratio
    centre = (taps - 1) / 2
    i = np.arange(taps, dtype=np.float64)
    x = i - centre
    with np.errstate(divide="ignore", invalid="ignore"):
        sinc = np.where(x == 0, 2 * cutoff, np.sin(2 * math.pi * cutoff * x) / (math.pi * x))
    window = 0.42 - 0.5 * np.cos(2 * math.pi * i / (taps - 1)) + 0.08 * np.cos(4 * math.pi * i / (taps - 1))
    fir = (sinc * window).astype(np.float32)
    fir = fir / fir.sum()
    pad = np.zeros(taps // 2, dtype=np.float32)
    padded = np.concatenate([pad, samples.astype(np.float32), pad, np.zeros(factor, dtype=np.float32)])
    count = len(samples) // factor
    # vDSP_desamp: out[n] = sum_p padded[n * factor + p] * fir[p]
    out = np.array([np.dot(padded[n * factor:n * factor + taps], fir) for n in range(count)], dtype=np.float32)
    return out


def decode16k(path):
    data, rate = sf.read(path, dtype="float32", always_2d=True)
    return resample(data[:, 0], rate, SAMPLE_RATE)


def bucketed(samples):
    for seconds in BUCKETS_SECONDS:
        if len(samples) <= seconds * SAMPLE_RATE:
            return np.pad(samples, (0, seconds * SAMPLE_RATE - len(samples))), seconds
    raise SystemExit(f"take longer than {BUCKETS_SECONDS[-1]} s")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True, help="the judge's .mlpackage (int8)")
    parser.add_argument("--vocab", required=True, help="the model's vocab.json (392 espeak tokens)")
    parser.add_argument("--model-name", default="", help="what to record as the posteriors' source")
    args = parser.parse_args()

    vocab = json.load(open(args.vocab, encoding="utf-8"))
    columns = sorted({vocab["<pad>"]} | {vocab[t] for t in ENGLISH})
    model = ct.models.MLModel(args.model, compute_units=ct.ComputeUnit.CPU_ONLY)
    manifest = json.load(open(os.path.join(STARTER, "manifest.json"), encoding="utf-8"))
    os.makedirs(OUT, exist_ok=True)
    total = 0
    for phrase in manifest["phrases"]:
        recording = next(r for r in phrase["recordings"] if r["speaker"] == VOICE)
        samples = decode16k(os.path.join(STARTER, recording["audio"]))
        padded, bucket = bucketed(samples)
        x = ((padded - padded.mean()) / np.sqrt(padded.var() + 1e-7)).astype(np.float32)
        logprobs = model.predict({"audio": x[None]})["logprobs"][0].astype(np.float32)
        assert logprobs.shape[1] == len(vocab), logprobs.shape
        kept = logprobs[:, columns].astype("<f2")
        fixture = {
            "formatVersion": 1,
            "phraseID": phrase["id"],
            "recordingID": recording["id"],
            "text": phrase["text"],
            "model": args.model_name or os.path.basename(args.model.rstrip("/")),
            "bucketSeconds": bucket,
            "takeSamples": int(len(samples)),
            "frames": int(logprobs.shape[0]),
            "vocabularySize": len(vocab),
            "columns": columns,
            "fill": FILL,
            "valuesFloat16Base64": base64.b64encode(kept.tobytes()).decode("ascii"),
        }
        path = os.path.join(OUT, phrase["id"] + ".json")
        with open(path, "w", encoding="utf-8") as f:
            json.dump(fixture, f, indent=1, ensure_ascii=False)
            f.write("\n")
        total += os.path.getsize(path)
        print(phrase["id"], recording["id"], f"{len(samples) / SAMPLE_RATE:.2f} s -> {bucket} s,",
              f"{logprobs.shape[0]} frames x {len(columns)} columns")
    print(f"{total} bytes in {OUT}")


if __name__ == "__main__":
    main()
