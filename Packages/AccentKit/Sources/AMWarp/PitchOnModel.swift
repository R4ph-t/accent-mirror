// Your pitch on model time (plan §4.4): your line mapped through `toYou` on the model's 10 ms grid. It breaks at
// every missing or inserted word (never bridged across) and wherever your own line breaks (pauses over 250 ms,
// spec 04).

import Foundation
import AMCore
import AMPitch

extension TimeWarp {
    /// `track` (your pitch on your timeline) on model time.
    public func pitchOnModel(_ track: PitchTrack) -> [PitchSegment] {
        pitchOnModel(track.segments, hopSeconds: track.hopSeconds)
    }

    /// `segments` (10 ms frames on your timeline, frame `k` the cell `[start + k·hop, start + (k+1)·hop)`) on model
    /// time, on the same grid: each model cell takes your frame whose cell holds its mapped centre. A model cell with
    /// no mapped time, no frame of yours, or a gap or a break of your line since the previous cell starts a new
    /// segment.
    public func pitchOnModel(_ segments: [PitchSegment], hopSeconds hop: Double) -> [PitchSegment] {
        let mappedModel = map.segments.compactMap { s -> TimeRange? in
            if case .mapped(let model, _, _, _) = s { model } else { nil }
        }
        guard hop > 0, let first = mappedModel.first, let last = mappedModel.last else { return [] }
        let gaps = map.segments.filter { if case .mapped = $0 { false } else { true } }

        var out: [PitchSegment] = []
        var current: (start: Double, frames: [PitchFrame])?
        var previous: (model: Double, you: Double, segment: Int)?
        func close() {
            if let c = current, !c.frames.isEmpty { out.append(PitchSegment(start: c.start, frames: c.frames)) }
            current = nil
        }

        let kFirst = Int((first.start / hop).rounded(.down))
        let kLast = Int((last.end / hop).rounded(.up))
        guard kFirst <= kLast else { return [] }
        for k in kFirst...kLast {
            let t = (Double(k) + 0.5) * hop
            guard let y = toYou(t), let (s, frame) = Self.frame(at: y, in: segments, hop: hop) else {
                close()
                previous = nil
                continue
            }
            if let p = previous {
                let crossesGap = gaps.contains { gap in
                    if let r = gap.modelRange, r.start < t, r.end > p.model { return true }
                    if let r = gap.yourRange, r.start < y, r.end > p.you { return true }
                    return false
                }
                if crossesGap || s != p.segment { close() }
            }
            if current == nil { current = (Double(k) * hop, []) }
            current!.frames.append(frame)
            previous = (t, y, s)
        }
        close()
        return out
    }

    /// The pitch segment and frame whose cell holds `t`.
    static func frame(at t: Double, in segments: [PitchSegment], hop: Double) -> (Int, PitchFrame)? {
        for (s, segment) in segments.enumerated() {
            let j = Int(((t - segment.start) / hop).rounded(.down))
            if j >= 0, j < segment.frames.count { return (s, segment.frames[j]) }
        }
        return nil
    }
}
