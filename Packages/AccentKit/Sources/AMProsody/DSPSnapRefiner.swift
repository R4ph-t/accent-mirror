// dsp-snap-1 (spec 23, candidate b1): snaps each Whisper word boundary to the nearby voicing or intensity edge. No
// weights and no dependency: our own pYIN (spec 04) for voicing, and vDSP frame RMS for intensity.
//
// Frame k is the 10 ms cell [k·hop, (k+1)·hop), as in `PitchTrack` and spec 05. A frame belongs to a search window
// when its centre is inside it.
//
// - End: the later of the voicing offset (the end of the last voiced frame in the window, when the frame after it is
//   unvoiced and in the window) and the intensity offset (the first frame after the window's last local RMS peak
//   that is `intensityDropDB` below that peak).
// - Start, the mirror rule: the earlier of the voicing onset (the first voiced frame in the window, when the frame
//   before it is unvoiced and in the window) and the intensity onset (the frame after the last one, before the
//   window's first local RMS peak, that is `intensityDropDB` below that peak).
// - Neither found: the boundary stays where Whisper put it. `BoundarySearch` applies the clamps.

import Accelerate
import Foundation
import AMCore
import AMAlignment
import AMPitch

public struct DSPSnapRefiner: WordBoundaryRefiner {
    public static let aligner = "dsp-snap-1"

    public var id: String { Self.aligner }
    public let thresholds: Thresholds.WordBoundaries
    public let pitch: Thresholds.Pitch

    /// Frames of RMS between cancellation checks (far under 50 ms of work).
    static let cancellationCheckFrames = 1_000

    public init(thresholds: Thresholds.WordBoundaries = Thresholds.current.wordBoundaries,
                pitch: Thresholds.Pitch = Thresholds.current.pitch) {
        self.thresholds = thresholds
        self.pitch = pitch
    }

    /// Which rule set a boundary (spec 23, Open question 2: report the share each rule won).
    public enum Rule: String, Sendable, Codable, CaseIterable {
        /// Only the voicing edge was found, or it won.
        case voicing
        /// Only the intensity edge was found, or it won.
        case intensity
        /// Both were found at the same frame.
        case tie
        /// Neither was found: Whisper's time, clamped.
        case unchanged
    }

    /// The refined words and, per word, the rule that set its start and its end.
    public struct Snapped: Sendable, Equatable {
        public var words: [WordTimestamp]
        public var startRules: [Rule]
        public var endRules: [Rule]
    }

    public func refine(_ words: [WordTimestamp], samples: [Float], sampleRate: Double) async throws -> [WordTimestamp] {
        try await snap(words, samples: samples, sampleRate: sampleRate).words
    }

    public func snap(_ words: [WordTimestamp], samples: [Float], sampleRate: Double) async throws -> Snapped {
        try Task.checkCancellation()
        guard !words.isEmpty else { return Snapped(words: [], startRules: [], endRules: []) }
        let track = try await PYINTracker(thresholds: pitch).track(samples, sampleRate: sampleRate)
        let hopSamples = max(Int((sampleRate * pitch.hopMs / 1000).rounded()), 1)
        let hop = Double(hopSamples) / sampleRate
        let frames = Frames(
            voiced: Self.voicedFrames(track, count: samples.count / hopSamples),
            levelDB: try Self.levelsDB(samples, hopSamples: hopSamples),
            hop: hop)
        let drop = thresholds.intensityDropDB
        var startRules: [Rule] = [], endRules: [Rule] = []
        let refined = try BoundarySearch.refine(
            words, takeDuration: Double(samples.count) / sampleRate, windowSeconds: thresholds.snapWindowMs / 1000,
            findStart: { window in
                let (time, rule) = Self.pick(
                    voicing: frames.voicingOnset(in: window), intensity: frames.intensityOnset(in: window, dropDB: drop),
                    later: false)
                startRules.append(rule)
                return time
            },
            findEnd: { window in
                let (time, rule) = Self.pick(
                    voicing: frames.voicingOffset(in: window), intensity: frames.intensityOffset(in: window, dropDB: drop),
                    later: true)
                endRules.append(rule)
                return time
            })
        return Snapped(words: refined, startRules: startRules, endRules: endRules)
    }

