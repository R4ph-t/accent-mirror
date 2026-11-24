import AMCore
import AMPlacement
import AMProsody
import Foundation
import Testing
@testable import AMScoring

typealias S = PairBuilder.Syllable

func kinds(_ decision: Decision) -> [DiffKind] {
    if case .verdict(.feedback(let rows, _)) = decision { return rows.map(\.kind) }
    return []
}

@Suite("Suppression (§5)") struct SuppressionTests {
    @Test("placement: your stress confidence below high gives no diff") func yourStressBelowHigh() throws {
        // B's mismatch on PHO, with every syllable at medium: stress confidence is capped at medium.
        let you = Pairs.syllables([0.20, 0.14, 0.10, 0.12], [-19, -22, -25, -25], [5, 2, 0, -1], level: .medium)
        let scoring = try Pairs.photography(you: you).score()
        let word = try #require(scoring.placements.first)
        #expect(word.mismatch && !word.flagged)
        #expect([.exposedSyllable, .stressConfidenceBelowHigh].contains(word.suppression))
        #expect(!kinds(scoring.decision).contains(.placement))
    }

    @Test("placement: low syllable confidence gives no diff") func lowSyllableConfidence() throws {
        let you = Pairs.syllables([0.20, 0.14, 0.10, 0.12], [-19, -22, -25, -25], [5, 2, 0, -1], level: .low)
        let word = try #require(try Pairs.photography(you: you).score().placements.first)
        #expect(word.mismatch && word.suppression == .lowSyllableConfidence)
    }

    @Test("placement: low stress confidence on the model's side gives no diff") func modelStressLow() throws {
        var pair = Pairs.photography(you: Pairs.b)
        pair.model = .init(syllables: [Pairs.d])  // flat: TOG by 0.06, low
        let scoring = try pair.score()
        let word = try #require(scoring.placements.first)
        #expect(word.mismatch && word.suppression == .modelStressConfidenceLow)
        #expect(!kinds(scoring.decision).contains(.placement))
    }

    @Test("placement: a referenceAnomaly model gives no diff") func referenceAnomaly() throws {
        var pair = Pairs.photography(you: Pairs.b)
        pair.model = .init(syllables: [Pairs.b])  // the model's own primary (PHO) is outside A(w) at high
        let scoring = try pair.score()
        let word = try #require(scoring.placements.first)
        #expect(word.referenceAnomaly && word.suppression == .referenceAnomaly)
        #expect(scoring.stress.first?.referenceAnomaly == true)
        #expect(!kinds(scoring.decision).contains(.placement))
    }

    @Test("placement: an expectedAmbiguous word is never decided") func expectedAmbiguous() throws {
        var pair = Pairs.photography(you: Pairs.b)
        pair = PairBuilder(
            words: [PairBuilder.Word(text: "photography", arpabet: "F AH0 T AA1 G R AH0 F IY0", isTarget: true, ambiguous: true)],
            model: pair.model, you: pair.you)
        let scoring = try pair.score()
        #expect(scoring.placements.isEmpty)
        #expect(scoring.measures[.stressPlacement] == .notApplicable(.noEligibleWord))
        #expect(scoring.stress.first?.expectedPattern == nil)
        #expect(scoring.decision == .verdict(.inconclusive([.noApplicableStressMeasure])))
    }

    @Test("contrast, weak length, too much contrast: no diff at low measure confidence") func contrastLowConfidence() throws {
        // D would trigger contrast and weak length; I and love at low make S∪U 4 of 6 at medium or above.
        let scoring = try Pairs.iLovePhotography(you: Pairs.d, lead: .low, timing: .good).score()
        for kind in [MeasureKind.contrast, .tooMuchContrast, .weakLength] {
            #expect(scoring.measures[kind] == .unavailable(.lowConfidence), "\(kind)")
        }
        #expect(!scoring.diffs.contains { [.contrast, .weakLength, .tooMuchContrast].contains($0.kind) })
    }

    @Test("pitch range, final direction, shape match: no diff and no close at low coverage") func pitchLowConfidence() throws {
        // You voice only the first of each syllable's frames' worth: coverage well under 0.5.
        let you: [[S]] = [[S(0.24, -18, (4, 1)), S(0.28, -26, nil)]]
        var pair = Pairs.record(you: you[0])
        pair.you.syllables = you
        let scoring = try pair.score()
        #expect(try #require(scoring.pitchCoverage) < 0.5)
        #expect(scoring.measures[.pitchRange] == .unavailable(.lowConfidence))
        #expect(scoring.measures[.shapeMatch].value == nil)
        #expect(scoring.decision != .verdict(.close))
    }

    @Test("poor timing: no stress, contrast or weak-length diffs; inconclusive(.timingUnreliable)") func poorTiming() throws {
        var pair = Pairs.photography(you: Pairs.b)
        pair.you.timing = .poor
        let scoring = try pair.score()
        #expect(!scoring.diffs.contains { [.placement, .contrast, .weakLength, .tooMuchContrast].contains($0.kind) })
        #expect(scoring.placements.first?.suppression == .timingPoor)
        #expect(scoring.decision == .verdict(.inconclusive([.timingUnreliable])))
    }
}

