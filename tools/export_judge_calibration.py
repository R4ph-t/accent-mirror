#!/usr/bin/env python3
"""Export the sound judge's per-phone calibration head (AMJudging/Resources/calibration.json).

Refits exactly what the judging spike's calibrate.py fitted: LogisticRegression(C=1.0, max_iter=3000) on the
speechocean762 TRAIN rows (lv60_so762train.*.json), features [max(gop, -20), one-hot over the 39 sorted ARPAbet
phones, gop_clipped * one-hot], label "phone accuracy <= 0.4". Composite units use their first member's phone.
Then checks the export reproduces the spike's th_f1_train (threshold 0.22; LibriSpeech native word flags 35/5,659).

Run with the spike's venv (scikit-learn 1.9.1, numpy):
    <spike>/.venv/bin/python tools/export_judge_calibration.py <spike-dir> [out.json]
Training data: speechocean762 (https://huggingface.co/datasets/mispeech/speechocean762), CC BY 4.0.
"""
import glob, json, os, re, sys
import numpy as np
from sklearn.linear_model import LogisticRegression

SPIKE = sys.argv[1]
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(
    os.path.dirname(os.path.abspath(__file__)), '..', 'Packages', 'AccentKit', 'Sources', 'AMJudging', 'Resources',
    'calibration.json')
PH = sorted('AA AE AH AO AW AY EH ER EY IH IY OW OY UH UW B CH D DH F G HH JH K L M N NG P R S SH T TH V W Y Z ZH'.split())


def load(name):
    rows = []
    for f in sorted(glob.glob(f'{SPIKE}/results/lv60_{name}.json')) + sorted(glob.glob(f'{SPIKE}/results/lv60_{name}.[0-9].json')):
        rows.extend(json.load(open(f))['rows'])
    return rows


def table(rows):
    X, acc, key = [], [], []
    for r in rows:
        for k, (members, g) in enumerate(zip(r['units'], r['gop'])):
            p = re.sub(r'\d', '', members[0][2])
            oh = np.zeros(len(PH)); oh[PH.index(p)] = 1; gc = max(g, -20)
            X.append(np.concatenate([[gc], oh, gc * oh])); key.append((r['id'], members[0][0]))
            if 'acc' in r: acc.append(min(r['acc'][k]))
    return np.array(X), np.array(acc), key


Xtr, atr, _ = table(load('so762train'))
clf = LogisticRegression(C=1.0, max_iter=3000).fit(Xtr, atr <= 0.4)
w = clf.coef_[0]; b = float(clf.intercept_[0])

# Threshold check, as calibrate.py: best phone F1 on train over the 0.02..0.98 grid.
ptr = clf.predict_proba(Xtr)[:, 1]; err = atr <= 0.4
def f1(t):
    f = ptr > t; tp = (f & err).sum(); P = tp / max(1, f.sum()); R = tp / err.sum(); return 2 * P * R / max(1e-9, P + R)
th = float(max(np.linspace(0.02, 0.98, 97), key=f1))
Xli, _, kli = table(load('libri'))
# P(error) = sigmoid(w.x + b), computed the way the Swift scorer does.
pli = 1 / (1 + np.exp(-(Xli @ w + b)))
words = {}
for k, f in zip(kli, pli > th): words[k] = words.get(k, False) or bool(f)
flagged, total = sum(words.values()), len(words)
print(f'train units {len(atr)}; th_f1_train {th:.2f}; LibriSpeech word flags {flagged}/{total}')
assert round(th, 2) == 0.22 and (flagged, total) == (35, 5659), 'does not reproduce results/lv60_calibrated.json'

out = {
    '_comment': ('Per-phone logistic calibration of segmentation-free GOP for wav2vec2-lv-60-espeak-cv-ft. '
                 'P(error) = sigmoid(intercept + sum(coefficients * x)), x = [max(gop, -20), one-hot(phones), '
                 'max(gop, -20) * one-hot(phones)]. Fitted by tools/export_judge_calibration.py '
                 '(LogisticRegression C=1.0, max_iter=3000) on speechocean762 train '
                 '(https://huggingface.co/datasets/mispeech/speechocean762, CC BY 4.0; label: phone accuracy <= 0.4).'),
    'source': 'speechocean762 train (CC BY 4.0)',
    'license': 'CC BY 4.0',
    'gopClip': -20.0,
    'phones': PH,
    'intercept': b,
    'coefficients': [float(x) for x in w],
    'trainUnits': int(len(atr)),
}
with open(OUT, 'w') as fh:
    json.dump(out, fh, indent=1); fh.write('\n')
print('wrote', OUT)
