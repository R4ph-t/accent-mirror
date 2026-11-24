"""Converts facebook/wav2vec2-base-960h (Apache-2.0) to a Core ML package for spec 23's CTC aligner (b2).

Run only by scripts/fetch-ctc.sh, inside its pinned venv under the git-ignored .cache/. Never at app runtime.
Input: the upstream folder (config.json, model.safetensors, ...), already SHA-256 checked. Output: one .mlpackage
taking `audio` (1 x N float32, 16 kHz, zero-mean unit-variance) and returning `logits` (1 x T x 32, one frame per
320 samples). Float32 weights and compute, as the spec names.

Reproducible bytes, so the package can be SHA-256 pinned: the model spec is re-serialised deterministically (protobuf
otherwise writes its maps in a random order), and the package's Manifest.json, whose item identifiers coremltools
draws at random, is rewritten with identifiers derived from each item's path. The weights are already stable.
"""

import json
import os
import sys
import uuid

import coremltools as ct
import numpy as np
import torch
from coremltools.proto import Model_pb2
from transformers import Wav2Vec2ForCTC

MIN_SAMPLES = 4_000      # 0.25 s; shorter takes are zero-padded by the aligner
MAX_SAMPLES = 320_000    # 20 s, the recording cap (capture.recordingCapS)


class Logits(torch.nn.Module):
    def __init__(self, model):
        super().__init__()
        self.model = model

    def forward(self, audio):
        return self.model(audio).logits


def main(upstream: str, out: str) -> None:
    torch.manual_seed(0)
    model = Wav2Vec2ForCTC.from_pretrained(upstream, local_files_only=True, attn_implementation="eager").eval()
    example = torch.zeros(1, 16_000)
    traced = torch.jit.trace(Logits(model).eval(), example)
    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(name="audio", shape=(1, ct.RangeDim(MIN_SAMPLES, MAX_SAMPLES, 16_000)), dtype=np.float32)],
        outputs=[ct.TensorType(name="logits", dtype=np.float32)],
        compute_precision=ct.precision.FLOAT32,
        minimum_deployment_target=ct.target.macOS14,
        convert_to="mlprogram",
    )
    mlmodel.short_description = "facebook/wav2vec2-base-960h (Apache-2.0), CTC character logits, for forced alignment"
    mlmodel.save(out)
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
