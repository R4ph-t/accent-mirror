// Statistics for agreement reports (plan §6.5, §6.6): Wilson interval, exact McNemar, and clustered bootstraps with a
// seeded generator so every number in a report reproduces from the seed in the split manifest.

import Foundation

/// A closed interval of shares, with the label every report prints next to it.
public struct Interval: Sendable, Hashable, Codable {
    public let lower: Double
    public let upper: Double
    /// How the interval was computed, for example "descriptive (ignores clustering)".
    public let label: String

    public init(lower: Double, upper: Double, label: String) {
        self.lower = lower
        self.upper = upper
        self.label = label
    }
}

public enum Statistics {
    /// The label printed with every Wilson interval.
    public static let wilsonLabel = "descriptive (ignores clustering)"

    /// The 95% Wilson score interval for `successes` out of `n`. Always printed as descriptive: it ignores clustering.
    public static func wilson(successes: Int, n: Int, z: Double = 1.959_963_984_540_054) -> Interval {
        precondition(n > 0 && successes >= 0 && successes <= n, "wilson needs 0 ≤ successes ≤ n, n > 0")
        let nn = Double(n)
        let p = Double(successes) / nn
        let z2 = z * z
        let centre = (p + z2 / (2 * nn)) / (1 + z2 / nn)
        let half = z * (p * (1 - p) / nn + z2 / (4 * nn * nn)).squareRoot() / (1 + z2 / nn)
        return Interval(lower: max(0, centre - half), upper: min(1, centre + half), label: wilsonLabel)
    }

    /// Exact two-sided McNemar test: `b` = detector right and baseline wrong, `c` = the reverse. Returns the
    /// two-sided binomial p-value under p = 0.5 over the b + c discordant pairs (capped at 1).
    public static func mcnemarExact(b: Int, c: Int) -> Double {
        precondition(b >= 0 && c >= 0)
        let n = b + c
        guard n > 0 else { return 1 }
        let k = min(b, c)
        // log-space binomial tail, exact enough for any n a report sees.
        var tail = 0.0
        for i in 0...k {
            tail += exp(logChoose(n, i) - Double(n) * log(2.0))
        }
        return min(1, 2 * tail)
    }

    static func logChoose(_ n: Int, _ k: Int) -> Double {
        lgamma(Double(n + 1)) - lgamma(Double(k + 1)) - lgamma(Double(n - k + 1))
    }

    /// The value at quantile `q` of `sorted` (linear interpolation between order statistics).
    public static func quantile(_ sorted: [Double], _ q: Double) -> Double {
        precondition(!sorted.isEmpty)
        let position = q * Double(sorted.count - 1)
        let low = Int(position.rounded(.down))
        let high = min(low + 1, sorted.count - 1)
        let weight = position - Double(low)
        return sorted[low] * (1 - weight) + sorted[high] * weight
    }
}

/// SplitMix64: a small, fully specified generator, so a seed reproduces the same resamples on every machine.
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A uniform index in `0..<count`.
    mutating func index(below count: Int) -> Int {
        Int(next() % UInt64(count))
    }
}

/// One scored unit for a bootstrap: which speaker and phrase it belongs to, and its outcome(s).
public struct BootstrapUnit: Sendable, Hashable {
    public let speaker: String
    /// Phrase (or utterance text); ignored by the speaker-clustered bootstrap.
    public let phrase: String
    /// The phrase cluster the two-way bootstrap resamples: the phrase itself, or a sub-phrase's source prompt
    /// (spec 24), so sub-phrases of one prompt are drawn together.
    public let phraseCluster: String
    /// 1 for a hit, 0 for a miss (detector).
    public let value: Double
    /// The paired comparison value (for example the best baseline's hit), when the bootstrap is paired.
    public let paired: Double

    public init(speaker: String, phrase: String = "", phraseCluster: String? = nil, value: Double, paired: Double = 0) {
        self.speaker = speaker
        self.phrase = phrase
        self.phraseCluster = phraseCluster ?? phrase
        self.value = value
        self.paired = paired
    }
}

