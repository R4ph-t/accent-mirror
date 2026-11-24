// Spec 28 §5: the inverse lookup spec 20's playhead uses is `TimeWarp.toYou` / `toModel` (no new API). Tests only.

import Foundation
import Testing
import AMCore
@testable import AMWarp

@Suite("Inverse lookup: toYou / toModel (spec 28 §5)") struct InverseLookupTests {
    static let hop = 0.01
    static let clamp = 0.05

    /// Model times every 5 ms inside each anchored (mapped) segment, keeping clear of the 50 ms clamp zone.
    static func anchoredModelTimes(_ warp: TimeWarp) -> [(segment: Int, t: Double)] {
        warp.map.segments.enumerated().flatMap { i, segment -> [(segment: Int, t: Double)] in
            guard case .mapped(let model, _, _, _) = segment else { return [] }
            let lo = model.start + clamp, hi = model.end - clamp
            guard lo < hi else { return [] }
            return stride(from: lo, through: hi, by: 0.005).map { (i, $0) }
        }
    }

    @Test("round trip within one hop on anchored spans, outside the 50 ms clamp zone") func roundTrip() throws {
        let warp = try Scene.warp()
        let times = Self.anchoredModelTimes(warp)
        #expect(times.count > 50)
        for (_, t) in times {
            let you = try #require(warp.toYou(t), "toYou(\(t))")
            let back = try #require(warp.toModel(you), "toModel(\(you))")
            #expect(abs(back - t) <= Self.hop, "\(t) → \(you) → \(back)")
        }
        // And from your side.
        for segment in warp.map.segments {
            guard case .mapped(_, let you, _, _) = segment else { continue }
            for t in stride(from: you.start + Self.clamp, through: you.end - Self.clamp, by: 0.005) {
                let model = try #require(warp.toModel(t))
                let back = try #require(warp.toYou(model))
                #expect(abs(back - t) <= Self.hop)
            }
        }
    }

    @Test("nil inside gaps, a missing word and an inserted word") func nilInGaps() throws {
        let warp = try Scene.warp()
        // Missing word b (model 0.60–0.90): no counterpart in your take.
        for t in stride(from: 0.61, through: 0.89, by: 0.01) { #expect(warp.toYou(t) == nil, "missing \(t)") }
        // Inserted "uh-huh" (yours 1.00–1.30): no model time.
        for t in stride(from: 1.01, through: 1.29, by: 0.01) { #expect(warp.toModel(t) == nil, "inserted \(t)") }
        // Between words on the model timeline (0.50–0.60 and 0.90–1.00), never bridged beyond the clamp.
        #expect(warp.toYou(0.56) == nil && warp.toYou(0.95) == nil)
    }

    @Test("monotonic on each side of a gap") func monotonicAroundGaps() throws {
        let warp = try Scene.warp()
        var bySegment: [Int: [(Double, Double)]] = [:]
        for (segment, t) in Self.anchoredModelTimes(warp) {
            bySegment[segment, default: []].append((t, try #require(warp.toYou(t))))
        }
        #expect(bySegment.count >= 3, "present, present, substituted segments either side of the gaps")
        for (_, points) in bySegment {
            for (a, b) in zip(points, points.dropFirst()) { #expect(b.1 >= a.1, "toYou is monotone") }
        }
        // Across a gap the mapping still increases: each mapped segment's your-side start follows the previous end.
        let mapped = warp.map.segments.compactMap { segment -> TimeRange? in
            if case .mapped(_, let you, _, _) = segment { you } else { nil }
        }
        for (a, b) in zip(mapped, mapped.dropFirst()) { #expect(b.start >= a.end) }
    }
}
