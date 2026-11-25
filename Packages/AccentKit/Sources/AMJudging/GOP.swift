// Segmentation-free GOP (after Cao et al.), a port of the spike's `gop()` / `gop_batched`. For each unit:
//   GOP = log Σ_{a ∈ acceptable} P(prefix·a·suffix) − log Σ_{a ∈ acceptable ∪ English substitutions ∪ deletion} P(…)
// where prefix and suffix are the rest of the canonical sequence. Every term is a full-utterance CTC likelihood.
//
// Speed-up over the spike's batched forward passes: the canonical sequence's forward (alpha) and backward (beta)
// passes are computed once. A prefix's alpha and a suffix's beta don't depend on what sits between them, so each
// term only recomputes the alternative's own ≤ 4 extended states across the frames and joins them to the suffix
// where every path enters its first label. Equal to the full computation (tested to 1e-6).

import Foundation

struct UnitScore: Sendable, Hashable {
    /// log posterior of the acceptable set, ≤ 0.
    let gop: Double
    /// The strongest non-acceptable term when it beats every acceptable one: a token id, or −1 for deletion.
    let competitor: Int?
}

enum GOP {
    static let deletion = -1

    static func score(units: [JudgingUnit], emissions e: Emissions, vocabulary: TokenVocabulary) -> [UnitScore] {
        let blankColumn = e.column(e.blank)
        let canonical = units.flatMap(\.canonical)
        let lattice = CTCLattice(labels: canonical, emissions: e, blankColumn: blankColumn)
        let english = vocabulary.englishIDs
        var starts: [Int] = []
        var position = 0
        for unit in units {
            starts.append(position)
            position += unit.canonical.count
        }
        var columns: [Int: [Double]] = [:]
        for id in english { columns[id] = e.column(id) }
        let shared = Shared(lattice: lattice, blankColumn: blankColumn, columns: columns, canonical: canonical)

        return units.indices.map { i in
            let unit = units[i]
            let p = starts[i], q = p + unit.canonical.count
            var acceptable: [Double] = []
            var bestOther = -Double.infinity
            var bestOtherID: Int?
            for alt in unit.acceptable { acceptable.append(shared.logLikelihood(replacing: p..<q, with: alt)) }
            var all = acceptable
            for id in english where !unit.acceptable.contains([id]) {
                let ll = shared.logLikelihood(replacing: p..<q, with: [id])
                all.append(ll)
                if ll > bestOther { bestOther = ll; bestOtherID = id }
            }
            if !unit.acceptable.contains([]) {
                let ll = shared.logLikelihood(replacing: p..<q, with: [])
                all.append(ll)
                if ll > bestOther { bestOther = ll; bestOtherID = deletion }
            }
            let num = logSumExp(acceptable)
            let gop = num - logSumExp(all)
            let beats = bestOtherID != nil && acceptable.allSatisfy { bestOther > $0 }
            return UnitScore(gop: gop.isFinite ? min(0, gop) : -.infinity, competitor: beats ? bestOtherID : nil)
        }
    }

    /// The canonical lattice plus the emission columns, shared by every term.
    struct Shared {
        let lattice: CTCLattice
        let blankColumn: [Double]
        let columns: [Int: [Double]]
        let canonical: [Int]

        /// log P(canonical[..<range.lower] + middle + canonical[range.upper...]).
        func logLikelihood(replacing range: Range<Int>, with middle: [Int]) -> Double {
            let T = lattice.frames
            guard T > 0 else { return -.infinity }
            let p = range.lowerBound, q = range.upperBound, n = canonical.count
            let m = middle.count
            // Prefix states in the canonical lattice: last prefix label 2p−1, blank after it 2p.
            let prefixBlank = 2 * p, prefixLabel = 2 * p - 1
            let prefixLast: Int? = p > 0 ? canonical[p - 1] : nil
            // Middle states: label k at 2k, blank after it at 2k+1; alpha over all frames.
            var mid = [[Double]](repeating: [Double](repeating: -.infinity, count: T), count: 2 * m)
            let midCols = middle.map { columns[$0] ?? [] }
            for t in 0..<T {
                for k in 0..<m {
                    let label = 2 * k, blank = 2 * k + 1
                    var v: Double
                    if t == 0 {
                        v = k == 0 && p == 0 ? 0 : -.infinity
                    } else {
                        v = mid[label][t - 1]
                        if k == 0 {
                            v = logAdd(v, lattice.alphaAt(t - 1, prefixBlank))
                            if let last = prefixLast, last != middle[0] { v = logAdd(v, lattice.alphaAt(t - 1, prefixLabel)) }
                        } else {
                            v = logAdd(v, mid[label - 1][t - 1])
                            if middle[k] != middle[k - 1] { v = logAdd(v, mid[label - 2][t - 1]) }
                        }
                    }
                    mid[label][t] = v == -.infinity ? v : v + midCols[k][t]
                    var bv = t > 0 ? logAdd(mid[blank][t - 1], mid[label][t - 1]) : -.infinity
                    if t == 0 { bv = -.infinity }
                    mid[blank][t] = bv == -.infinity ? bv : bv + blankColumn[t]
                }
            }
            // The two states before the suffix's first label: K−1 (a blank) and K−2 (a label, if any).
            func kMinus1(_ t: Int) -> Double { m > 0 ? mid[2 * m - 1][t] : lattice.alphaAt(t, prefixBlank) }
            let kMinus2Label: Int? = m > 0 ? middle[m - 1] : prefixLast
            func kMinus2(_ t: Int) -> Double {
                m > 0 ? mid[2 * m - 2][t] : (p > 0 ? lattice.alphaAt(t, prefixLabel) : -.infinity)
            }
            if q == n {  // no suffix: end in the last label or the final blank
                return logAdd(kMinus1(T - 1), kMinus2(T - 1))
            }
            let first = canonical[q], firstState = 2 * q + 1
            let skip = kMinus2Label.map { $0 != first } ?? false
            var total = -Double.infinity
            if m == 0 && p == 0 { total = lattice.betaAt(0, firstState) }  // the path starts on the suffix
            for t in 0..<(T - 1) {
                let into = skip ? logAdd(kMinus1(t), kMinus2(t)) : kMinus1(t)
                if into == -.infinity { continue }
                let rest = lattice.betaAt(t + 1, firstState)
                if rest == -.infinity { continue }
                total = logAdd(total, into + rest)
            }
            return total
        }
    }
}