/// Clustered percentile bootstraps (§6.6). Two-way for the VCTK positive set (speakers and phrases resampled
/// independently), speaker-clustered for speechocean762. 95% intervals from the 2.5th and 97.5th percentiles.
public enum ClusteredBootstrap {
    public enum Clustering: String, Sendable, Codable {
        case speakers
        case speakersAndPhrases
    }

    /// The bootstrap distribution of `statistic` over resamples. `statistic` receives the multiset of units drawn
    /// (each unit repeated by its cluster weight) as parallel arrays of values and weights.
    static func distribution(
        units: [BootstrapUnit], clustering: Clustering, resamples: Int, seed: UInt64,
        statistic: ([BootstrapUnit], [Double]) -> Double?
    ) -> [Double] {
        precondition(!units.isEmpty && resamples > 0)
        var generator = SeededGenerator(seed: seed)
        let speakers = Array(Set(units.map(\.speaker))).sorted()
        let phrases = Array(Set(units.map(\.phraseCluster))).sorted()
        let speakerIndex = Dictionary(uniqueKeysWithValues: speakers.enumerated().map { ($1, $0) })
        let phraseIndex = Dictionary(uniqueKeysWithValues: phrases.enumerated().map { ($1, $0) })
        var results: [Double] = []
        results.reserveCapacity(resamples)
        for _ in 0..<resamples {
            var speakerCount = [Double](repeating: 0, count: speakers.count)
            for _ in speakers.indices { speakerCount[generator.index(below: speakers.count)] += 1 }
            var phraseCount = [Double](repeating: 1, count: phrases.count)
            if clustering == .speakersAndPhrases {
                phraseCount = [Double](repeating: 0, count: phrases.count)
                for _ in phrases.indices { phraseCount[generator.index(below: phrases.count)] += 1 }
            }
            let weights = units.map { speakerCount[speakerIndex[$0.speaker]!] * phraseCount[phraseIndex[$0.phraseCluster]!] }
            if let value = statistic(units, weights) { results.append(value) }
        }
        return results.sorted()
    }

    /// The 95% percentile interval of the weighted mean of `value`.
    public static func meanInterval(
        units: [BootstrapUnit], clustering: Clustering, resamples: Int, seed: UInt64
    ) -> Interval {
        let values = distribution(units: units, clustering: clustering, resamples: resamples, seed: seed) { units, weights in
            weightedMean(units.map(\.value), weights)
        }
        return Interval(
            lower: Statistics.quantile(values, 0.025), upper: Statistics.quantile(values, 0.975),
            label: label(clustering, resamples: resamples))
    }

    /// The 95% percentile interval of the paired difference mean(value) − mean(paired), resampled together.
    public static func pairedDifferenceInterval(
        units: [BootstrapUnit], clustering: Clustering, resamples: Int, seed: UInt64
    ) -> Interval {
        let values = distribution(units: units, clustering: clustering, resamples: resamples, seed: seed) { units, weights in
            guard let d = weightedMean(units.map(\.value), weights),
                let b = weightedMean(units.map(\.paired), weights)
            else { return nil }
            return d - b
        }
        return Interval(
            lower: Statistics.quantile(values, 0.025), upper: Statistics.quantile(values, 0.975),
            label: "paired " + label(clustering, resamples: resamples))
    }

    static func label(_ clustering: Clustering, resamples: Int) -> String {
        switch clustering {
        case .speakers: "speaker-clustered bootstrap, \(resamples) resamples"
        case .speakersAndPhrases: "two-way clustered bootstrap (speakers × source prompts), \(resamples) resamples"
        }
    }

    static func weightedMean(_ values: [Double], _ weights: [Double]) -> Double? {
        let total = weights.reduce(0, +)
        guard total > 0 else { return nil }
        return zip(values, weights).reduce(0) { $0 + $1.0 * $1.1 } / total
    }
}
