// Spec 27 §1: the features (all relative within the word), the L2-regularised logistic regression that scores each
// nucleus as "primary", and the abstaining decision. No absolute value, speaker id or reference recording is read.

import Foundation

/// Lit amendment 2's variants: with and without spectral tilt, phrase-residual f0 or no f0 (the ablation).
public enum Variant: String, Sendable, Hashable, Codable, CaseIterable {
    case tiltF0 = "tilt+f0"
    case f0Only = "f0"
    case tiltNoF0 = "tilt, no f0"
    case noTiltNoF0 = "no tilt, no f0"

    public var tilt: Bool { self == .tiltF0 || self == .tiltNoF0 }
    public var f0: Bool { self == .tiltF0 || self == .f0Only }
    /// Feature count, for the "simpler wins" tie-break.
    public var size: Int { Features.names(self).count }
}

public enum Features {
    public static func names(_ variant: Variant) -> [String] {
        var names = ["d/mean d", "e − mean e (dB)"]
        if variant.f0 { names.append("f0 residual − mean (st)") }
        if variant.tilt { names.append("tilt − mean (dB)") }
        names += ["rank d", "rank e"]
        if variant.f0 { names.append("rank f0 residual") }
        if variant.tilt { names.append("rank tilt") }
        names += ["N = 2", "N = 3", "N ≥ 4", "initial", "medial", "final"]
        return names
    }

    /// One row per nucleus of the word, in time order.
    public static func rows(_ nuclei: [MeasuredNucleus], variant: Variant) -> [[Double]] {
        let n = nuclei.count
        guard n >= 2 else { return [] }
        let d = nuclei.map(\.duration), e = nuclei.map(\.energyDB), t = nuclei.map(\.tiltDB)
        let meanD = d.reduce(0, +) / Double(n), meanE = e.reduce(0, +) / Double(n), meanT = t.reduce(0, +) / Double(n)
        let fAvailable = nuclei.compactMap(\.f0Residual)
        let meanF = fAvailable.isEmpty ? 0 : fAvailable.reduce(0, +) / Double(fAvailable.count)
        let f = nuclei.map { $0.f0Residual.map { $0 - meanF } ?? 0 }
        let rd = ranks(d), re = ranks(e), rf = ranks(f), rt = ranks(t)
        return (0..<n).map { k in
            var row = [meanD > 0 ? d[k] / meanD : 1, e[k] - meanE]
            if variant.f0 { row.append(f[k]) }
            if variant.tilt { row.append(t[k] - meanT) }
            row += [rd[k], re[k]]
            if variant.f0 { row.append(rf[k]) }
            if variant.tilt { row.append(rt[k]) }
            row += [n == 2 ? 1 : 0, n == 3 ? 1 : 0, n >= 4 ? 1 : 0]
            row += [k == 0 ? 1 : 0, k > 0 && k < n - 1 ? 1 : 0, k == n - 1 ? 1 : 0]
            return row
        }
    }

    /// Ranks scaled to 0…1 (0 lowest), ties averaged.
    static func ranks(_ values: [Double]) -> [Double] {
        let n = values.count
        guard n >= 2 else { return values.map { _ in 0.5 } }
        let order = values.indices.sorted { values[$0] < values[$1] }
        var out = [Double](repeating: 0, count: n)
        var i = 0
        while i < n {
            var j = i
            while j + 1 < n && values[order[j + 1]] == values[order[i]] { j += 1 }
            let rank = Double(i + j) / 2 / Double(n - 1)
            for k in i...j { out[order[k]] = rank }
            i = j + 1
        }
        return out
    }
}

/// L2-regularised logistic regression on standardised features (the intercept isn't penalised), fitted by Newton's
/// method (IRLS). Small and inspectable: its coefficients go in the report.
public struct LogisticModel: Sendable, Hashable, Codable {
    public let names: [String]
    public let mean: [Double]
    public let scale: [Double]
    /// Intercept first, then one weight per standardised feature.
    public let weights: [Double]
    public let lambda: Double

    public static let defaultLambda = 1.0

    public static func fit(_ x: [[Double]], _ y: [Bool], names: [String], lambda: Double = defaultLambda,
                           iterations: Int = 50) -> LogisticModel {
        let p = names.count
        let n = x.count
        var mean = [Double](repeating: 0, count: p), scale = [Double](repeating: 1, count: p)
        if n > 0 {
            for j in 0..<p { mean[j] = x.reduce(0) { $0 + $1[j] } / Double(n) }
            for j in 0..<p {
                let v = x.reduce(0) { $0 + ($1[j] - mean[j]) * ($1[j] - mean[j]) } / Double(n)
                scale[j] = v > 1e-12 ? sqrt(v) : 1
            }
        }
        let z = x.map { row in [1.0] + (0..<p).map { (row[$0] - mean[$0]) / scale[$0] } }
        var w = [Double](repeating: 0, count: p + 1)
        for _ in 0..<iterations {
            var gradient = [Double](repeating: 0, count: p + 1)
            var hessian = [[Double]](repeating: [Double](repeating: 0, count: p + 1), count: p + 1)
            for (row, label) in zip(z, y) {
                let mu = sigmoid(dot(w, row))
                let r = mu - (label ? 1 : 0)
                let s = max(mu * (1 - mu), 1e-9)
                for a in 0...p {
                    gradient[a] += r * row[a]
                    for b in a...p { hessian[a][b] += s * row[a] * row[b] }
                }
            }
            for a in 0...p { for b in 0..<a { hessian[a][b] = hessian[b][a] } }
            for a in 1...p { gradient[a] += lambda * w[a]; hessian[a][a] += lambda }
            hessian[0][0] += 1e-9
            guard let step = solve(hessian, gradient) else { break }
            var change = 0.0
            for a in 0...p { w[a] -= step[a]; change = max(change, abs(step[a])) }
            if change < 1e-9 { break }
        }
        return LogisticModel(names: names, mean: mean, scale: scale, weights: w, lambda: lambda)
    }