    static func pick(voicing: Double?, intensity: Double?, later: Bool) -> (Double?, Rule) {
        switch (voicing, intensity) {
        case (nil, nil): return (nil, .unchanged)
        case (let v?, nil): return (v, .voicing)
        case (nil, let i?): return (i, .intensity)
        case (let v?, let i?):
            if v == i { return (v, .tie) }
            let voicingWins = later ? v > i : v < i
            return voicingWins ? (v, .voicing) : (i, .intensity)
        }
    }

    /// One flag per 10 ms frame: voiced (not bridged) in the pYIN track.
    static func voicedFrames(_ track: PitchTrack, count: Int) -> [Bool] {
        var voiced = [Bool](repeating: false, count: count)
        for segment in track.segments {
            let first = Int((segment.start / track.hopSeconds).rounded())
            for (k, frame) in segment.frames.enumerated() where frame.voiced && (0..<count).contains(first + k) {
                voiced[first + k] = true
            }
        }
        return voiced
    }

    /// Frame RMS in dBFS, 20·log10(RMS) of each frame's own samples (spec 05); silence reads −120.
    static func levelsDB(_ samples: [Float], hopSamples: Int) throws -> [Double] {
        let count = samples.count / hopSamples
        var levels: [Double] = []
        levels.reserveCapacity(count)
        try samples.withUnsafeBufferPointer { audio in
            for k in 0..<count {
                if k.isMultiple(of: cancellationCheckFrames) { try Task.checkCancellation() }
                let frame = UnsafeBufferPointer(rebasing: audio[(k * hopSamples)..<((k + 1) * hopSamples)])
                levels.append(20 * log10(max(Double(vDSP.rootMeanSquare(frame)), 1e-6)))
            }
        }
        return levels
    }
}

/// The take's per-frame voicing and level, and the edge rules over a search window.
struct Frames {
    let voiced: [Bool]
    let levelDB: [Double]
    let hop: Double

    /// Frames whose centre lies in the window.
    func indices(in window: BoundarySearch.Window) -> ClosedRange<Int>? {
        let first = max(Int((window.lower / hop - 0.5).rounded(.up)), 0)
        let last = min(Int((window.upper / hop - 0.5).rounded(.down)), voiced.count - 1)
        return first <= last ? first...last : nil
    }

    func voicingOffset(in window: BoundarySearch.Window) -> Double? {
        guard let range = indices(in: window), range.count >= 2 else { return nil }
        guard let last = range.dropLast().last(where: { voiced[$0] && !voiced[$0 + 1] }),
              !(last + 1...range.upperBound).contains(where: { voiced[$0] })
        else { return nil }
        return Double(last + 1) * hop
    }

    func voicingOnset(in window: BoundarySearch.Window) -> Double? {
        guard let range = indices(in: window), range.count >= 2 else { return nil }
        guard let first = range.dropFirst().first(where: { voiced[$0] && !voiced[$0 - 1] }),
              !(range.lowerBound..<first).contains(where: { voiced[$0] })
        else { return nil }
        return Double(first) * hop
    }

    /// Local maxima of the level strictly inside the window (both neighbours in it).
    func peaks(in range: ClosedRange<Int>) -> [Int] {
        guard range.count >= 3 else { return [] }
        return (range.lowerBound + 1..<range.upperBound).filter {
            levelDB[$0] > levelDB[$0 - 1] && levelDB[$0] >= levelDB[$0 + 1]
        }
    }

    func intensityOffset(in window: BoundarySearch.Window, dropDB: Double) -> Double? {
        guard let range = indices(in: window), let peak = peaks(in: range).last else { return nil }
        let floor = levelDB[peak] - dropDB
        guard let quiet = (peak + 1...range.upperBound).first(where: { levelDB[$0] < floor }) else { return nil }
        return Double(quiet) * hop
    }

    func intensityOnset(in window: BoundarySearch.Window, dropDB: Double) -> Double? {
        guard let range = indices(in: window), let peak = peaks(in: range).first else { return nil }
        let floor = levelDB[peak] - dropDB
        guard let quiet = (range.lowerBound...peak - 1).last(where: { levelDB[$0] < floor }) else { return nil }
        return Double(quiet + 1) * hop
    }
}
