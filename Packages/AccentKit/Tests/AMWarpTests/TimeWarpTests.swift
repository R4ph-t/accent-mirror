import Foundation
import Testing
import AMCore
import AMPitch
@testable import AMWarp

func r(_ start: Double, _ end: Double) -> TimeRange { try! TimeRange(start: start, end: end) }

/// A word split into equal syllables.
func word(_ start: Double, _ end: Double, syllables: Int = 1, timing: TimingLevel = .good) -> TimedWord {
    let step = (end - start) / Double(syllables)
    return TimedWord(
        range: r(start, end), syllables: (0..<syllables).map { r(start + Double($0) * step, start + Double($0 + 1) * step) },
        timing: timing)
}

func w(_ i: Int) -> WordIndex { WordIndex(i) }

/// Phrase "a b c d e": a present (2 syllables), b missing, "uh-huh" inserted, c present, d substituted, e present.
enum Scene {
    static let model = [
        word(0.10, 0.50, syllables: 2), word(0.60, 0.90), word(1.00, 1.30, syllables: 3), word(1.40, 1.70),
        word(1.80, 2.00),
    ]
    static let you: [WordIndex: TimedWord] = [
        w(0): word(0.20, 0.80, syllables: 2), w(2): word(1.50, 1.80, syllables: 3),
        w(3): TimedWord(range: r(1.90, 2.30), timing: .good), w(4): word(2.35, 2.60),
    ]
    static let alignment = try! WordAlignment(pairs: [
        .present(phrase: w(0), you: r(0.20, 0.80)),
        .missing(phrase: w(1)),
        .inserted(heard: "uh-huh", you: r(1.00, 1.30), afterPhrase: w(0)),
        .present(phrase: w(2), you: r(1.50, 1.80)),
        .substituted(phrase: w(3), heard: "dee", you: r(1.90, 2.30)),
        .present(phrase: w(4), you: r(2.35, 2.60)),
    ])
    static func warp() throws -> TimeWarp { try TimeWarp(alignment: alignment, model: model, you: you, timing: .good) }
}

@Suite("Partial time map") struct TimeMapTests {
    @Test("Segments follow the alignment: mapped, modelOnly, youOnly, with syllable or edge anchors")
    func segmentKinds() throws {
        let warp = try Scene.warp()
        let s = warp.map.segments
        #expect(s.count == 6)
        guard case .mapped(let m0, let y0, let a0, true) = s[0] else { Issue.record("present"); return }
        #expect(m0 == r(0.10, 0.50) && y0 == r(0.20, 0.80))
        let expected: [(Double, Double)] = [(0.10, 0.20), (0.30, 0.50), (0.50, 0.80)]
        #expect(a0.count == 3)
        for (a, e) in zip(a0, expected) { #expect(abs(a.model - e.0) < 1e-12 && abs(a.you - e.1) < 1e-12) }
        #expect(s[1] == .modelOnly(model: r(0.60, 0.90)))
        #expect(s[2] == .youOnly(you: r(1.00, 1.30)))
        guard case .mapped(_, _, let a3, true) = s[3], case .mapped(_, _, let a4, false) = s[4] else {
            Issue.record("present, substituted"); return
        }
        #expect(a3.count == 4)
        #expect(a4 == [.init(model: 1.40, you: 1.90), .init(model: 1.70, you: 2.30)])
        // Comparable: the 2 + 3 + 1 syllables of the present words out of 8 model syllables.
        #expect(warp.comparableCoverage == 6.0 / 8.0)
        // Validation from spec 01 passes for the built map (it would have thrown), and round-trips.
        #expect(try PartialTimeMap(segments: s) == warp.map)
    }

    @Test("Anchors map exactly both ways, and the map is monotone") func anchorsExactAndMonotone() throws {
        let warp = try Scene.warp()
        for segment in warp.map.segments {
            guard case .mapped(_, _, let anchors, _) = segment else { continue }
            for a in anchors {
                #expect(abs(warp.toModel(a.you)! - a.model) < 1e-12)
                #expect(abs(warp.toYou(a.model)! - a.you) < 1e-12)
            }
        }
        var last = -Double.infinity
        for t in stride(from: 0.15, through: 2.65, by: 0.005) {
            guard let m = warp.toModel(t) else { continue }
            #expect(m >= last, "toModel(\(t))")
            last = m
        }
    }

    @Test("toModel is nil inside an insertion; toYou is nil inside a missing word; gaps are never bridged")
    func gaps() throws {
        let warp = try Scene.warp()
        #expect(warp.toModel(1.15) == nil)
        #expect(warp.toYou(0.75) == nil)
        // The pause between word a and the insertion, and between the missing word and c: a gap, not bridged.
        #expect(warp.toModel(0.90) == nil)
        #expect(warp.toYou(0.95) == nil)
        // Between c and d (adjacent mapped words, no gap between): linear across the pause.
        #expect(abs(warp.toModel(1.85)! - 1.35) < 1e-12)
        #expect(abs(warp.toYou(1.35)! - 1.85) < 1e-12)
    }

    @Test("Past either end: 40 ms clamps to the edge, 60 ms is nil, no extrapolation") func endClamp() throws {
        let warp = try Scene.warp()
        #expect(warp.toYou(2.04) == 2.60)
        #expect(warp.toYou(2.06) == nil)
        #expect(warp.toModel(2.64) == 2.00)
        #expect(warp.toModel(2.66) == nil)
        #expect(warp.toYou(0.06) == 0.20)
        #expect(warp.toYou(0.04) == nil)
        #expect(warp.toModel(0.16) == 0.10)
        #expect(warp.toModel(0.14) == nil)
    }

    @Test("Playback: a missing word plays the model only, an insertion yours only") func playback() throws {
        let warp = try Scene.warp()
        let pairs = Scene.alignment.pairs
        #expect(warp.playbackRange(word: pairs[1], speaker: .you) == nil)
        #expect(warp.playbackRange(word: pairs[1], speaker: .model) == r(0.60, 0.90))
        #expect(warp.playbackRange(word: pairs[2], speaker: .model) == nil)
        #expect(warp.playbackRange(word: pairs[2], speaker: .you) == r(1.00, 1.30))
        #expect(warp.playbackRange(word: pairs[0], speaker: .you) == r(0.20, 0.80))
        #expect(warp.playbackRange(word: pairs[0], speaker: .model) == r(0.10, 0.50))
        #expect(warp.playbackRange(word: pairs[4], speaker: .you) == r(1.90, 2.30))
    }

    @Test("A loop slice plays your mapped ranges inside it; only a missing word plays the model only")
    func loop() throws {
        let warp = try Scene.warp()
        let missingOnly = warp.loopPlayback(modelSlice: r(0.55, 0.95))
        #expect(missingOnly.modelOnly && missingOnly.you.isEmpty)
        // c, d and e are adjacent mapped words: one range of yours.
        let tail = warp.loopPlayback(modelSlice: r(1.00, 2.00))
        #expect(tail.you == [r(1.50, 2.60)])
        // a, then the missing b: a's part only.
        let head = warp.loopPlayback(modelSlice: r(0.30, 0.95))
        #expect(head.you.count == 1 && abs(head.you[0].start - 0.50) < 1e-12 && head.you[0].end == 0.80)
        // Across the missing word and the insertion: two separate ranges, never joined over the gap.
        #expect(warp.loopPlayback(modelSlice: r(0.10, 1.30)).you == [r(0.20, 0.80), r(1.50, 1.80)])
    }

    @Test("Overlapping word spans are clamped so the map stays valid") func overlapClamped() throws {
        let alignment = try WordAlignment(pairs: [
            .present(phrase: w(0), you: r(0.0, 0.5)), .present(phrase: w(1), you: r(0.45, 1.0)),
        ])
        let warp = try TimeWarp(
            alignment: alignment, model: [word(0.0, 0.4, syllables: 2), word(0.35, 0.8, syllables: 2)],
            you: [w(0): word(0.0, 0.5, syllables: 2), w(1): word(0.45, 1.0, syllables: 2)], timing: .good)
        #expect(warp.map.segments[1].modelRange == r(0.4, 0.8))
        #expect(warp.map.segments[1].yourRange == r(0.5, 1.0))
    }
}

@Suite("Pitch on model time") struct PitchOnModelTests {
    /// One unbroken line of yours over the whole take: frame k at 10 ms has value k / 100 st.
    static func yourLine(from start: Double, to end: Double) -> [PitchSegment] {
        let count = Int(((end - start) / 0.01).rounded())
        return [PitchSegment(start: start, frames: (0..<count).map { PitchFrame(semitones: Double($0) / 100, voiced: true) })]
    }