    public func probability(_ row: [Double]) -> Double {
        var s = weights[0]
        for j in 0..<names.count { s += weights[j + 1] * (row[j] - mean[j]) / scale[j] }
        return Self.sigmoid(s)
    }

    static func sigmoid(_ s: Double) -> Double { s >= 0 ? 1 / (1 + exp(-s)) : exp(s) / (1 + exp(s)) }
    static func dot(_ a: [Double], _ b: [Double]) -> Double { zip(a, b).reduce(0) { $0 + $1.0 * $1.1 } }

    /// Gaussian elimination with partial pivoting; nil when singular.
    static func solve(_ a: [[Double]], _ b: [Double]) -> [Double]? {
        var m = a, v = b
        let n = v.count
        for col in 0..<n {
            var pivot = col
            for r in col..<n where abs(m[r][col]) > abs(m[pivot][col]) { pivot = r }
            guard abs(m[pivot][col]) > 1e-12 else { return nil }
            m.swapAt(col, pivot); v.swapAt(col, pivot)
            for r in (col + 1)..<n {
                let f = m[r][col] / m[col][col]
                guard f != 0 else { continue }
                for c in col..<n { m[r][c] -= f * m[col][c] }
                v[r] -= f * v[col]
            }
        }
        var out = [Double](repeating: 0, count: n)
        for r in stride(from: n - 1, through: 0, by: -1) {
            var s = v[r]
            for c in (r + 1)..<n { s -= m[r][c] * out[c] }
            out[r] = s / m[r][r]
        }
        return out
    }
}

/// A fitted word-stress classifier: the variant and its model.
public struct StressClassifier: Sendable, Hashable, Codable {
    public let variant: Variant
    public let model: LogisticModel

    public init(variant: Variant, model: LogisticModel) {
        self.variant = variant
        self.model = model
    }

    /// P(primary) per nucleus, in time order.
    public func probabilities(_ nuclei: [MeasuredNucleus]) -> [Double] {
        Features.rows(nuclei, variant: variant).map(model.probability)
    }

    /// Fits on words whose `label` is the index of the nucleus that carries primary stress acoustically.
    public static func fit(_ words: [(nuclei: [MeasuredNucleus], label: Int)], variant: Variant,
                           lambda: Double = LogisticModel.defaultLambda) -> StressClassifier {
        var x: [[Double]] = []
        var y: [Bool] = []
        for word in words {
            for (k, row) in Features.rows(word.nuclei, variant: variant).enumerated() {
                x.append(row)
                y.append(k == word.label)
            }
        }
        return StressClassifier(variant: variant,
                                model: LogisticModel.fit(x, y, names: Features.names(variant), lambda: lambda))
    }
}

/// One word's outcome.
public enum WordVerdict: Sendable, Hashable, Codable, CustomStringConvertible {
    /// "Stress not on syllable k*": the predicted syllable differs from the target by a margin ≥ τ.
    case flag(Int)
    /// The predicted syllable is the target.
    case close
    /// Predicted ≠ target, margin under τ.
    case unsure
    case abstain(Abstention)

    public var isFlag: Bool { if case .flag = self { true } else { false } }
    public var isAbstain: Bool { if case .abstain = self { true } else { false } }

    public var description: String {
        switch self {
        case .flag(let k): "flag:\(k)"
        case .close: "close"
        case .unsure: "unsure"
        case .abstain(let reason): "abstain:\(reason.rawValue)"
        }
    }

    /// §1: flag only when the predicted syllable ≠ the target and its probability margin over the target is ≥ τ.
    public static func decide(probabilities p: [Double], target: Int, tau: Double) -> (WordVerdict, Int, Double) {
        var predicted = 0
        for k in p.indices where p[k] > p[predicted] { predicted = k }
        let margin = p[predicted] - p[target]
        if predicted == target { return (.close, predicted, 0) }
        return (margin >= tau - 1e-12 ? .flag(predicted) : .unsure, predicted, margin)
    }
}

public enum ROC {
    /// Area under the ROC curve (Mann–Whitney, ties half): P(score of a positive > score of a negative).
    public static func auc(positives: [Double], negatives: [Double]) -> Double? {
        guard !positives.isEmpty, !negatives.isEmpty else { return nil }
        let all = (positives.map { ($0, true) } + negatives.map { ($0, false) }).sorted { $0.0 < $1.0 }
        var rankSum = 0.0
        var i = 0
        while i < all.count {
            var j = i
            while j + 1 < all.count && all[j + 1].0 == all[i].0 { j += 1 }
            let rank = Double(i + j) / 2 + 1
            for k in i...j where all[k].1 { rankSum += rank }
            i = j + 1
        }
        let np = Double(positives.count), nn = Double(negatives.count)
        return (rankSum - np * (np + 1) / 2) / (np * nn)
    }
}
