#!/usr/bin/env python3
"""Accent Mirror worked examples: prominence, observed stress, contrast, weak length.
Commit-ready reference for ProminenceTests (spec 08). Pure Python 3, no dependencies.
Algorithm (plan v2 rev 4.1, section 2):
  d_i = ln(dur_i) - ln(lambda) if syllable i is lengthening-exposed (last syllable of the take
        or before a pause > 150 ms), else ln(dur_i)
  e_i = mean RMS dBFS floored at -60 ; p_i = peak F0 in st re speaker median (None if < 3 voiced frames)
  z_k,i = (x_k,i - mean_k) / max(sd_k, floor_k), population sd over the comparable syllables where k present
  P_i = sum(w_k z_k,i) / sum(w_k) over present features; w = (0.4, 0.3, 0.3); floors = (0.05, 1.0, 1.0)
  Placement (per word): primary = argmax P within the word; margin m = P(top) - P(second)
    conf = high if m >= tau_high else medium if m >= tau_med else low. A placement flag needs high
    confidence (section 3.3); a word with an exposed syllable therefore also needs high.
    Initial tau_med = 0.25, tau_high = 0.5 (tuned later).
  Contrast C = median(A over S) / median(A over U), A_i = dur_i * 10^(e_i/20), RAW durations
  (the discount applies to prominence only). Weak length W = median dur(U) / median dur(S).
"""
import math, statistics as st

W = {"d": 0.4, "e": 0.3, "p": 0.3}
FLOOR = {"d": 0.05, "e": 1.0, "p": 1.0}

def prominence(sylls, lam):
    feats = {"d": [], "e": [], "p": []}
    for s in sylls:
        d = math.log(s["dur"]) - (math.log(lam) if s.get("exposed") else 0.0)
        feats["d"].append(d); feats["e"].append(max(s["db"], -60.0)); feats["p"].append(s.get("p"))
    z = {}
    for k, xs in feats.items():
        pres = [x for x in xs if x is not None]
        if len(pres) < 2:
            z[k] = [None] * len(xs); continue
        m, sd = st.mean(pres), max(st.pstdev(pres), FLOOR[k])
        z[k] = [None if x is None else (x - m) / sd for x in xs]
    out = []
    for i in range(len(sylls)):
        num = sum(W[k] * z[k][i] for k in W if z[k][i] is not None)
        den = sum(W[k] for k in W if z[k][i] is not None)
        out.append(num / den)
    return out

def placement(P, idx, labels, exposed, tau_med=0.25, tau_high=0.5):
    sub = sorted(((P[i], i) for i in idx), reverse=True)
    m = sub[0][0] - sub[1][0]
    conf = "high" if m >= tau_high else "medium" if m >= tau_med else "low"
    flaggable = conf == "high"  # section 3.3: placement needs high stress confidence
    return labels[sub[0][1]], round(m, 2), conf, flaggable

def contrast(sylls, S, U):
    A = [s["dur"] * 10 ** (max(s["db"], -60) / 20) for s in sylls]
    C = st.median([A[i] for i in S]) / st.median([A[i] for i in U])
    Wl = st.median([sylls[i]["dur"] for i in U]) / st.median([sylls[i]["dur"] for i in S]) * 100
    return round(C, 2), round(Wl, 1)

def word(durs, dbs, ps, final=True):
    return [{"dur": d, "db": e, "p": p, "exposed": (final and i == len(durs) - 1)}
            for i, (d, e, p) in enumerate(zip(durs, dbs, ps))]

PH = ["pho", "tog", "ra", "phy"]
CASES = {
 "A model, 'photography' (take = the word)": word([.10, .20, .08, .12], [-24, -18, -27, -26], [1, 6, -1, -2]),
 "B you, stress on PHO":                     word([.20, .14, .10, .12], [-19, -22, -25, -25], [5, 2, 0, -1]),
 "C as B, 'ra' unvoiced":                    word([.20, .14, .10, .12], [-19, -22, -25, -25], [5, 2, None, -1]),
 "D flat take":                              word([.15] * 4, [-22] * 4, [0, .2, 0, -.2]),
}
# E: full sentence 'I love photography.'; normalisation over all 6 comparable syllables
E = [{"dur": .09, "db": -22, "p": 1}, {"dur": .20, "db": -18, "p": 3}] + \
    word([.10, .18, .08, .28], [-24, -21, -27, -20], [0, 2, -1, 1])
S, U = [1], [0, 2, 3]   # expected: tog stressed; pho, ra, phy unstressed (secondary on pho ignored for S here)

if __name__ == "__main__":
    for lam in (1.6, 1.0):
        print(f"=== lambda = {lam} ===")
        for name, sy in list(CASES.items()) + [("E native, 'I love photography.' (6 syllables)", E)]:
            P = prominence(sy, lam)
            idx = list(range(len(sy) - 4, len(sy)))
            ex = [s.get("exposed", False) for s in sy]
            pri, m, conf, fl = placement(P, idx, {i: PH[j] for j, i in enumerate(idx)}, ex)
            Cc, Wl = contrast(sy[-4:], S, U)
            print(f"{name}: P(word) = {[round(P[i], 2) for i in idx]}; primary {pri.upper()}, "
                  f"margin {m} ({conf}), flaggable={fl}; C = {Cc}, W = {Wl}%")
