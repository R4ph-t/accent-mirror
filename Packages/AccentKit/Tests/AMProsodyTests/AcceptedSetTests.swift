import AMAlignment
import AMCore
import AMProsody
import Foundation
import Testing

/// A(w), matched S and U, `referenceAnomaly` and the placement rule (plan §3.3, §5) on "record" in "a new record".
@Suite("AcceptedSetTests") struct AcceptedSetTests {
    static let record = WordIndex(2)
    static let noun = try! Pronunciation(arpabet: "R EH1 K ER0 D")

    /// The starter phrase "a new record", with the noun override (spec 06): the context pronunciation is RE-cord.
    static func phrase(override: Bool = true) throws -> ExpectedPhrase {
        let selector = try PronunciationSelector.bundled()
        return selector.expectedPhrase(for: PhraseText(
            text: "a new record", origin: .starter, overrides: override ? [record: noun] : [:]))
    }

    static func expected(override: Bool = true) throws -> ExpectedWord {
        try #require(try phrase(override: override).words.first { $0.index == record })
    }

    /// A take of "a new record" whose "record" puts a clear peak on `primary` (0 noun, 1 verb).
    static func take(primary: Int, level: Confidence = .high, exposedLast: Bool = true) -> TakeProminence {
        func syllable(_ word: Int, _ index: Int, _ d: Double, _ e: Double, _ p: Double, exposed: Bool = false)
            -> ComparableSyllable
        {
            ComparableSyllable(
                word: WordIndex(word), indexInWord: index,
                features: ProminenceFeatures(duration: d, energyDBFS: e, peakSemitones: p, lengtheningExposed: exposed),
                level: word == record.rawValue ? level : .high)
        }
        let strong = (d: 0.24, e: -17.0, p: 4.0), weak = (d: 0.09, e: -26.0, p: -1.0)
        let first = primary == 0 ? strong : weak, second = primary == 0 ? weak : strong
        return TakeProminence([
            syllable(0, 0, 0.08, -24, 0),
            syllable(1, 0, 0.15, -21, 1),
            syllable(2, 0, first.d, first.e, first.p),
            syllable(2, 1, second.d, second.e, second.p, exposed: exposedLast),
        ])!
    }

    static func verbReading(voice: String, confidence: Confidence = .high) -> NativeReading {
        NativeReading(
            voice: voice,
            observed: ObservedStress(
                primary: 1, secondary: nil, margin: 1.2, marginConfidence: confidence, syllableConfidence: .high,
                exposed: true))
    }

