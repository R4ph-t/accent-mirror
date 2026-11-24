// Spec 12: the VCTK positive set through the pipeline. Each held-out pair is analysed by the `Analyzer` exactly as the
// app would (replayed word timings, real pitch, real scoring) against a reference set of the phrase's bundled native
// readers, so spec 10's positive gates and spec 09's band coverage print measured numbers. Initial, untuned
// thresholds; nothing is tuned here. Word timings are recorded once with `am-eval record-timings --set positive`.

import AMAlignment
import AMCore
import AMEvaluation
import AMLibrary
import AMPipeline
import Foundation
import Synchronization

let vctkAttribution = "CSTR VCTK Corpus 0.92 (University of Edinburgh), CC BY 4.0; local evaluation cache, never committed"

/// The trimmed clip of `speaker` reading `phrase` in the VCTK cache.
func vctkAudio(_ cache: URL, speaker: String, phrase: String) -> URL {
    cache.appendingPathComponent("\(speaker)/\(speaker)_\(phrase).flac")
}

/// What the positive suite analyses: the trimmed cache's kept clips, by speaker and phrase.
struct PositiveCache {
    let cache: URL
    let kept: [VCTKClip]
    let rejected: [[String: String]]

    init?(_ cache: URL) {
        guard let data = try? Data(contentsOf: cache.appendingPathComponent("trim-report.json")),
            let report = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let kept = report["kept"] as? [String]
        else { return nil }
        self.cache = cache
        self.kept = kept.compactMap { name -> VCTKClip? in
            let parts = name.split(separator: "_")
            return parts.count == 2 ? VCTKClip(speaker: String(parts[0]), phrase: String(parts[1])) : nil
        }
        // A cache trimmed before spec 24 has no `stage`: every rejection in it is the trim's.
        rejected = ((report["rejected"] as? [[String: String]]) ?? []).map { r in
            r["stage"] == nil ? r.merging(["stage": "trim"]) { $1 } : r
        }
    }

    /// The VCTK tuning speakers' takes (spec 11's tuning objective and guard on tuning data).
    func tuningClips(manifest: VCTKEvalSpeakersManifest) -> [VCTKClip] {
        let speakers = Set(manifest.tuningSpeakers.map(\.id))
        return kept.filter { speakers.contains($0.speaker) }.sorted { ($0.speaker, $0.phrase) < ($1.speaker, $1.phrase) }
    }

    /// The clips whose word timings the suite replays: the held-out speakers' takes and the bundled readers'.
    func timingClips(manifest: VCTKEvalSpeakersManifest) -> [VCTKClip] {
        let speakers = Set(manifest.heldOutSpeakers.map(\.id) + VCTK.bundledVoices)
        return kept.filter { speakers.contains($0.speaker) }.sorted { ($0.speaker, $0.phrase) < ($1.speaker, $1.phrase) }
    }
}

/// The words of a positive-set phrase, as the detector and the scorer read them.
struct PositivePhrases {
    let baseline: [String: [String]]
    let phraseText: [String: String]
    let table: VCTKSubPhraseTable
    let selector: PronunciationSelector
    let dictionary: PronouncingDictionary

    init(root: URL, manifest: VCTKEvalSpeakersManifest, table: VCTKSubPhraseTable) throws {
        struct Baseline: Decodable {
            struct Clip: Decodable {
                struct Word: Decodable { let word: String }
                let clipID: String
                let words: [Word]
            }
            let clips: [Clip]
        }
        let clips = try JSONDecoder().decode(
            Baseline.self, from: Data(contentsOf: root.appendingPathComponent(Paths.mfaBaseline))).clips
        var baseline: [String: [String]] = [:]
        for clip in clips {
            guard let prompt = clip.clipID.split(separator: "_").last.map(String.init), baseline[prompt] == nil else { continue }
            baseline[prompt] = clip.words.map(\.word)
        }
        self.baseline = baseline
        phraseText = manifest.phraseText ?? [:]
        self.table = table
        selector = try .bundled()
        dictionary = try .bundled()
    }

    /// The phrase's text: a sub-phrase's own text, the MFA baseline's words for a starter prompt (as every reader
    /// read it), else the shared text in eval-speakers.json.
    func text(of phrase: String) -> String? {
        if let sub = table.subPhrases.first(where: { $0.id == phrase }) { return sub.text }
        if let words = baseline[phrase] { return words.joined(separator: " ") }
        return phraseText[phrase].map(Self.spoken)
    }

    /// Lowercase words with their apostrophes, punctuation dropped.
    static func spoken(_ text: String) -> String {
        let kept = String(text.lowercased().unicodeScalars.map { ("a"..."z").contains($0) || $0 == "'" ? Character($0) : " " })
        return kept.split(separator: " ").joined(separator: " ")
    }

