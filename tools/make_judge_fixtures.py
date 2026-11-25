#!/usr/bin/env python3
"""Make AMJudging's parity fixtures (Packages/AccentKit/Tests/AMJudgingTests/Fixtures/*.json).

Each fixture holds a clip's words with every CMUdict variant (ARPAbet with stress digits), compact log-posteriors
(blank + the judge's English token columns, float16, base64; every other column is -1e4 when rebuilt) and the judging
spike's Python reference computed on exactly those rebuilt posteriors: the chosen variant per word, per unit its GOP
(spike gop.gop()), P(error) (tools/export_judge_calibration.py's head), flag (P > 0.22), strongest competitor when it
beats every acceptable form, and each unit's forced-alignment frames (torchaudio forced_align).

Starter clips (VCTK, CC BY 4.0) run through the spike's int8 Core ML model (CPU only), zero-padded to the smallest
input bucket (2, 4, 6, 8, 10 s) before normalisation. The speechocean762 clip (CC BY 4.0) uses the spike's stored
PyTorch posteriors and the dataset's canonical phones (its audio isn't kept).

Run with the judging spike's venv:  <spike>/.venv/bin/python tools/make_judge_fixtures.py <spike-dir>
"""
import base64, json, os, re, sys
import numpy as np

SPIKE = os.path.abspath(sys.argv[1])
sys.path.insert(0, os.path.join(SPIKE, 'scripts'))
import torch, soundfile as sf, librosa  # noqa: E402
from torchaudio.functional import forced_align  # noqa: E402
from gop import units, gop, ctc_ll, cmudict, ENG_IDS, VOCAB  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', 'Packages', 'AccentKit', 'Tests', 'AMJudgingTests', 'Fixtures')
CAL = json.load(open(os.path.join(HERE, '..', 'Packages', 'AccentKit', 'Sources', 'AMJudging', 'Resources', 'calibration.json')))
TH = 0.22
STARTER = ['p225_013', 'p233_013', 'p252_006', 'p225_002', 'p233_012']
SO762 = '0044_0056'
COLS = [0] + ENG_IDS
ID2TOK = {v: k for k, v in VOCAB.items()}


def p_error(g, phone):
    ph = CAL['phones']; k = ph.index(re.sub(r'\d', '', phone)); n = len(ph); w = CAL['coefficients']; g = max(g, -20)
    z = CAL['intercept'] + w[0] * g + w[1 + k] + w[1 + n + k] * g
    return 1 / (1 + np.exp(-z))


def compact(lp):
    """-> (base64 float16 of the kept columns, rebuilt full float32 matrix)."""
    kept = lp[:, COLS].astype(np.float16)
    full = np.full(lp.shape, -1e4, dtype=np.float32); full[:, COLS] = kept.astype(np.float32)
    return base64.b64encode(kept.astype('<f2').tobytes()).decode(), full


def competitors(lp, U, i):
    canon = [u[1][0] for u in U]; flat = lambda parts: [t for p in parts for t in p]
    acc = U[i][1]
    acc_ll = ctc_ll(lp, [flat(canon[:i] + [a] + canon[i + 1:]) for a in acc])
    others, ids = [], []
    for a in ENG_IDS:
        if [a] in acc: continue
        others.append(flat(canon[:i] + [[a]] + canon[i + 1:])); ids.append(a)
    if [] not in acc: others.append(flat(canon[:i] + canon[i + 1:])); ids.append(-1)
    if not others: return None
    ll = ctc_ll(lp, others); k = int(torch.argmax(ll))
    if float(ll[k]) > float(acc_ll.max()):
        return {'nothing': True} if ids[k] == -1 else {'sound': ID2TOK[ids[k]]}
    return None


def spans(lp, canon):
    al, _ = forced_align(lp[None], torch.tensor([canon]), blank=0); al = al[0].tolist()
    out = []; prev = 0
    for t, a in enumerate(al):
        if a != 0 and (a != prev or prev == 0):
            out.append([t, t])
        elif a != 0:
            out[-1][1] = t
        prev = a
    assert len(out) == len(canon)
    return out


