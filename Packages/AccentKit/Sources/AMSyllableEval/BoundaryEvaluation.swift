// The spec 07 real-speech bar (Open question 1): segmenter syllable boundaries against MFA phone alignments
// syllabified by spec 06, with the first v2 bars and the calibration check. Local tooling only: never linked into the
// app, never run by CI or `make check`. Until spec 23 ships a refiner, the report prints these lines NOT EVALUATED.

import AMAlignment
import AMCore
import AMProsody
import Foundation

/// One MFA phone interval, in seconds.
public struct AlignedPhone: Sendable, Hashable, Codable {
    public let phone: String
    public let start: Double
    public let end: Double

    public init(phone: String, start: Double, end: Double) {
        self.phone = phone
        self.start = start
        self.end = end
    }
}

public enum MFASyllableReference {
    public enum Exclusion: Error, Equatable {
        /// MFA's phones for the word don't line up one-to-one with the dictionary pronunciation.
        case phoneCountMismatch(dictionary: Int, aligned: Int)
    }

    /// The word-internal syllable boundaries of one word: the start of the first MFA phone of each syllable after the
    /// first, with syllables taken from spec 06's syllabifier on the pronunciation the segmenter used. Matching by
    /// position keeps it independent of MFA's phone set (english_mfa phones aren't ARPAbet).
    public static func boundaries(
        pronunciation: Pronunciation, aligned: [AlignedPhone]
    ) throws(Exclusion) -> [Double] {
        guard aligned.count == pronunciation.phones.count else {
            throw .phoneCountMismatch(dictionary: pronunciation.phones.count, aligned: aligned.count)
        }
        var offset = 0
        var boundaries: [Double] = []
        for syllable in pronunciation.syllables.dropLast() {
            offset += syllable.phones.count
            boundaries.append(aligned[offset].start)
        }
        return boundaries
    }
}

/// One word-internal syllable boundary: the MFA reference against the segmenter's, with the confidence level of the
/// syllable that ends at it.
public struct BoundaryPair: Sendable, Hashable, Codable {
    public let reference: Double
    public let measured: Double
    public let level: Confidence

    public init(reference: Double, measured: Double, level: Confidence) {
        self.reference = reference
        self.measured = measured
        self.level = level
    }

    public var errorMs: Double { abs(measured - reference) * 1000 }

    /// The pairs of one segmented word against its MFA reference boundaries; nil when the counts differ.
    public static func pairs(word: SegmentedWord, reference: [Double]) -> [BoundaryPair]? {
        let measured = word.syllables.dropLast()
        guard measured.count == reference.count else { return nil }
        return zip(measured, reference).map { BoundaryPair(reference: $1, measured: $0.range.end, level: $0.level) }
    }
}

public enum GateStatus: String, Sendable, Hashable, Codable {
    case pass = "PASS"
    case fail = "FAIL"
    case notEvaluated = "NOT EVALUATED"
}

/// The MFA bar's three lines over a set of boundary pairs.
public struct BoundaryEvaluation: Sendable, Hashable, Codable {
    public let count: Int
    public let medianErrorMs: Double?
    public let withinToleranceShare: Double?
    /// Median error of boundaries after low-confidence syllables, and after medium or high ones.
    public let medianErrorLowMs: Double?
    public let medianErrorMediumOrHighMs: Double?

    public let median: GateStatus
    public let withinTolerance: GateStatus
    /// Low-confidence syllables must have the larger median error. Not evaluated when either group is empty.
    public let calibration: GateStatus

    public init(pairs: [BoundaryPair], bars: Thresholds.SyllableBoundaries = Thresholds.current.syllableBoundaries) {
        let errors = pairs.map(\.errorMs)
        count = pairs.count
        medianErrorMs = Self.median(errors)
        withinToleranceShare = errors.isEmpty
            ? nil : Double(errors.count { $0 <= bars.withinToleranceMs }) / Double(errors.count)
        medianErrorLowMs = Self.median(pairs.filter { $0.level == .low }.map(\.errorMs))
        medianErrorMediumOrHighMs = Self.median(pairs.filter { $0.level >= .medium }.map(\.errorMs))

        median = medianErrorMs.map { $0 <= bars.medianErrorMaxMs ? .pass : .fail } ?? .notEvaluated
        withinTolerance = withinToleranceShare.map { $0 >= bars.withinToleranceShareMin ? .pass : .fail } ?? .notEvaluated
        if let low = medianErrorLowMs, let rest = medianErrorMediumOrHighMs {
            calibration = low > rest ? .pass : .fail
        } else {
            calibration = .notEvaluated
        }
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