@Suite("Triggers, ranking and the 3-row cap") struct RankingTests {
    @Test("B vs A: placement, contrast, weak length, in that order") func placementFirst() throws {
        let scoring = try Pairs.photography(you: Pairs.b).score()
        #expect(kinds(scoring.decision) == [.placement, .contrast, .weakLength])
        let row = try #require(scoring.diffs.first)
        #expect(row.word == WordIndex(0) && row.acceptedSyllable == 1 && row.heardSyllable == 0)
        #expect(row.syllables == [1, 0])  // indices into the model's syllables: accepted, then heard
    }

    @Test("ranking order: placement, contrast, weak length, pitch range, final direction, too much contrast")
    func order() {
        let shuffled: [DiffKind] = [.tooMuchContrast, .finalDirection, .pitchRange, .weakLength, .contrast, .placement]
        let ranked = Scorer.rank(shuffled.map { TriggeredDiff(row: DiffRow(kind: $0), relativeGap: 0.1) })
        #expect(ranked.map(\.kind) == [.placement, .contrast, .weakLength, .pitchRange, .finalDirection, .tooMuchContrast])
    }

    @Test("ties within a kind go to the larger relative gap") func ties() {
        let small = TriggeredDiff(row: DiffRow(kind: .placement, word: WordIndex(0)), relativeGap: 0.5)
        let large = TriggeredDiff(row: DiffRow(kind: .placement, word: WordIndex(1)), relativeGap: 1.5)
        #expect(Scorer.rank([small, large]).map(\.word) == [WordIndex(1), WordIndex(0)])
    }

    @Test("the rough-timing row comes first and counts toward 3") func roughTimingCounts() throws {
        var pair = Pairs.photography(you: Pairs.b)
        pair.you.timing = .rough
        #expect(kinds(try pair.score().decision) == [.roughTiming, .placement, .contrast])
    }

    @Test("too much contrast never displaces a higher row") func tooMuchContrastLast() throws {
        let measures = try Pairs.photography(you: Pairs.b).score().measures
        let triggered: [DiffKind] = [.tooMuchContrast, .placement, .contrast, .weakLength]
        let rows = Scorer.rank(triggered.map { TriggeredDiff(row: DiffRow(kind: $0), relativeGap: 9) })
        for (timing, expected) in [(TimingLevel.good, [DiffKind.placement, .contrast, .weakLength]),
                                   (.rough, [.roughTiming, .placement, .contrast])] {
            let decision = decide(DecisionInput(
                alignment: AlignmentSummary(matchShare: 1), timing: timing, comparableCoverage: 1, measures: measures,
                triggeredDiffs: rows))
            #expect(kinds(decision) == expected)
        }
        // Over-stressed alone: it shows, since fewer than 3 higher rows fired.
        #expect(kinds(try Pairs.photography(you: Pairs.over).score().decision) == [.tooMuchContrast])
    }