    func input(_ phrase: String) throws -> PhraseInput? {
        guard let text = text(of: phrase) else { return nil }
        let words = try starterPhraseWords(text, selector: selector, dictionary: dictionary).map { word in
            PlacementTake.Word(
                index: WordIndex(word.index), text: word.text, pronunciation: try Pronunciation(arpabet: word.phones),
                accepted: word.accepted.map(Set.init))
        }
        return PhraseInput(id: PhraseID("vctk-" + phrase), words: words)
    }
}

/// A bundled-voice phrase's words: the starter rule (overrides only, no tagger), so stress-shift words are
/// expectedAmbiguous and get no decision. Shared with the smoke set's VCTK items.
func starterPhraseWords(
    _ text: String, selector: PronunciationSelector, dictionary: PronouncingDictionary
) -> [PlacementFixtureItem.Word] {
    selector.expectedPhrase(for: PhraseText(text: text, origin: .starter)).words.map { word in
        let phones = word.pronunciation?.arpabet ?? fallbackPhones(word.text, dictionary: dictionary)
        let pattern = word.expectedPattern ?? []
        let accepted = pattern.count >= 2 ? pattern.firstIndex(of: .primary).map { [$0] } : nil
        return PlacementFixtureItem.Word(id: nil, index: word.index.rawValue, text: word.text, phones: phones, accepted: accepted)
    }
}

/// The positive set's reference side: per phrase, the bundled native readers' analyses, built once by the analyzer.
final class EvalReferenceSet: ReferenceSet {
    private let natives: [PhraseID: [NativeRecording]]

    init(natives: [PhraseID: [NativeRecording]]) { self.natives = natives }

    func identity(phrase: PhraseID, voice: RecordingID) -> ReferenceIdentity {
        let recordings = natives[phrase] ?? []
        let hashes = recordings.map(\.audioSHA256).sorted()
        return ReferenceIdentity(
            phraseID: phrase, recordingID: voice,
            recordingSHA256: recordings.first { $0.id == voice }?.audioSHA256 ?? "", transcriptRevision: 0,
            pronunciationOverridesHash: "starter", targetsHash: "starter",
            nativeSetHash: SHA256Digest.hex(of: Data(hashes.joined(separator: "\n").utf8)))
    }

    func natives(phrase: PhraseID) async throws(ReferenceSetError) -> [NativeRecording] { natives[phrase] ?? [] }

    func rebuild(_ recording: RecordingID, phrase: PhraseID) async throws(ReferenceSetError) {
        throw .cacheCorrupt(recording)
    }

    static func recordingID(speaker: String, phrase: String) -> RecordingID { RecordingID("\(speaker)_\(phrase)") }
}

/// Why a word of `analysis` can't be used (§3a's transcript check): substituted, missing, span sanity failed or low
/// Whisper probability (below `confidence.levelMedium`); usable words are absent from the result.
func wordProblems(
    _ analysis: PlacementAnalysis, words: [PlacementTake.Word], thresholds: Thresholds = .current
) -> [WordIndex: WordUsabilityProblem] {
    var out: [WordIndex: WordUsabilityProblem] = [:]
    let segmented = Dictionary(analysis.segmentation.words.map { ($0.phraseWord, $0) }, uniquingKeysWith: { a, _ in a })
    for word in words {
        let pair = analysis.alignment.pairs.first { $0.phraseWord == word.index }
        switch pair {
        case .substituted?: out[word.index] = .asrSubstitution
        case .present?:
            guard let s = segmented[word.index], s.kind == .present else { out[word.index] = .asrMissing; continue }
            if s.spanSanity < 1 { out[word.index] = .spanSanityFailed }
            else if s.injected.probability < thresholds.confidence.levelMedium { out[word.index] = .lowAsrConfidence }
        default: out[word.index] = .asrMissing
        }
    }
    return out
}

/// §3a: every phrase's listed references analysed once, each word checked, and the per-pair choice of reference.
final class ReferencedPhrases {
    struct Native {
        let voice: String
        let recording: NativeRecording
        let analysis: NativeAnalysis
        let problems: [WordIndex: WordUsabilityProblem]
    }

    struct Phrase {
        let input: PhraseInput
        let list: [String]
        var natives: [Native] = []
        /// Listed voices whose clip isn't in the cache (outside 2–6 s, or not read).
        var trimRejected: Set<String> = []
    }

    let analyzer: Analyzer
    let cache: URL
    private(set) var phrases: [String: Phrase] = [:]

    init(analyzer: Analyzer, cache: URL) {
        self.analyzer = analyzer
        self.cache = cache
    }

