// The native band (plan §9.2): P10–P90 in semitones per frame of the selected voice's timeline, across the native
// takes each warped onto that voice; ±1.5 st around the model with one take. It is L2: a voice switch rebuilds it on
// the new voice. It never contains the test speaker.

import Foundation
import AMCore
import AMPitch

/// One native take: its audio's SHA-256 and its pitch on its own timeline.
public struct NativeVoice: Sendable, Hashable {
    public let sha256: String
    public let pitch: [PitchSegment]

    public init(sha256: String, pitch: [PitchSegment]) {
        self.sha256 = sha256
        self.pitch = pitch
    }

    public init(sha256: String, track: PitchTrack) {
        self.init(sha256: sha256, pitch: track.segments)
    }
}

/// A native take with its warp onto the selected voice (the take is "you", the selected voice is the model).
public struct WarpedVoice: Sendable, Hashable {
    public let voice: NativeVoice
    public let ontoSelected: TimeWarp

    public init(voice: NativeVoice, ontoSelected: TimeWarp) {
        self.voice = voice
        self.ontoSelected = ontoSelected
    }
}

public struct NativeBand: Sendable, Hashable {
    /// One point per frame of the selected voice's 10 ms grid that any take covers, in time order.
    public let points: [BandPoint]
    /// The SHA-256s of the takes used, sorted.
    public let takeHashes: [String]
    /// SHA-256 of the sorted take hashes, one per line: `AnalysisIdentity.nativeSetHash`.
    public let nativeSetHash: String
    public let hopSeconds: Double

    public enum BuildError: Error, Equatable {
        /// The take under test is one of the native takes; the band never contains the test speaker.
        case testTakeInNativeSet(String)
    }

    /// Builds the band on `selected`'s timeline from it and `others`, each warped onto it.
    ///
    /// - Parameter testTake: the SHA-256 of the take the band will be compared against; throws when it is one of
    ///   the native takes.
    public init(
        selected: NativeVoice, others: [WarpedVoice], testTake: String?,
        hopSeconds hop: Double = Thresholds.current.pitch.hopMs / 1000,
        thresholds: Thresholds.Band = Thresholds.current.band
    ) throws {
        let hashes = ([selected.sha256] + others.map(\.voice.sha256)).sorted()
        if let testTake, hashes.contains(testTake) { throw BuildError.testTakeInNativeSet(testTake) }
        let lines = [selected.pitch] + others.map { $0.ontoSelected.pitchOnModel($0.voice.pitch, hopSeconds: hop) }

        var values: [Int: [Double]] = [:]
        for line in lines {
            for segment in line {
                let k0 = Int((segment.start / hop).rounded())
                for (j, frame) in segment.frames.enumerated() { values[k0 + j, default: []].append(frame.semitones) }
            }
        }
        let half = thresholds.singleTakeHalfWidthSemitones
        points = values.keys.sorted().map { k in
            let v = values[k]!.sorted()
            let time = Double(k) * hop
            guard v.count > 1 else { return BandPoint(time: time, lower: v[0] - half, upper: v[0] + half) }
            return BandPoint(
                time: time, lower: Self.percentile(v, thresholds.lowerPercentile),
                upper: Self.percentile(v, thresholds.upperPercentile))
        }
        takeHashes = hashes
        nativeSetHash = SHA256Digest.hex(of: Data(hashes.joined(separator: "\n").utf8))
        hopSeconds = hop
    }

    /// Linear-interpolated percentile `p` (0–100) of sorted values.
    static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        let position = p / 100 * Double(sorted.count - 1)
        let lo = Int(position.rounded(.down))
        let hi = min(lo + 1, sorted.count - 1)
        return sorted[lo] + (position - Double(lo)) * (sorted[hi] - sorted[lo])
    }

    /// Band coverage for one pair: the share of your comparable voiced frames on model time (`youOnModel`, from
    /// `warp.pitchOnModel`) that lie inside the band. A frame with no band point counts as outside. Nil with no
    /// comparable voiced frame.
    public func coverage(of youOnModel: [PitchSegment], warp: TimeWarp) -> Double? {
        let band = Dictionary(points.map { (Int(($0.time / hopSeconds).rounded()), $0) }, uniquingKeysWith: { a, _ in a })
        var total = 0
        var inside = 0
        for segment in youOnModel {
            let k0 = Int((segment.start / hopSeconds).rounded())
            for (j, frame) in segment.frames.enumerated() where frame.voiced {
                let k = k0 + j
                guard warp.isComparable(modelTime: (Double(k) + 0.5) * hopSeconds) else { continue }
                total += 1
                if let p = band[k], p.lower <= frame.semitones, frame.semitones <= p.upper { inside += 1 }
            }
        }
        return total > 0 ? Double(inside) / Double(total) : nil
    }
}