    @Test("one placement row per phrase: the most prominent mismatch, every mismatching word flagged") func onePlacementRow() throws {
        let w = Pairs.photographyWord
        let pair = PairBuilder(
            words: [w, w], model: .init(syllables: [Pairs.a, Pairs.a]), you: .init(syllables: [Pairs.b, Pairs.b]))
        let scoring = try pair.score()
        #expect(scoring.placements.filter(\.flagged).count == 2)
        let rows = scoring.diffs.filter { $0.kind == .placement }
        #expect(rows.count == 1)
        let margins = Dictionary(uniqueKeysWithValues: scoring.placements.map { ($0.word, $0.yours.margin) })
        #expect(margins[rows[0].word!] == margins.values.max())
    }

    @Test("an enabled flag off keeps the measure and drops its diff") func enabledFlags() throws {
        var thresholds = Thresholds.current
        thresholds.diffs.weakLengthEnabled = false
        thresholds.diffs.pitchRangeEnabled = false
        let scoring = try Pairs.photography(you: Pairs.d).score(thresholds: thresholds)
        #expect(scoring.measures[.weakLength].value == 100)
        #expect(kinds(scoring.decision) == [.contrast])
        thresholds.diffs.finalDirectionEnabled = false
        let rise = try Pairs.whoDidYouGiveItTo(final: Pairs.risingFinal).score(thresholds: thresholds)
        #expect(rise.measures[.finalDirection].value == 7)
        #expect(rise.diffs.isEmpty)
    }

    @Test("rows never name a banned word in any string field") func bannedWords() throws {
        let banned = ["prominence", "f0", "npvi", "z-score", "zscore", "lexical", "nucleus"]
        let pairs = [Pairs.photography(you: Pairs.b), Pairs.photography(you: Pairs.d), Pairs.photography(you: Pairs.over),
                     Pairs.whoDidYouGiveItTo(final: Pairs.risingFinal)]
        for pair in pairs {
            var rough = pair
            rough.you.timing = .rough
            guard case .verdict(.feedback(let rows, _)) = try rough.score().decision else { continue }
            let json = String(decoding: try JSONEncoder().encode(Array(rows)), as: UTF8.self).lowercased()
            for word in banned { #expect(!json.contains(word), "\(word) in \(json)") }
        }
    }
}

@Suite("Measures") struct MeasureTests {
    @Test("applicability comes from the phrase and the model only") func applicabilityIgnoresYou() throws {
        let tables = try [Pairs.a, Pairs.b, Pairs.d].map { try Pairs.photography(you: $0).score().applicability }
        #expect(Set(tables).count == 1)
    }

    @Test("shape match is unavailable below 20 overlapping frames, never 0") func shapeTooFewFrames() throws {
        // You voice only "ra", which maps onto the model's 8-frame "ra": 8 overlapping frames.
        let you = [S(0.20, -19, nil), S(0.14, -22, nil), S(0.10, -25, (0, 1)), S(0.12, -25, nil)]
        let scoring = try Pairs.photography(you: you).score()
        #expect(scoring.measures[.shapeMatch] == .unavailable(.tooFewOverlappingFrames))
    }

    @Test("shape match is unavailable when either side is flat") func shapeZeroVariance() throws {
        let scoring = try Pairs.record(you: [S(0.24, -18, (2, 2)), S(0.28, -26, (2, 2))]).score()
        #expect(scoring.measures[.shapeMatch] == .unavailable(.zeroVariance))
    }

    @Test("no voiced frames: pitch range, final direction and shape match unavailable; close impossible")
    func noVoicedFrames() throws {
        let scoring = try Pairs.record(you: [S(0.24, -18, nil), S(0.28, -26, nil)]).score()
        for kind in [MeasureKind.pitchRange, .shapeMatch, .finalDirection] {
            #expect(scoring.measures[kind] == .unavailable(.noVoicedFrames), "\(kind)")
        }
        #expect(scoring.decision != .verdict(.close))
    }

