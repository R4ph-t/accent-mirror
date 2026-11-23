import AMCore
import AMProsody
import AMWarp
import Foundation
import Testing
@testable import AMScoring

/// Spec 10's golden `AnalysisResult`s, from replayed L1 data. They live under `AMCoreTests/Golden/scoring/`, so spec
/// 01's golden digest covers them: changing one needs a version bump and a new `Versions.goldenDigests` record.
/// Re-record with `AM_RECORD_GOLDEN=1 swift test --package-path Packages/AccentKit --filter recordScoringGolden`.
enum ScoringGolden {
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // AMScoringTests
        .deletingLastPathComponent()  // Tests
        .appendingPathComponent("AMCoreTests/Golden/scoring")

    static let dropTo: [PairBuilder.Fate] = [.present, .present, .present, .present, .present, .missing]

    /// (file, phrase, pair, expected verdict).
    static let cases: [(file: String, phrase: String, pair: PairBuilder, verdict: Verdict)] = [
        ("placement-photography-B-vs-A.json", "photography", Pairs.photography(you: Pairs.b),
         .feedback(rows: rows(.placement, .contrast, .weakLength), partial: [])),
        ("flat-contrast-photography-D-vs-A.json", "photography", Pairs.photography(you: Pairs.d),
         .feedback(rows: rows(.contrast, .weakLength, .pitchRange), partial: [])),
        ("too-much-contrast-photography.json", "photography", Pairs.photography(you: Pairs.over),
         .feedback(rows: rows(.tooMuchContrast), partial: [])),
        ("close-record.json", "record", Pairs.record(you: Pairs.recordYouClose), .close),
        ("feedback-partial-contrast.json", "i-love-photography",
         Pairs.iLovePhotography(you: Pairs.b, lead: .low, timing: .rough),
         .feedback(rows: rows(.roughTiming, .placement), partial: [.contrast])),
        ("inconclusive-contrast-unavailable.json", "i-love-photography",
         Pairs.iLovePhotography(you: Pairs.a, lead: .low, timing: .rough),
         .inconclusive([.requiredMeasureUnavailable([.contrast])])),
        ("final-direction-who-did-you-give-it-to.json", "who-did-you-give-it-to",
         Pairs.whoDidYouGiveItTo(final: Pairs.risingFinal), .feedback(rows: rows(.finalDirection), partial: [])),
        ("final-direction-to-dropped.json", "who-did-you-give-it-to",
         Pairs.whoDidYouGiveItTo(final: [Pairs.fallingFinal[0], []], fates: dropTo),
         .noClearDifference([.optionalMeasuresUnavailable([.finalDirection]), .nonTargetWordsIncomplete([WordIndex(5)])])),
    ]

    /// Kinds only: the expected verdict's shape; the golden file holds the values.
    static func rows(_ kinds: DiffKind...) -> BoundedRows { BoundedRows(kinds.map { DiffRow(kind: $0) })! }

    static func result(phrase: String, pair: PairBuilder) throws -> AnalysisResult {
        let built = try pair.build()
        let scoring = try Scorer.score(built.input)
        guard case .verdict(let verdict) = scoring.decision else { throw CocoaError(.featureUnsupported) }
        let words = pair.accepted
        let model = speaker(built.model, built.input.model, words: words, texts: pair.words.map(\.text), measured: nil)
        let you = speaker(built.you, built.input.you, words: words, texts: pair.words.map(\.text), measured: scoring)
        let band = try NativeBand(
            selected: NativeVoice(sha256: String(repeating: "b", count: 64), pitch: built.input.model.pitch),
            others: [], testTake: nil, hopSeconds: pair.hop)
        let axis = model.words.map(\.range)
        return AnalysisResult(
            phraseID: PhraseID(phrase), takeID: TakeID("take-0001"), recordedAt: Date(timeIntervalSince1970: 1_795_420_800),
            model: model, you: you,
            modelAxis: try TimeRange(start: axis.map(\.start).min()!, end: axis.map(\.end).max()!),
            alignment: built.input.alignment, timeMap: built.input.warp.map, youPitchOnModel: scoring.youPitchOnModel,
            nativeBand: band.points, pitchAxis: -12...12, timing: scoring.timing, stress: scoring.stress,
            measures: scoring.measures.states, applicability: scoring.applicability, verdict: verdict,
            identity: identity(phrase))
    }