    @Test("Your pitch breaks at each gap and is never bridged across") func breaksAtGaps() throws {
        let warp = try Scene.warp()
        let out = warp.pitchOnModel(Self.yourLine(from: 0.0, to: 3.0), hopSeconds: 0.01)
        // a | (b missing, insertion) | c d e.
        #expect(out.count == 2)
        let missing = r(0.60, 0.90)
        for segment in out {
            let end = segment.start + Double(segment.frames.count) * 0.01
            #expect(!(segment.start < missing.end && end > missing.start), "segment \(segment.start)–\(end)")
        }
        // No model frame maps into the insertion: values stay off your 1.00–1.30 s frames.
        let values = out.flatMap(\.frames).map(\.semitones)
        #expect(!values.contains { $0 > 1.0 && $0 < 1.3 })
    }

    @Test("A break in your own line (a pause over 250 ms) breaks the mapped line") func breaksAtYourPause() throws {
        let alignment = try WordAlignment(pairs: [.present(phrase: w(0), you: r(0.0, 1.0))])
        let warp = try TimeWarp(
            alignment: alignment, model: [word(0.0, 1.0)], you: [w(0): word(0.0, 1.0)], timing: .good)
        let line = [
            PitchSegment(start: 0.0, frames: Array(repeating: PitchFrame(semitones: 1, voiced: true), count: 30)),
            PitchSegment(start: 0.6, frames: Array(repeating: PitchFrame(semitones: 2, voiced: true), count: 30)),
        ]
        let out = warp.pitchOnModel(line, hopSeconds: 0.01)
        #expect(out.count == 2)
        #expect(out.map(\.frames.count) == [30, 30])
    }

    @Test("Comparable frames skip gaps and substituted words") func comparable() throws {
        let warp = try Scene.warp()
        #expect(warp.isComparable(modelTime: 0.3))
        #expect(!warp.isComparable(modelTime: 0.75))  // missing
        #expect(!warp.isComparable(modelTime: 1.55))  // substituted
        #expect(!warp.isComparable(modelTime: 0.55))  // pause after a, before the gap
    }
}