    @Test("final direction: least-squares slope in st/s over the final 200 ms") func slopeUnits() {
        // 0.07 st per 10 ms frame = +7 st/s.
        let frames = (0..<40).map { PitchFrame(semitones: 0.07 * Double($0), voiced: true) }
        let window = FinalWindow(
            pitch: [PitchSegment(start: 0, frames: frames)], material: [try! TimeRange(start: 0, end: 0.4)],
            hopSeconds: 0.01)
        #expect(window.voicedFrames == 20)
        #expect(abs(window.slope! - 7) < 1e-9)
        #expect(PitchDirection(slope: 7) == .rise && PitchDirection(slope: -5) == .fall && PitchDirection(slope: 4.9) == .level)
    }

    @Test("final direction: extends to 300 ms when 200 ms holds fewer than 10 voiced frames, else unavailable")
    func windowExtension() {
        // Voiced, 12 unvoiced, 8 voiced: 200 ms holds 8, 300 ms holds 8 + 10 = 18.
        let head: [PitchFrame] = (0..<20).map { PitchFrame(semitones: -0.08 * Double($0), voiced: true) }
        let gap: [PitchFrame] = Array(repeating: PitchFrame(semitones: 0, voiced: false), count: 12)
        let tail: [PitchFrame] = (0..<8).map { PitchFrame(semitones: -0.08 * Double($0 + 32), voiced: true) }
        let frames = head + gap + tail
        let material = [try! TimeRange(start: 0, end: 0.4)]
        let window = FinalWindow(pitch: [PitchSegment(start: 0, frames: frames)], material: material, hopSeconds: 0.01)
        #expect(window.voicedFrames == 18)
        #expect(abs(window.slope! + 8) < 1e-9)
        // 9 voiced frames in all: under 10 even at 300 ms.
        let voiced: [PitchFrame] = (0..<9).map { PitchFrame(semitones: Double($0), voiced: true) }
        let silent: [PitchFrame] = Array(repeating: PitchFrame(semitones: 0, voiced: false), count: 31)
        let sparse = voiced + silent
        let short = FinalWindow(pitch: [PitchSegment(start: 0, frames: sparse)], material: material, hopSeconds: 0.01)
        #expect(short.slope == nil)
    }

    @Test("final direction: opposite, non-level directions trigger; the last word dropped is wordMissing")
    func finalDirection() throws {
        let rise = try Pairs.whoDidYouGiveItTo(final: Pairs.risingFinal).score()
        let row = try #require(rise.diffs.first)
        #expect(row.kind == .finalDirection && row.word == WordIndex(5))
        #expect(abs(row.values.you! - 7) < 0.5 && abs(row.values.model! + 8) < 0.5)
        let dropped = try Pairs.whoDidYouGiveItTo(
            final: [Pairs.fallingFinal[0], []], fates: [.present, .present, .present, .present, .present, .missing]
        ).score()
        #expect(dropped.measures[.finalDirection] == .unavailable(.wordMissing))
    }

    @Test("nPVI is inspector only: computed, never a diff") func npvi() throws {
        let scoring = try Pairs.photography(you: Pairs.d).score()
        #expect(scoring.applicability[.rhythm] == .applicable(.inspectorOnly))
        #expect(scoring.measures[.rhythm].value != nil)
        #expect(!DiffKind.allCases.map(\.rawValue).contains("rhythm"))
    }

    @Test("the contrast group reports as .contrast in partial and requiredMeasureUnavailable") func contrastGroup() throws {
        let partial = try Pairs.iLovePhotography(you: Pairs.b, lead: .low, timing: .rough).score()
        guard case .verdict(.feedback(_, let missing)) = partial.decision else { Issue.record("\(partial.decision)"); return }
        #expect(missing == [.contrast])
        let none = try Pairs.iLovePhotography(you: Pairs.a, lead: .low, timing: .rough).score()
        #expect(none.decision == .verdict(.inconclusive([.requiredMeasureUnavailable([.contrast])])))
    }
}