    func take(speaker: String, phrase: String) throws -> TakeAudio {
        let url = vctkAudio(cache, speaker: speaker, phrase: phrase)
        let (samples, rate) = try AudioFiles.readMono(url)
        return TakeAudio(
            samples: try AudioFiles.resample(samples, from: rate, to: TakeAudio.sampleRate),
            sha256: try sha256(of: url), clipID: "\(speaker)_\(phrase)", recordedAt: Date(timeIntervalSince1970: 0))
    }

    static func build(
        phrases names: Set<String>, lists: VCTKReferenceLists, cache: URL, available: Set<VCTKClip>,
        phrases text: PositivePhrases, timings: any WordTimestamper
    ) async throws -> ReferencedPhrases {
        let out = ReferencedPhrases(
            analyzer: Analyzer(speech: SpeechModelHost(ready: timings), configuration: try .shipped()), cache: cache)
        for name in names.sorted() {
            guard let input = try text.input(name) else { continue }
            var phrase = Phrase(input: input, list: lists.phrases[name] ?? [])
            for voice in phrase.list {
                guard available.contains(VCTKClip(speaker: voice, phrase: name)) else {
                    phrase.trimRejected.insert(voice)
                    continue
                }
                let audio = try out.take(speaker: voice, phrase: name)
                guard let record = try? await out.analyzer.analyseNative(take: audio, phrase: input),
                    let native = DerivedCoding.native(in: record)
                else { continue }
                phrase.natives.append(Native(
                    voice: voice,
                    recording: NativeRecording(
                        id: EvalReferenceSet.recordingID(speaker: voice, phrase: name), voice: voice,
                        audioSHA256: audio.sha256, analysis: record),
                    analysis: native, problems: wordProblems(native.l1.analysis, words: input.words)))
            }
            out.phrases[name] = phrase
        }
        return out
    }

    /// The first listed reference (never `speaker`) usable for every phrase word, and why each earlier one wasn't.
    func choose(speaker: String, phrase name: String) -> (reference: String?, skipped: [String: WordUsabilityProblem]) {
        guard let phrase = phrases[name] else { return (nil, [:]) }
        var skipped: [String: WordUsabilityProblem] = [:]
        for voice in phrase.list where voice != speaker {
            if phrase.trimRejected.contains(voice) { skipped[voice] = .trimRejected; continue }
            guard let native = phrase.natives.first(where: { $0.voice == voice }) else {
                skipped[voice] = .asrMissing
                continue
            }
            if let first = phrase.input.words.lazy.compactMap({ native.problems[$0.index] }).first {
                skipped[voice] = first
                continue
            }
            return (voice, skipped)
        }
        return (nil, skipped)
    }

    /// The reference set a take by `speaker` is scored against: the phrase's analysed references but the speaker.
    func referenceSet(phrase name: String, excluding speaker: String) -> EvalReferenceSet {
        guard let phrase = phrases[name] else { return EvalReferenceSet(natives: [:]) }
        return EvalReferenceSet(natives: [phrase.input.id: phrase.natives.filter { $0.voice != speaker }.map(\.recording)])
    }
}

/// Every take of `speakers` in `phrases` with a kept clip: the pair universe (one speaker × one phrase, counted once).
func referencedPairs(speakers: [String], available: Set<VCTKClip>, phrases: [String]) -> [(speaker: String, phrase: String)] {
    speakers.sorted().flatMap { speaker in
        phrases.filter { available.contains(VCTKClip(speaker: speaker, phrase: $0)) }.map { (speaker, $0) }
    }
}

/// The positive set's pairs through the analyzer: each pair's scoring and band coverage, and why any pair wasn't scored.
struct PositiveRun {
    var outcomes: [PairOutcome] = []
    var band: [PairBandCoverage] = []
    /// Unscored pairs by reason.
    var unscored: [String: Int] = [:]
    /// Native recordings that couldn't be analysed, by reason.
    var nativeFailures: [String: Int] = [:]
    /// Scored pairs with no band coverage (no comparable voiced frame).
    var noBandCoverage = 0
    /// §3a: every pair of the universe, scored or lost, with the reference that served it.
    var accounts: [PairAccount] = []

