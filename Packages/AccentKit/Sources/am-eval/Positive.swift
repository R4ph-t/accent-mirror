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

    static func run(
        pairs: [VCTKPair], cache: URL, available: Set<VCTKClip>, phrases: PositivePhrases, timings: FixtureTimestamper
    ) async throws -> PositiveRun {
        let analyzer = Analyzer(speech: SpeechModelHost(ready: timings), configuration: try .shipped())
        func take(speaker: String, phrase: String) throws -> TakeAudio {
            let url = vctkAudio(cache, speaker: speaker, phrase: phrase)
            let (samples, rate) = try AudioFiles.readMono(url)
            return TakeAudio(
                samples: try AudioFiles.resample(samples, from: rate, to: TakeAudio.sampleRate),
                sha256: try sha256(of: url), clipID: "\(speaker)_\(phrase)", recordedAt: Date(timeIntervalSince1970: 0))
        }
        var run = PositiveRun()
        var inputs: [String: PhraseInput] = [:]
        var natives: [PhraseID: [NativeRecording]] = [:]
        for phrase in Set(pairs.map(\.phrase)).sorted() {
            guard let input = try phrases.input(phrase) else {
                run.nativeFailures["no text for \(phrase)", default: 0] += 1
                continue
            }
            inputs[phrase] = input
            for voice in VCTK.nativeReaders(for: phrase) where available.contains(VCTKClip(speaker: voice, phrase: phrase)) {
                do {
                    let audio = try take(speaker: voice, phrase: phrase)
                    let record = try await analyzer.analyseNative(take: audio, phrase: input)
                    natives[input.id, default: []].append(NativeRecording(
                        id: EvalReferenceSet.recordingID(speaker: voice, phrase: phrase), voice: voice,
                        audioSHA256: audio.sha256, analysis: record))
                } catch {
                    run.nativeFailures["\(type(of: error))", default: 0] += 1
                }
            }
        }
        let reference = EvalReferenceSet(natives: natives)
        for (n, pair) in pairs.enumerated() {
            guard let input = inputs[pair.phrase] else {
                run.unscored["no phrase text", default: 0] += 1
                continue
            }
            let result = await analyzer.run(
                take: try take(speaker: pair.speaker, phrase: pair.phrase), phrase: input, reference: reference,
                voice: EvalReferenceSet.recordingID(speaker: pair.reference, phrase: pair.phrase))
            if (n + 1) % 50 == 0 { print("positive: analysed \(n + 1) of \(pairs.count) pairs") }
            guard let l2 = result.l2, let decision = l2.decision else {
                switch result.response.outcome {
                case .takeProblem(let problem):
                    run.unscored["take problem before scoring (\(problem.rawValue))", default: 0] += 1
                case .failed(.inferenceFailed(stage: .mapTime)):
                    // Either the reference reader's recognised words miss or substitute a phrase word, so it can't
                    // serve as the model (PairScoring.Failure.modelIncomplete), or your take's time map can't be built.
                    let model = natives[input.id]?.first { $0.voice == pair.reference }
                        .flatMap { DerivedCoding.native(in: $0.analysis) }
                    let present = Set(model?.l1.analysis.segmentation.words.filter { $0.kind == .present }.map(\.phraseWord) ?? [])
                    let complete = input.words.allSatisfy { present.contains($0.index) }
                    run.unscored[complete
                        ? "failed at mapTime: your take's time map (\(pair.phrase))"
                        : "failed at mapTime: reference \(pair.reference) incomplete for \(pair.phrase)", default: 0] += 1
                case .failed(let error):
                    run.unscored["failed: \(error)", default: 0] += 1
                default:
                    run.unscored["\(result.response.outcome)", default: 0] += 1
                }
                continue
            }
            run.outcomes.append(PairOutcome(
                speaker: pair.speaker, phrase: pair.phrase, phraseCluster: pair.sourcePrompt, decision: decision,
                applicability: l2.applicability, measures: l2.measures, modelValues: l2.modelValues,
                referenceAnomaly: l2.referenceAnomaly))
            if let coverage = l2.bandCoverage {
                run.band.append(PairBandCoverage(speaker: pair.speaker, phrase: pair.phrase, coverage: coverage))
            } else {
                run.noBandCoverage += 1
            }
        }
        return run
    }
}