    /// One side as `SpeakerAnalysis`: dictionary stress for the model, measured primaries for you.
    static func speaker(
        _ laid: PairBuilder.Laid, _ take: ScoringTake, words: [ScoringWord], texts: [String], measured: Scoring?
    ) -> SpeakerAnalysis {
        let display = TakeProminence(take.syllables)?.display ?? take.syllables.map { _ in 0 }
        let total = take.syllables.reduce(0) { $0 + $1.features.duration }
        var spans: [WordSpan] = []
        var syllables: [SyllableMeasure] = []
        for w in laid.wordRanges.keys.sorted() {
            let ranges = laid.syllableRanges[w]!
            let first = syllables.count
            let observed = measured?.stress.first { $0.word == WordIndex(w) }?.observedPrimary
            for (i, range) in ranges.enumerated() {
                let k = take.syllables.firstIndex { $0.word == WordIndex(w) && $0.indexInWord == i }
                let stress: SyllableStress =
                    measured == nil ? (words[w].expectedPattern?[i] ?? .unstressed)
                    : observed.map { $0 == i ? .primary : .unstressed } ?? (words[w].expectedPattern?[i] ?? .unstressed)
                syllables.append(SyllableMeasure(
                    text: ranges.count == 1 ? texts[w] : "\(texts[w])#\(i)", wordIndex: spans.count, indexInWord: i,
                    range: range, share: k.map { take.syllables[$0].features.duration / total } ?? 0,
                    prominence: k.map { display[$0] } ?? 0, stress: stress,
                    stressSource: measured == nil || observed == nil ? .dictionary : .measured))
            }
            spans.append(WordSpan(text: texts[w], range: laid.wordRanges[w]!, syllables: Array(first..<syllables.count)))
        }
        return SpeakerAnalysis(words: spans, syllables: syllables, pitch: take.pitch, medianF0Hz: 150)
    }

    static func identity(_ phrase: String) -> AnalysisIdentity {
        AnalysisIdentity(
            takeAudioSHA256: String(repeating: "a", count: 64),
            reference: ReferenceIdentity(
                phraseID: PhraseID(phrase), recordingID: RecordingID("p225-\(phrase)"),
                recordingSHA256: String(repeating: "b", count: 64), transcriptRevision: 1,
                pronunciationOverridesHash: String(repeating: "c", count: 64), targetsHash: String(repeating: "d", count: 64),
                nativeSetHash: String(repeating: "e", count: 64)),
            config: ConfigIdentity(asrModelID: "replayed-word-timings", pitchTrackerID: "pyin-1", voicingID: "acf-1"))
    }

    static func pretty(_ value: AnalysisResult) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encode(value) + Data("\n".utf8)
    }
}

/// Verdict shape: the kinds of the rows, or the verdict itself when it has no rows.
private func shape(_ verdict: Verdict) -> String {
    if case .feedback(let rows, let partial) = verdict { return "feedback(\(rows.map(\.kind)), partial: \(partial))" }
    return "\(verdict)"
}

@Suite("Scoring goldens (spec 10)", .serialized) struct ScoringGoldenTests {
    @Test("record the scoring goldens when AM_RECORD_GOLDEN=1",
          .enabled(if: ProcessInfo.processInfo.environment["AM_RECORD_GOLDEN"] == "1"))
    func recordScoringGolden() throws {
        try FileManager.default.createDirectory(at: ScoringGolden.directory, withIntermediateDirectories: true)
        for c in ScoringGolden.cases {
            try ScoringGolden.pretty(try ScoringGolden.result(phrase: c.phrase, pair: c.pair))
                .write(to: ScoringGolden.directory.appendingPathComponent(c.file))
        }
    }

    @Test("each golden is what scoring produces, with the verdict the spec names",
          arguments: ScoringGolden.cases.map(\.file))
    func golden(file: String) throws {
        let c = try #require(ScoringGolden.cases.first { $0.file == file })
        let result = try ScoringGolden.result(phrase: c.phrase, pair: c.pair)
        #expect(shape(result.verdict) == shape(c.verdict))
        let data = try Data(contentsOf: ScoringGolden.directory.appendingPathComponent(file))
        #expect(try CanonicalJSON.canonicalize(data) == CanonicalJSON.encode(result), "\(file) differs: re-record")
        #expect(try CanonicalJSON.decoder().decode(AnalysisResult.self, from: data) == result)
    }

    @Test("every file under Golden/scoring/ is a listed case") func noStrayFiles() throws {
        let files = try FileManager.default.contentsOfDirectory(atPath: ScoringGolden.directory.path).filter {
            $0.hasSuffix(".json")
        }
        #expect(Set(files) == Set(ScoringGolden.cases.map(\.file)))
    }
}