def fixture(cid, source, text, words, variants, lp_full_np, b64, chosen_override=None):
    lp = torch.tensor(lp_full_np)
    if chosen_override is None:
        choice = [0] * len(words)
        build = lambda ch: units([(wi, j, p) for wi in range(len(words)) for j, p in enumerate(variants[wi][ch[wi]])], words)
        canon_ll = lambda ch: float(ctc_ll(lp, [[t for u in build(ch) for t in u[1][0]]])[0])
        best = canon_ll(choice)
        for wi in range(len(words)):
            for v in range(1, len(variants[wi])):
                c = choice.copy(); c[wi] = v; s = canon_ll(c)
                if s > best: best, choice = s, c
    else:
        choice = chosen_override
    U = units([(wi, j, p) for wi in range(len(words)) for j, p in enumerate(variants[wi][choice[wi]])], words)
    g = gop(lp, U)
    canon = [t for u in U for t in u[1][0]]
    sp = spans(lp, canon); k = 0; rows = []
    for i, (mem, acc) in enumerate(U):
        n = len(acc[0]); fr = [sp[k][0], sp[k + n - 1][1]]; k += n
        pe = float(p_error(g[i], mem[0][2]))
        rows.append({'word': mem[0][0], 'members': [m[1] for m in mem], 'phones': [m[2] for m in mem],
                     'gop': round(float(g[i]), 6), 'pError': round(pe, 6), 'flagged': bool(pe > TH),
                     'heardInstead': competitors(lp, U, i), 'frames': fr})
    return {'id': cid, 'source': source, 'text': text, 'frames': int(lp.shape[0]), 'vocabularySize': int(lp.shape[1]),
            'columns': [{'token': ID2TOK[c], 'id': c} for c in COLS], 'posteriorsFloat16Base64': b64,
            'words': [{'text': w, 'variants': [' '.join(v) for v in variants[i]]} for i, w in enumerate(words)],
            'chosenVariant': choice, 'units': rows}


def main():
    import coremltools as ct
    os.makedirs(OUT, exist_ok=True)
    d = cmudict()
    meta = {m['id']: m for m in json.load(open(f'{SPIKE}/box-headstart/lists/vctk_starter_meta.json'))}
    ml = ct.models.MLModel(f'{SPIKE}/models/lv60_int8.mlpackage', compute_units=ct.ComputeUnit.CPU_ONLY)
    for cid in STARTER:
        spk, utt = cid.split('_')
        y, sr = sf.read(f'{SPIKE}/data/starter/vctk-{utt}_{spk}.flac', dtype='float32')
        y = y.mean(1) if y.ndim > 1 else y
        y = librosa.resample(y, orig_sr=sr, target_sr=16000) if sr != 16000 else y
        bucket = next(b for b in (32000, 64000, 96000, 128000, 160000) if b >= len(y))
        x = np.pad(y, (0, bucket - len(y))); x = ((x - x.mean()) / np.sqrt(x.var() + 1e-7)).astype(np.float32)
        lp = ml.predict({'audio': x[None]})['logprobs'][0].astype(np.float32)
        b64, full = compact(lp)
        text = meta[cid]['text']
        words = re.findall(r"[a-z']+", text.lower().replace('’', "'"))
        variants = [d[w.strip("'")] for w in words]
        f = fixture(cid, 'VCTK starter (CC BY 4.0), lv60_int8 Core ML CPU, padded to %.0f s' % (bucket / 16000),
                    text, words, variants, full, b64)
        f['takeSeconds'] = round(len(y) / 16000, 4)
        json.dump(f, open(f'{OUT}/{cid}.json', 'w'), separators=(',', ':'))
        print(cid, f['frames'], 'frames', sum(u['flagged'] for u in f['units']), 'flags')
    # speechocean762: the spike's stored PyTorch posteriors and its scored units (dataset phones, CMUdict stress).
    row = next(r for i in range(4) for r in json.load(open(f'{SPIKE}/results/lv60_so762.{i}.json'))['rows'] if r['id'] == SO762)
    lp = np.load(f'{SPIKE}/lp/lv60/so762/{SO762}.npy').astype(np.float32)
    b64, full = compact(lp)
    words = row['words']; phones = [[] for _ in words]
    for u in row['units']:
        for wi, j, p in u: phones[wi].append(p)
    f = fixture(SO762, 'speechocean762 test (CC BY 4.0), spike PyTorch posteriors, dataset phones', ' '.join(words),
                words, [[p] for p in phones], full, b64, chosen_override=[0] * len(words))
    f['takeSeconds'] = round(lp.shape[0] * 0.02, 4)
    json.dump(f, open(f'{OUT}/{SO762}.json', 'w'), separators=(',', ':'))
    print(SO762, f['frames'], 'frames', sum(u['flagged'] for u in f['units']), 'flags')


if __name__ == '__main__':
    main()