    static func decide(_ take: TakeProminence, _ accepted: WordAcceptedSet) throws -> PlacementDecision {
        let observed = try #require(take.observedStress(of: record))
        return try #require(placementDecision(
            observed: observed, accepted: accepted.primaries, confidence: observed.syllableConfidence,
            exposure: observed.exposed))
    }

    @Test("a verb-stress take of the noun 'record' is flagged") func verbStressFlagged() throws {
        let accepted = try #require(WordAcceptedSet(expected: try Self.expected(), natives: []))
        #expect(accepted.primaries == [0])
        let take = Self.take(primary: 1)
        let observed = try #require(take.observedStress(of: Self.record))
        #expect(observed.primary == 1)
        #expect(observed.confidence == .high)
        let decision = try Self.decide(take, accepted)
        #expect(decision.outsideAccepted)
        #expect(decision.flagged)
        // Your primary is outside A(w): S and U come from the context pronunciation; the row names the nearest.
        #expect(accepted.matched(primary: 1, selectedVoice: nil) == nil)
        #expect(accepted.stressSets(matching: nil).stressed == [0])
        #expect(accepted.nearest(primary: 1, selectedVoice: nil) == AcceptedPattern(primary: 0, source: .contextPronunciation))
    }

    @Test("not flagged when a bundled native of this phrase produced verb stress at high confidence")
    func nativeAlternativeAccepted() throws {
        let accepted = try #require(WordAcceptedSet(
            expected: try Self.expected(), natives: [Self.verbReading(voice: "p311")]))
        #expect(accepted.primaries == [0, 1])
        let decision = try Self.decide(Self.take(primary: 1), accepted)
        #expect(!decision.outsideAccepted)
        #expect(!decision.flagged)
        // The inspector names the native pattern you match, and S/U come from it.
        let matched = try #require(accepted.matched(primary: 1, selectedVoice: "p225"))
        #expect(matched.pattern == AcceptedPattern(primary: 1, source: .nativeReader(voice: "p311")))
        let sets = accepted.stressSets(matching: matched)
        #expect(sets.stressed == [1] && sets.unstressed == [0])
    }

    @Test("a native reading below high confidence is not accepted", arguments: [Confidence.medium, .low])
    func lowConfidenceNativeIgnored(_ confidence: Confidence) throws {
        let accepted = try #require(WordAcceptedSet(
            expected: try Self.expected(), natives: [Self.verbReading(voice: "p311", confidence: confidence)]))
        #expect(accepted.primaries == [0])
        #expect(try Self.decide(Self.take(primary: 1), accepted).flagged)
    }

    @Test("other CMUdict variants are never accepted") func otherVariantsNotAccepted() throws {
        // CMUdict lists the verb (R IH0 K AO1 R D) too; only the context pronunciation is in A(w).
        #expect(try #require(WordAcceptedSet(expected: try Self.expected(), natives: [])).primaries == [0])
    }

    @Test("an expectedAmbiguous word has no accepted set, so it is never flagged") func ambiguousNeverFlagged() throws {
        // Without the override, the stress-shift word "record" in a starter phrase is expectedAmbiguous (spec 06).
        let word = try Self.expected(override: false)
        #expect(word.expectedAmbiguous)
        #expect(WordAcceptedSet(expected: word, natives: [Self.verbReading(voice: "p311")]) == nil)
    }

    @Test("a model voice outside A(w) at high confidence logs referenceAnomaly") func referenceAnomaly() throws {
        let model = Self.verbReading(voice: "p225")
        let accepted = try #require(WordAcceptedSet(expected: try Self.expected(), natives: [model]))
        #expect(accepted.isReferenceAnomaly(model: model), "its own reading does not vouch for itself")
        // Another native of the phrase produced the same pattern at high confidence: not an anomaly.
        let backed = try #require(WordAcceptedSet(
            expected: try Self.expected(), natives: [model, Self.verbReading(voice: "p311")]))
        #expect(!backed.isReferenceAnomaly(model: model))
        // Not at high confidence: not an anomaly.
        let unsure = Self.verbReading(voice: "p225", confidence: .medium)
        #expect(!accepted.isReferenceAnomaly(model: unsure))
        // A model on the context pattern is never an anomaly.
        let nounModel = NativeReading(
            voice: "p225", observed: ObservedStress(
                primary: 0, secondary: nil, margin: 1, marginConfidence: .high, syllableConfidence: .high, exposed: true))
        #expect(!accepted.isReferenceAnomaly(model: nounModel))
    }

    @Test("the test speaker is never added to its own A(w)") func heldOutSpeakerExcluded() throws {
        let natives = [Self.verbReading(voice: "p311"), Self.verbReading(voice: "p345")]
        let withoutSpeaker = try #require(WordAcceptedSet(
            expected: try Self.expected(), natives: natives, takeSpeaker: "p311"))
        #expect(!withoutSpeaker.entries.contains { $0.pattern.source == .nativeReader(voice: "p311") })
        #expect(withoutSpeaker.entries.contains { $0.pattern.source == .nativeReader(voice: "p345") })
        let alone = try #require(WordAcceptedSet(
            expected: try Self.expected(), natives: [Self.verbReading(voice: "p311")], takeSpeaker: "p311"))
        #expect(alone.primaries == [0])
        #expect(try Self.decide(Self.take(primary: 1), alone).flagged)
    }

    @Test("nearest accepted pattern: closest primary, ties go to the selected voice") func nearestTies() throws {
        let photography = ExpectedWord(
            index: WordIndex(0), text: "photography", pronunciation: try Pronunciation(arpabet: "F AH0 T AA1 G R AH0 F IY0"),
            source: .override, expectedAmbiguous: false, isContent: true, isTarget: true)
        func reading(_ voice: String, _ primary: Int) -> NativeReading {
            NativeReading(voice: voice, observed: ObservedStress(
                primary: primary, secondary: nil, margin: 1, marginConfidence: .high, syllableConfidence: .high,
                exposed: false))
        }
        // A(w) = {1 (context), 3 (p311)}; your primary 2 is equally close to both.
        let accepted = try #require(WordAcceptedSet(expected: photography, natives: [reading("p311", 3)]))
        #expect(accepted.nearest(primary: 2, selectedVoice: "p311")?.primary == 3)
        #expect(accepted.nearest(primary: 2, selectedVoice: "p225")?.primary == 1, "no selected-voice entry: context")
        #expect(accepted.nearest(primary: 0, selectedVoice: "p311")?.primary == 1, "closest wins over the voice")
    }

    @Test("a native alternative's secondary joins S") func nativeSecondary() throws {
        let photographic = ExpectedWord(
            index: WordIndex(0), text: "photographic",
            pronunciation: try Pronunciation(arpabet: "F OW2 T AH0 G R AE1 F IH0 K"),
            source: .override, expectedAmbiguous: false, isContent: true, isTarget: true)
        let accepted = try #require(WordAcceptedSet(expected: photographic, natives: [
            NativeReading(voice: "p311", observed: ObservedStress(
                primary: 0, secondary: 2, margin: 1, marginConfidence: .high, syllableConfidence: .high, exposed: false)),
        ]))
        // Context: primary 2, secondary 0 → S = {0, 2}.
        #expect(accepted.stressSets(matching: nil).stressed == [0, 2])
        let native = try #require(accepted.matched(primary: 0, selectedVoice: nil))
        #expect(native.stressed == [0, 2])
        #expect(accepted.stressSets(matching: native).unstressed == [1, 3])
        // The context pronunciation wins a match on its own primary.
        #expect(accepted.matched(primary: 2, selectedVoice: "p311")?.pattern.source == .contextPronunciation)
    }

    // MARK: placementDecision

    struct RuleCase: Sendable, CustomTestStringConvertible {
        let name: String
        let margin: Confidence
        let syllable: Confidence
        let exposure: Bool
        let flagged: Bool
        let suppression: PlacementSuppressionReason?
        var testDescription: String { name }
    }

    static let rules: [RuleCase] = [
        RuleCase(name: "high, high, not exposed", margin: .high, syllable: .high, exposure: false, flagged: true, suppression: nil),
        RuleCase(name: "high, high, exposed", margin: .high, syllable: .high, exposure: true, flagged: true, suppression: nil),
        RuleCase(name: "medium stress", margin: .medium, syllable: .high, exposure: false, flagged: false, suppression: .stressConfidenceBelowHigh),
        RuleCase(name: "medium stress, exposed", margin: .medium, syllable: .high, exposure: true, flagged: false, suppression: .exposedSyllable),
        RuleCase(name: "low stress", margin: .low, syllable: .high, exposure: false, flagged: false, suppression: .stressConfidenceBelowHigh),
        RuleCase(name: "syllable medium caps stress", margin: .high, syllable: .medium, exposure: false, flagged: false, suppression: .stressConfidenceBelowHigh),
        RuleCase(name: "syllable low", margin: .high, syllable: .low, exposure: false, flagged: false, suppression: .lowSyllableConfidence),
    ]

    @Test("placementDecision: outside A(w), high stress confidence, syllable ≥ medium", arguments: rules)
    func rule(_ rule: RuleCase) throws {
        let observed = ObservedStress(
            primary: 1, secondary: nil, margin: 1, marginConfidence: rule.margin, syllableConfidence: rule.syllable,
            exposed: rule.exposure)
        let outside = try #require(placementDecision(
            observed: observed, accepted: [0], confidence: rule.syllable, exposure: rule.exposure))
        #expect(outside.outsideAccepted)
        #expect(outside.flagged == rule.flagged)
        #expect(outside.suppression == rule.suppression)
        // Inside A(w): never flagged, nothing to suppress.
        let inside = try #require(placementDecision(
            observed: observed, accepted: [0, 1], confidence: rule.syllable, exposure: rule.exposure))
        #expect(!inside.outsideAccepted && !inside.flagged && inside.suppression == nil)
    }

    @Test("an empty A(w) gives no placement decision") func emptyAccepted() {
        let observed = ObservedStress(
            primary: 1, secondary: nil, margin: 1, marginConfidence: .high, syllableConfidence: .high, exposed: false)
        #expect(placementDecision(observed: observed, accepted: [], confidence: .high, exposure: false) == nil)
    }
}
