"""Local-only parity and latency check for the sound judge's Core ML package. Never run by CI or the app.

Compares the int8 package (scripts/fetch-judge-model.sh) against PyTorch fp32 posteriors of the same upstream model
on VCTK starter clips, through the judging spike's segmentation-free GOP (its scripts/gop.py, imported from the spike
folder, which is not part of this repo). Reports GOP Pearson (bar >= 0.99) and flag agreement at tau = -4.75, and
the 4 s bucket's forward latency on CPU_AND_NE (bar < 60 ms). With --other it also compares a second Core ML package
(the spike's lv60_int8.mlpackage) against the first.

The take goes through the model as the app sends it: raw 16 kHz samples zero-padded to the smallest bucket that
holds them, then normalised as (y - mean) / sqrt(var + 1e-7). PyTorch is run twice: on the same padded input
("padded": the package's numerical fidelity) and on the unpadded clip ("unpadded": the spike's reference setup).

Core ML rewrites a package's Manifest.json when it opens one, which would break fetch-judge-model.sh --verify, so
every package is copied to a temporary folder before it is loaded; nothing is loaded in place.

Run it in a venv with torch, transformers, coremltools, soundfile and librosa (the spike's .venv has them):

  python -I tools/judge_model_parity.py --spike SPIKE_DIR --torch-model UPSTREAM_DIR \
      --package CACHE/wav2vec2-lv-60-espeak-cv-ft/LV60Int8.mlpackage [--other SPIKE_DIR/models/lv60_int8.mlpackage] \
      [--clips 20] [--out report.json]
"""

import argparse
import json
import os
import re
import shutil
import sys
import tempfile
import time

import coremltools as ct
import librosa
import numpy as np
import soundfile as sf
import torch
from transformers import Wav2Vec2ForCTC

SR = 16_000
BUCKETS = (2, 4, 6, 8, 10, 12, 15)
TAU = -4.75


def normalise(y):
    return ((y - y.mean()) / np.sqrt(y.var() + 1e-7)).astype(np.float32)


def pad_to_bucket(y, buckets=BUCKETS):
    for s in buckets:
        if len(y) <= s * SR:
            return np.pad(y, (0, s * SR - len(y)))
    return None


def load_copy(package, compute_units, tmp):
    dst = os.path.join(tmp, f"{len(os.listdir(tmp))}-{os.path.basename(package)}")
    shutil.copytree(package, dst)
    t = time.perf_counter()
    model = ct.models.MLModel(dst, compute_units=getattr(ct.ComputeUnit, compute_units))
    return model, time.perf_counter() - t


def coreml_logprobs(model, x):
    return torch.tensor(model.predict({"audio": x[None]})["logprobs"][0].astype(np.float32))


def stats(a, b):
    a, b = np.array(a), np.array(b)
    return {
        "units": len(a),
        "gop_pearson": round(float(np.corrcoef(a, b)[0, 1]), 4),
        "gop_mean_abs_diff": round(float(np.abs(a - b).mean()), 3),
        "flag_agreement_at_tau": round(float(np.mean((a < TAU) == (b < TAU))), 4),
        "flags_a": int((a < TAU).sum()),
        "flags_b": int((b < TAU).sum()),
    }