    static func run(
        pairs: [(speaker: String, phrase: String)], references: ReferencedPhrases
    ) async throws -> PositiveRun {
        var run = PositiveRun()
        for (n, pair) in pairs.enumerated() {
            if (n + 1) % 50 == 0 { print("positive: analysed \(n + 1) of \(pairs.count) pairs") }
            func lose(_ reason: String, skipped: [String: WordUsabilityProblem] = [:]) {
                run.unscored[reason, default: 0] += 1
                run.accounts.append(PairAccount(
                    speaker: pair.speaker, phrase: pair.phrase, reference: nil, skipped: skipped, lostReason: reason))
            }
            guard let phrase = references.phrases[pair.phrase] else { lose("no phrase text"); continue }
            let (reference, skipped) = references.choose(speaker: pair.speaker, phrase: pair.phrase)
            guard let reference else { lose(WordUsabilityProblem.noUsableReference.rawValue, skipped: skipped); continue }
            let result = await references.analyzer.run(
                take: try references.take(speaker: pair.speaker, phrase: pair.phrase), phrase: phrase.input,
                reference: references.referenceSet(phrase: pair.phrase, excluding: pair.speaker),
                voice: EvalReferenceSet.recordingID(speaker: reference, phrase: pair.phrase))
            guard let l2 = result.l2, let decision = l2.decision else {
                switch result.response.outcome {
                case .takeProblem(let problem): lose("held-out take: take problem before scoring (\(problem.rawValue))", skipped: skipped)
                case .failed(let error): lose("held-out take: failed (\(error))", skipped: skipped)
                default: lose("held-out take: \(result.response.outcome)", skipped: skipped)
                }
                continue
            }
            run.accounts.append(PairAccount(
                speaker: pair.speaker, phrase: pair.phrase, reference: reference, skipped: skipped, lostReason: nil))
            run.outcomes.append(PairOutcome(
                speaker: pair.speaker, phrase: pair.phrase, phraseCluster: VCTK.sourcePrompt(of: pair.phrase),
                decision: decision, applicability: l2.applicability, measures: l2.measures,
                modelValues: l2.modelValues, referenceAnomaly: l2.referenceAnomaly))
            if let coverage = l2.bandCoverage {
                run.band.append(PairBandCoverage(speaker: pair.speaker, phrase: pair.phrase, coverage: coverage))
            } else {
                run.noBandCoverage += 1
            }
        }
        return run
    }

    /// §3a's accounting for each positive row, keyed by `PositiveSetGates.Dependent.name`.
    func accounting() -> [String: RowAccounting] {
        func id(_ o: PairOutcome) -> String { "\(o.speaker)_\(o.phrase)" }
        let byID = Dictionary(outcomes.map { (id($0), $0) }, uniquingKeysWith: { a, _ in a })
        func why(_ kind: MeasureKind) -> (String) -> String {
            { pair in
                guard let o = byID[pair] else { return "not scored" }
                switch o.measures[kind] {
                case nil: return "\(kind.rawValue) not applicable"
                case .notApplicable(let r)?: return "\(kind.rawValue) not applicable (\(r))"
                case .unavailable(let r)?: return "\(kind.rawValue) unavailable (\(r))"
                case .evaluated?: return "no model value for \(kind.rawValue)"
                }
            }
        }
        let all = Set(outcomes.map(id))
        func measured(_ kind: MeasureKind, needsPositiveModel: Bool = false, applicable: Bool = false) -> Set<String> {
            Set(outcomes.filter { o in
                guard o.measures[kind]?.value != nil, let model = o.modelValues[kind] else { return false }
                if needsPositiveModel && model <= 0 { return false }
                if applicable && !o.applicability[kind].isApplicable { return false }
                return true
            }.map(id))
        }
        let scored: (String) -> String = { _ in "not scored" }
        var out: [String: RowAccounting] = [:]
        for name in ["Any-diff pairs", "Any-diff pairs, worst speaker", "Any-diff pairs, worst phrase", "Placement-diff pairs",
                     "Placement-diff pairs, worst speaker", "Inconclusive pairs", "Evaluation coverage"] {
            out[name] = RowAccounting.make(accounts: accounts, measured: all, why: scored)
        }
        out["Band coverage, median over pairs"] = RowAccounting.make(
            accounts: accounts, measured: Set(band.map { "\($0.speaker)_\($0.phrase)" }),
            why: { _ in "no comparable voiced frame" })
        out["Contrast ratio within tolerance"] = RowAccounting.make(
            accounts: accounts, measured: measured(.contrast, needsPositiveModel: true), why: why(.contrast))
        out["Weak length, largest |Δ|"] = RowAccounting.make(accounts: accounts, measured: measured(.weakLength), why: why(.weakLength))
        out["nPVI, largest |Δ|"] = RowAccounting.make(accounts: accounts, measured: measured(.rhythm), why: why(.rhythm))
        out["Pitch range ratio at or above minimum"] = RowAccounting.make(
            accounts: accounts, measured: measured(.pitchRange, needsPositiveModel: true), why: why(.pitchRange))
        out["Final direction agreement"] = RowAccounting.make(
            accounts: accounts, measured: measured(.finalDirection, applicable: true), why: why(.finalDirection))
        out["Positive-set placement false positives (synthetic references)"] = RowAccounting.make(
            accounts: accounts, measured: [], why: { _ in "no verified synthetic reference (spec 22)" })
        return out
    }
}
