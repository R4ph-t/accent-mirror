// Pitch range, shape match and final direction (spec 10; plan §1, §11; confidence from first v2 §5).
//
// Comparable frames are the model's voiced 10 ms frames whose centre lies in comparable model time (a `present`
// word's segment of the time map). Your frames are read on model time (`TimeWarp.pitchOnModel`). Voiced coverage =
// the share of comparable frames where your frame is voiced too; it is the confidence of every pitch measure.

import AMCore
import AMPlacement
import AMProsody
import AMWarp
import Foundation

/// The pitch measures of one pair.
struct PitchMeasures {
    var pitchRange: MeasureState<Double>
    var shapeMatch: MeasureState<Double>
    var finalDirection: MeasureState<Double>
    /// The model's own values, for diffs, the inspector and the tolerance gates.
    var modelPitchRange: Double?
    var modelFinal: FinalWindow
    /// Comparable voiced coverage, 0–1; nil with no comparable frame.
    var coverage: Double?

    init(_ input: ScoringInput, thresholds: Thresholds) {
        let hop = input.hopSeconds
        let confidence = thresholds.confidence
        modelFinal = FinalWindow(
            pitch: input.model.pitch, material: Array(input.model.words.values), hopSeconds: hop,
            thresholds: thresholds.finalDirection)

        // The model's comparable voiced frames, by model grid index, and yours on the same grid.
        var model: [Int: Double] = [:]
        for segment in input.model.pitch {
            let k0 = Int((segment.start / hop).rounded())
            for (j, frame) in segment.frames.enumerated() where frame.voiced {
                let k = k0 + j
                if input.warp.isComparable(modelTime: (Double(k) + 0.5) * hop) { model[k] = frame.semitones }
            }
        }
        var you: [Int: Double] = [:]
        for segment in input.warp.pitchOnModel(input.you.pitch, hopSeconds: hop) {
            let k0 = Int((segment.start / hop).rounded())
            for (j, frame) in segment.frames.enumerated() where frame.voiced {
                let k = k0 + j
                if input.warp.isComparable(modelTime: (Double(k) + 0.5) * hop) { you[k] = frame.semitones }
            }
        }
        let overlap = model.keys.filter { you[$0] != nil }.sorted()
        coverage = model.isEmpty ? nil : Double(overlap.count) / Double(model.count)
        modelPitchRange = Self.range(Array(model.values), thresholds: thresholds.band)

        let level: Confidence? = coverage.map {
            $0 >= confidence.pitchHigh ? .high : $0 >= confidence.pitchMedium ? .medium : .low
        }
        // Your take has no voiced frame at all: no pitch measure, and `close` is impossible.
        let gate: UnavailableReason? =
            input.you.voicedFrameCount == 0 ? .noVoicedFrames
            : model.isEmpty ? .coverageLow
            : level == .low ? .lowConfidence : nil

        if let gate {
            pitchRange = .unavailable(gate)
        } else if let yours = Self.range(Array(you.values), thresholds: thresholds.band) {
            pitchRange = .evaluated(yours, level!)
        } else {
            pitchRange = .unavailable(.noVoicedFrames)
        }

        let minimumOverlap = Int(thresholds.measures.shapeMatchMinOverlappingFrames)
        if input.you.voicedFrameCount == 0 {
            shapeMatch = .unavailable(.noVoicedFrames)
        } else if overlap.count < minimumOverlap {
            shapeMatch = .unavailable(.tooFewOverlappingFrames)
        } else if let r = Self.pearson(overlap.map { model[$0]! }, overlap.map { you[$0]! }) {
            shapeMatch = level == .low ? .unavailable(.lowConfidence) : .evaluated(r, level!)
        } else {
            // Either side flat: r is undefined, never 0.
            shapeMatch = .unavailable(.zeroVariance)
        }

        finalDirection = Self.yourFinal(input, thresholds: thresholds)
    }

    /// Your final direction: `.wordMissing` when the last phrase word is missing or substituted.
    static func yourFinal(_ input: ScoringInput, thresholds: Thresholds) -> MeasureState<Double> {
        if input.you.voicedFrameCount == 0 { return .unavailable(.noVoicedFrames) }
        if let last = input.words.last, input.status(of: last.index) != .present { return .unavailable(.wordMissing) }
        let window = FinalWindow(
            pitch: input.you.pitch, material: Array(input.you.words.values), hopSeconds: input.hopSeconds,
            thresholds: thresholds.finalDirection)
        guard let slope = window.slope else { return .unavailable(.lowConfidence) }
        let frames = Double(window.voicedFrames)
        let confidence = thresholds.confidence
        let level: Confidence = frames >= confidence.finalDirectionHighFrames ? .high
            : frames >= confidence.finalDirectionMediumFrames ? .medium : .low
        return level == .low ? .unavailable(.lowConfidence) : .evaluated(slope, level)
    }

    /// P90 − P10 in st (moved down to `PitchStatistics`, spec 28).
    static func range(_ values: [Double], thresholds: Thresholds.Band) -> Double? {
        PitchStatistics.range(values, thresholds: thresholds)
    }

    /// Pearson r; nil when either side has zero variance.
    static func pearson(_ x: [Double], _ y: [Double]) -> Double? {
        let n = Double(x.count)
        let mx = x.reduce(0, +) / n
        let my = y.reduce(0, +) / n
        var sxy = 0.0, sxx = 0.0, syy = 0.0
        for (a, b) in zip(x, y) {
            sxy += (a - mx) * (b - my)
            sxx += (a - mx) * (a - mx)
            syy += (b - my) * (b - my)
        }
        guard sxx > 1e-12, syy > 1e-12 else { return nil }
        return sxy / (sxx * syy).squareRoot()
    }
}