def latency(model, y4, n=20):
    x = normalise(pad_to_bucket(y4, (4,)))
    for _ in range(3):
        model.predict({"audio": x[None]})
    ts = []
    for _ in range(n):
        t = time.perf_counter()
        model.predict({"audio": x[None]})
        ts.append(time.perf_counter() - t)
    return round(1000 * float(np.median(ts)), 1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--spike", required=True)
    ap.add_argument("--torch-model", required=True)
    ap.add_argument("--package", required=True)
    ap.add_argument("--other")
    ap.add_argument("--clips", type=int, default=20)
    ap.add_argument("--out")
    args = ap.parse_args()

    sys.path.insert(0, os.path.join(args.spike, "scripts"))
    os.environ.setdefault("VOCAB", os.path.join(args.torch_model, "vocab.json"))
    from gop import gop, text_phones, units  # noqa: E402  (the spike's GOP, local only)

    meta = json.load(open(os.path.join(args.spike, "box-headstart", "lists", "vctk_starter_meta.json")))

    def load(uid):
        spk, utt = uid.split("_")
        y, sr = sf.read(os.path.join(args.spike, "data", "starter", f"vctk-{utt}_{spk}.flac"), dtype="float32")
        if y.ndim > 1:
            y = y.mean(1)
        return librosa.resample(y, orig_sr=sr, target_sr=SR) if sr != SR else y

    step = max(1, len(meta) // args.clips)
    picked = [m for m in meta[::step]][: args.clips]

    torch.set_num_threads(4)
    pt = Wav2Vec2ForCTC.from_pretrained(args.torch_model, local_files_only=True, attn_implementation="eager").eval()

    def pt_logprobs(x):
        with torch.no_grad():
            return torch.log_softmax(pt(torch.from_numpy(x)[None]).logits[0].float(), -1)

    report = {"clips": [], "tau": TAU}
    with tempfile.TemporaryDirectory(prefix="judge-parity-") as tmp:
        ours, ours_load = load_copy(args.package, "CPU_AND_NE", tmp)
        other = load_copy(args.other, "CPU_AND_NE", tmp)[0] if args.other else None
        g_pt_pad, g_pt_raw, g_ours, g_other, g_ours_o = [], [], [], [], []
        for m in picked:
            uid = m["id"]
            words, phones = text_phones(m["text"], m.get("pron"))
            if phones is None:
                continue
            y = load(uid)
            yp = pad_to_bucket(y)
            if yp is None:
                continue
            U = units([(wi, j, p) for wi, ph in enumerate(phones) for j, p in enumerate(ph)], words)
            a = gop(pt_logprobs(normalise(yp)), U)
            b = gop(pt_logprobs(normalise(y)), U)
            c = gop(coreml_logprobs(ours, normalise(yp)), U)
            g_pt_pad += a
            g_pt_raw += b
            g_ours += c
            if other is not None and len(y) <= 10 * SR:
                # The spike's package takes any length from 1 to 10 s (RangeDim): give it the same padded input.
                yp10 = pad_to_bucket(y, (2, 4, 6, 8, 10))
                g_other += gop(coreml_logprobs(other, normalise(yp10)), U)
                g_ours_o += gop(coreml_logprobs(ours, normalise(yp10)), U)
            report["clips"].append({"id": uid, "seconds": round(len(y) / SR, 2), "bucket": len(yp) // SR,
                                    "units": len(U)})
        report["int8_vs_pytorch_padded"] = stats(g_pt_pad, g_ours)
        report["int8_vs_pytorch_unpadded"] = stats(g_pt_raw, g_ours)
        report["pytorch_padded_vs_unpadded"] = stats(g_pt_raw, g_pt_pad)
        if other is not None:
            report["spike_int8_vs_this_int8"] = stats(g_other, g_ours_o)

        y4 = load("p233_013")  # the spike's 4 s latency phrase (3.996 s)
        report["load_seconds_cpu_and_ne_first"] = round(ours_load, 1)
        report["forward_ms_4s_cpu_and_ne"] = latency(ours, y4)
        if other is not None:
            report["spike_forward_ms_4s_cpu_and_ne"] = latency(other, y4)
        del ours, other
    report["bars"] = {
        "gop_pearson_ge_0.99": report["int8_vs_pytorch_unpadded"]["gop_pearson"] >= 0.99
        and report["int8_vs_pytorch_padded"]["gop_pearson"] >= 0.99,
        "forward_4s_lt_60ms": report["forward_ms_4s_cpu_and_ne"] < 60,
    }
    text = json.dumps(report, indent=1)
    print(text)
    if args.out:
        with open(args.out, "w") as f:
            f.write(text + "\n")


if __name__ == "__main__":
    main()
