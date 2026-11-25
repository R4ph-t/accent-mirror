"""Converts facebook/wav2vec2-lv-60-espeak-cv-ft (Apache-2.0) to the Core ML package the sound judge ships.

Run only by scripts/fetch-judge-model.sh, inside its pinned venv (tools/convert_judge_model.requirements.txt) under
a git-ignored cache. Never at app runtime and never in CI. Input: the upstream folder (config.json,
pytorch_model.bin, ...), already SHA-256 checked against the manifest. Output: LV60Int8.mlpackage, an mlprogram
(macOS 14) taking `audio` (1 x N float32: 16 kHz mono, normalised as (y - mean) / sqrt(var + 1e-7)) and returning
`logprobs` (1 x T x 392 float32: log-softmax over the espeak IPA vocabulary, one frame per 320 samples).

N is one of the enumerated buckets (2, 4, 6, 8, 10, 12 and 15 s): the Neural Engine is only fast at a length the
model was compiled for, so the app zero-pads a take to the smallest bucket that holds it. Converted in fp16, then
the weights are quantised to int8 (per-channel, linear symmetric), as the judging spike did; compute stays fp16.

Reproducible bytes, so the package can be SHA-256 pinned (as tools/convert_ctc.py): the model spec is re-serialised
deterministically and the package's Manifest.json item identifiers are derived from each item's path.
"""

import json
import os
import sys
import uuid

import coremltools as ct
import coremltools.optimize.coreml as cto
import numpy as np
import torch
from coremltools.proto import Model_pb2
from transformers import Wav2Vec2ForCTC

SAMPLE_RATE = 16_000
BUCKETS_SECONDS = (2, 4, 6, 8, 10, 12, 15)
DEFAULT_SECONDS = 4


class LogProbs(torch.nn.Module):
    def __init__(self, model):
        super().__init__()
        self.model = model

    def forward(self, audio):
        return torch.log_softmax(self.model(audio).logits, dim=-1)


def main(upstream: str, out: str) -> None:
    torch.manual_seed(0)
    model = Wav2Vec2ForCTC.from_pretrained(upstream, local_files_only=True, attn_implementation="eager").eval()
    example = torch.randn(1, DEFAULT_SECONDS * SAMPLE_RATE)
    with torch.no_grad():
        traced = torch.jit.trace(LogProbs(model).eval(), example, strict=False)
    shapes = ct.EnumeratedShapes(
        shapes=[(1, s * SAMPLE_RATE) for s in BUCKETS_SECONDS],
        default=(1, DEFAULT_SECONDS * SAMPLE_RATE),
    )
    fp16 = ct.convert(
        traced,
        inputs=[ct.TensorType(name="audio", shape=shapes, dtype=np.float32)],
        outputs=[ct.TensorType(name="logprobs", dtype=np.float32)],
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.macOS14,
        convert_to="mlprogram",
        compute_units=ct.ComputeUnit.CPU_ONLY,
    )
    config = cto.OptimizationConfig(
        global_config=cto.OpLinearQuantizerConfig(mode="linear_symmetric", dtype="int8", granularity="per_channel")
    )
    int8 = cto.linear_quantize_weights(fp16, config=config)
    int8.short_description = (
        "facebook/wav2vec2-lv-60-espeak-cv-ft (Apache-2.0), CTC log-posteriors over espeak IPA, for sound judging"
    )
    int8.save(out)
    canonicalise_spec(os.path.join(out, "Data", "com.apple.CoreML", "model.mlmodel"))
    canonicalise_manifest(os.path.join(out, "Manifest.json"))


def canonicalise_spec(path: str) -> None:
    spec = Model_pb2.Model()
    with open(path, "rb") as f:
        spec.ParseFromString(f.read())
    with open(path, "wb") as f:
        f.write(spec.SerializeToString(deterministic=True))


def canonicalise_manifest(path: str) -> None:
    with open(path) as f:
        manifest = json.load(f)
    ids = {old: str(uuid.uuid5(uuid.NAMESPACE_URL, "accent-mirror:" + item["path"]))
           for old, item in manifest["itemInfoEntries"].items()}
    manifest["itemInfoEntries"] = {ids[old]: item for old, item in manifest["itemInfoEntries"].items()}
    manifest["rootModelIdentifier"] = ids[manifest["rootModelIdentifier"]]
    with open(path, "w") as f:
        json.dump(manifest, f, indent=2, sort_keys=True)
        f.write("\n")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
