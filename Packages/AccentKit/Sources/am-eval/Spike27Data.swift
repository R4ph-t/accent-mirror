// Spec 27: the spike's data, prepared once per population into the build's cache (outside the worktree): every take
// through the front end (spec 25's detector at spec 26's frozen values) with its words under each boundary source.

import AMAlignment
import AMCore
import AMEvaluation
import AMSpike27
import Foundation

/// One take, measured, with its words per boundary source.
struct SpikeClip: Codable, Sendable {
    let id: String
    let speaker: String
    let population: Population
    /// The prompt: the starter id ("vctk-005") for VCTK texts and bundled voices, the utterance id for L2.
    let phrase: String
    let audio: String
    var measured: MeasuredAudio
    /// BoundarySource raw value → the take's words in time order.
    var words: [String: [TimedWord]]

    func words(_ source: BoundarySource) -> [TimedWord]? { words[source.rawValue] }
}

struct SpikeEnvironment {
    let root: URL
    let cache: URL
    let work: URL
    let listen: URL
    let reference: URL
    let split: VCTKSplitManifest
    let selector: PronunciationSelector
    let dictionary: PronouncingDictionary
    let reduced: ReducedForms
    let targets: TargetRule
    let aligner: WordAligner
    let jobs: Int

    init(_ args: Arguments, root: URL) throws {
        self.root = root
        let env = ProcessInfo.processInfo.environment
        cache = URL(fileURLWithPath: args.value("cache") ?? env["AM_EVAL_CACHE"] ?? root.appendingPathComponent("eval-cache").path)
        work = URL(fileURLWithPath: args.value("work") ?? cache.deletingLastPathComponent().appendingPathComponent("spike27").path)
        listen = URL(fileURLWithPath: args.value("listen") ?? cache.deletingLastPathComponent().appendingPathComponent("listen").path)
        reference = URL(fileURLWithPath: args.value("reference") ?? env["REFERENCE_DIR"] ?? cache.appendingPathComponent("../reference").path)
        split = try JSONDecoder().decode(VCTKSplitManifest.self,
                                         from: Data(contentsOf: root.appendingPathComponent("fixtures/splits/vctk.json")))
        selector = try .bundled()
        dictionary = try .bundled()
        reduced = try .bundled()
        targets = TargetRule(dictionary: dictionary, heteronyms: try TargetRule.loadHeteronyms(
            root.appendingPathComponent("docs/agreement/spike27/heteronyms.json")))
        aligner = try .bundled()
        jobs = Int(args.value("jobs") ?? "3") ?? 3
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    }

    func file(_ name: String) -> URL { work.appendingPathComponent(name) }

    /// The phrase's words under `source`, given (folded label, start, end) tokens in time order. Known text: LCS on
    /// folded words, then a 1:1 gap fill for substitutions (an unmatched prompt word between two matched anchors with
    /// exactly as many unmatched tokens as prompt words takes their spans in order). `fillSubstitutions` false gives
    /// exact matches only.
    func timedWords(phrase: ExpectedPhrase, phraseID: String?, tokens: [(String, Double, Double)],
                    tags: [Int: String] = [:], fillSubstitutions: Bool) -> [TimedWord] {
        let expected = phrase.words.map(\.folded)
        var match = lcsMatch(expected, tokens.map(\.0))
        if fillSubstitutions {
            var anchorsE = [-1] + match.keys.sorted() + [expected.count]
            anchorsE = Array(Set(anchorsE)).sorted()
            for (a, b) in zip(anchorsE, anchorsE.dropFirst()) {
                let ta = a >= 0 ? match[a]! : -1
                let tb = b < expected.count ? match[b]! : tokens.count
                let gapE = Array((a + 1)..<b), gapT = Array((ta + 1)..<max(ta + 1, tb))
                if !gapE.isEmpty && gapE.count == gapT.count { for (e, t) in zip(gapE, gapT) { match[e] = t } }
            }
        }
        var out: [TimedWord] = []
        for (i, word) in phrase.words.enumerated() {
            guard let t = match[i], let pronunciation = word.pronunciation, !pronunciation.syllables.isEmpty else { continue }
            let allowed = AllowedSyllableCounts.of(word: word.text, context: pronunciation, dictionary: dictionary,
                                                   reducedForms: reduced)
            let (target, exclusion) = targets.target(word: word.text, index: i, phrase: phraseID, context: pronunciation)
            out.append(TimedWord(index: i, text: word.text, start: tokens[t].1, end: max(tokens[t].2, tokens[t].1),
                                 syllables: pronunciation.syllables.count, allowed: allowed.counts, target: target,
                                 exclusion: exclusion, label: tags[i]))
        }
        return out.sorted { $0.start < $1.start || ($0.start == $1.start && $0.index < $1.index) }
    }

    /// Runtime known text (CTO markup 3): spec 03's shipped aligner (Needleman–Wunsch with the equivalence table)
    /// puts Whisper's heard words against the prompt; a `present` or `substituted` prompt word takes the heard span
    /// (the learner said the prompt word, whatever Whisper heard), a `missing` one has none.
    func knownTextWords(phrase: ExpectedPhrase, phraseID: String?, timing: TimingFile, tags: [Int: String] = [:])
        -> [TimedWord]
    {
        let heard = timing.words.compactMap { w -> HeardWord? in
            let text = w.word.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty, w.end >= w.start else { return nil }
            return HeardWord(text: text, range: SpikeData.range(w.start, w.end))
        }
        guard let result = try? aligner.align(phrase, heard: heard) else {
            return timedWords(phrase: phrase, phraseID: phraseID, tokens: timing.tokens, tags: tags, fillSubstitutions: true)
        }
        var spans: [Int: (Double, Double)] = [:]
        for pair in result.alignment.pairs {
            switch pair {
            case .present(let p, let you), .substituted(let p, _, let you): spans[p.rawValue] = (you.start, you.end)
            default: break
            }
        }
        var out: [TimedWord] = []
        for (i, word) in phrase.words.enumerated() {
            guard let span = spans[i], let pronunciation = word.pronunciation, !pronunciation.syllables.isEmpty else { continue }
            let allowed = AllowedSyllableCounts.of(word: word.text, context: pronunciation, dictionary: dictionary,
                                                   reducedForms: reduced)
            let (target, exclusion) = targets.target(word: word.text, index: i, phrase: phraseID, context: pronunciation)
            out.append(TimedWord(index: i, text: word.text, start: span.0, end: span.1,
                                 syllables: pronunciation.syllables.count, allowed: allowed.counts, target: target,
                                 exclusion: exclusion, label: tags[i]))
        }
        return out.sorted { $0.start < $1.start || ($0.start == $1.start && $0.index < $1.index) }
    }

    func expected(_ text: String, overrides: [WordIndex: Pronunciation] = [:]) -> ExpectedPhrase {
        selector.expectedPhrase(for: PhraseText(text: text, origin: .starter, overrides: overrides))
    }
}

struct TimingFile: Decodable {
    struct Word: Decodable { let start: Double; let end: Double; let word: String }
    let text: String
    let words: [Word]

    var tokens: [(String, Double, Double)] {
        words.map { (WordText.fold($0.word.trimmingCharacters(in: .whitespaces)), $0.start, $0.end) }
            .filter { !$0.0.isEmpty }
    }
}

private struct GuardInputFile: Decodable { let clipID: String; let audio: String; let transcript: String }

/// One take to prepare.
private struct PrepareItem: Sendable {
    let id: String
    let speaker: String
    let population: Population
    let phrase: String
    let audio: String
    let words: @Sendable (SpikeEnvironment) throws -> [String: [TimedWord]]
}

enum SpikeData {
    static func vctkPhrase(_ clipID: String) -> String {
        "vctk-" + (clipID.split(separator: "_").dropFirst().first.map(String.init) ?? clipID)
    }

    static func mfaTokens(_ url: URL) throws -> [(String, Double, Double)] {
        try MFATiers(contentsOf: url).words
            .filter { !$0.label.isEmpty && $0.label != "<eps>" && $0.label != "spn" }
            .map { (WordText.fold($0.label), $0.start, $0.end) }
    }

    /// Every take of a population (none measured yet).
    private static func items(_ population: Population, env: SpikeEnvironment) throws -> [PrepareItem] {
        switch population {
        case .tuningVCTK, .heldOutVCTK:
            let set = population == .tuningVCTK ? "tuning" : "held-out"
            let base = env.cache.appendingPathComponent("guard/\(set)")
            let timings = env.cache.appendingPathComponent(population == .tuningVCTK ? "vctk-tuning-timings" : "vctk-timings")
            let inputs = try JSONDecoder().decode([GuardInputFile].self,
                                                  from: Data(contentsOf: base.appendingPathComponent("inputs.json")))
            return inputs.map { input in
                let speaker = String(input.clipID.prefix { $0 != "_" })
                let mfa = base.appendingPathComponent("mfa-work/aligned/\(speaker)/\(input.clipID).json")
                let timing = timings.appendingPathComponent("\(input.clipID).json")
                let phrase = vctkPhrase(input.clipID)
                return PrepareItem(id: input.clipID, speaker: speaker, population: population, phrase: phrase,
                                   audio: input.audio) { env in
                    let expected = env.expected(input.transcript)
                    var words: [String: [TimedWord]] = [:]
                    if FileManager.default.fileExists(atPath: mfa.path) {
                        words[BoundarySource.oracle.rawValue] = env.timedWords(
                            phrase: expected, phraseID: phrase, tokens: try mfaTokens(mfa), fillSubstitutions: false)
                    }
                    if let file = try? JSONDecoder().decode(TimingFile.self, from: Data(contentsOf: timing)) {
                        words[BoundarySource.runtime.rawValue] = env.knownTextWords(
                            phrase: expected, phraseID: phrase, timing: file)
                    }
                    return words
                }
            }
        case .tts:
            struct Markers: Decodable { struct Phrase: Decodable { let clipID: String; let transcript: String }; let phrases: [Phrase] }
            struct Alignment: Decodable {
                struct Clip: Decodable { struct Word: Decodable { let start: Double; let end: Double; let word: String }; let clipID: String; let words: [Word] }
                let clips: [Clip]
            }
            let markers = try JSONDecoder().decode(Markers.self, from: Data(contentsOf: env.reference.appendingPathComponent("markers.json")))
            let alignment = try JSONDecoder().decode(Alignment.self, from: Data(contentsOf: env.reference.appendingPathComponent("mfa-alignment.json")))
            let byClip = Dictionary(uniqueKeysWithValues: alignment.clips.map { ($0.clipID, $0) })
            return markers.phrases.compactMap { phrase in
                guard let clip = byClip[phrase.clipID] else { return nil }
                let audio = env.reference.appendingPathComponent("corpus/tts/\(phrase.clipID).wav").path
                let phraseID = "vctk-" + phrase.clipID.replacingOccurrences(of: "tts_", with: "")
                return PrepareItem(id: phrase.clipID, speaker: "tts", population: .tts, phrase: phraseID, audio: audio) { env in
                    [BoundarySource.oracle.rawValue: env.timedWords(
                        phrase: env.expected(phrase.transcript), phraseID: phraseID,
                        tokens: clip.words.map { (WordText.fold($0.word), $0.start, $0.end) }, fillSubstitutions: false)]
                }
            }
        case .bundled:
            struct Manifest: Decodable {
                struct Phrase: Decodable {
                    struct Recording: Decodable { let speaker: String; let audio: String; let timings: String; let id: String }
                    let id: String; let text: String; let pronunciations: [String: String]; let recordings: [Recording]
                }
                let phrases: [Phrase]
            }
            let starter = env.root.appendingPathComponent("Resources/Starter")
            let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: starter.appendingPathComponent("manifest.json")))
            return manifest.phrases.flatMap { phrase in
                phrase.recordings.map { recording in
                    PrepareItem(id: "\(phrase.id)/\(recording.speaker)", speaker: recording.speaker, population: .bundled,
                                phrase: phrase.id, audio: starter.appendingPathComponent(recording.audio).path) { env in
                        var overrides: [WordIndex: Pronunciation] = [:]
                        for (key, arpabet) in phrase.pronunciations {
                            if let i = Int(key), let p = try? Pronunciation(arpabet: arpabet) { overrides[WordIndex(i)] = p }
                        }
                        let file = try JSONDecoder().decode(TimingFile.self, from: Data(contentsOf: starter.appendingPathComponent(recording.timings)))
                        return [BoundarySource.runtime.rawValue: env.knownTextWords(
                            phrase: env.expected(phrase.text, overrides: overrides), phraseID: phrase.id, timing: file)]
                    }
                }
            }
        case .l2Recall, .l2Clean, .speechocean762:
            return try l2Items(env)
        }
    }

    /// The L2 utterances that hold a 134, clean-1,400 or speechocean762 word, with Whisper timings. Each word is
    /// tagged with its sets: "134", "clean", "so762:misplaced" / "so762:correct".
    private static func l2Items(_ env: SpikeEnvironment) throws -> [PrepareItem] {
        let dir = env.cache.appendingPathComponent("speechocean762/current")
        func text(_ path: String) throws -> String { try String(contentsOf: dir.appendingPathComponent(path), encoding: .utf8) }
        let labels = try SpeechOceanLabels.fromCorpus(
            scoresDetail: Data(contentsOf: dir.appendingPathComponent("resource/scores-detail.json")),
            utt2spk: [.train: try text("train/utt2spk"), .test: try text("test/utt2spk")],
            spk2age: [.train: try text("train/spk2age"), .test: try text("test/spk2age")])
        let sets = SpeechOceanSets(labels: labels)
        var tags: [String: [Int: [String]]] = [:]
        for w in sets.recall { tags[w.utterance, default: [:]][w.index, default: []].append("134") }
        for w in sets.cleanFalsePositive { tags[w.utterance, default: [:]][w.index, default: []].append("clean") }
        let dropped = try loadDropped(env)
        struct Scores: Decodable {
            struct Word: Decodable { let text: String; let stress: Double; let accuracy: Double }
            let text: String; let words: [Word]
        }
        let scores = try JSONDecoder().decode([String: Scores].self,
                                              from: Data(contentsOf: dir.appendingPathComponent("resource/scores.json")))
        var texts: [String: String] = [:]
        for (utterance, entry) in scores {
            texts[utterance] = entry.words.map(\.text).joined(separator: " ")
            for (i, w) in entry.words.enumerated() {
                let n = env.dictionary.pronunciations(of: w.text).first?.syllables.count ?? 0
                if case .success(let label) = SpeechOcean762Rule.label(
                    stress: w.stress, accuracy: w.accuracy, syllables: n, utterance: utterance, dropped: dropped) {
                    tags[utterance, default: [:]][i, default: []].append("so762:\(label.rawValue)")
                }
            }
        }
        let timings = env.cache.appendingPathComponent("speechocean762-timings")
        let speakerOf = Dictionary(labels.words.map { ($0.utterance, $0.speaker) }, uniquingKeysWith: { a, _ in a })
        return tags.keys.sorted().compactMap { utterance in
            let timing = timings.appendingPathComponent("\(utterance).json")
            guard FileManager.default.fileExists(atPath: timing.path), let prompt = texts[utterance],
                  let speaker = speakerOf[utterance] else { return nil }
            let audio = dir.appendingPathComponent("WAVE/SPEAKER\(speaker)/\(utterance).WAV").path
            let wordTags = tags[utterance]!.mapValues { $0.joined(separator: ",") }
            return PrepareItem(id: utterance, speaker: speaker, population: .speechocean762, phrase: utterance,
                               audio: audio) { env in
                let file = try JSONDecoder().decode(TimingFile.self, from: Data(contentsOf: timing))
                let expected = env.expected(prompt)
                var words: [String: [TimedWord]] = [:]
                words[BoundarySource.runtime.rawValue] = env.knownTextWords(
                    phrase: expected, phraseID: nil, timing: file, tags: wordTags)
                // CTO markup 3's ASR variant: Whisper's own transcript is the phrase; a tagged prompt word is covered
                // only when Whisper heard that very word (LCS on folded words).
                let heard = env.expected(file.words.map { $0.word.trimmingCharacters(in: .whitespaces) }.joined(separator: " "))
                let promptToHeard = lcsMatch(expected.words.map(\.folded), heard.words.map(\.folded))
                var heardTags: [Int: String] = [:]
                for (p, h) in promptToHeard { if let tag = wordTags[p] { heardTags[h] = tag } }
                words[BoundarySource.asr.rawValue] = env.timedWords(
                    phrase: heard, phraseID: nil, tokens: file.tokens, tags: heardTags, fillSubstitutions: false)
                return words
            }
        }
    }

    static func range(_ start: Double, _ end: Double) -> TimeRange {
        (try? TimeRange(start: start, end: max(end, start))) ?? (try! TimeRange(start: 0, end: 0))
    }

    static func loadDropped(_ env: SpikeEnvironment) throws -> Set<String> {
        struct File: Decodable { let droppedUtterances: [String] }
        return Set(try JSONDecoder().decode(File.self, from: Data(contentsOf: env.root.appendingPathComponent(
            "docs/agreement/spike27/speechocean762.json"))).droppedUtterances)
    }

    static func cacheName(_ population: Population) -> String {
        switch population {
        case .l2Recall, .l2Clean, .speechocean762: "clips-l2.json"
        default: "clips-\(population.rawValue).json"
        }
    }

    /// Prepares (or loads from the cache) every take of `population`.
    static func clips(_ population: Population, env: SpikeEnvironment, log: (String) -> Void) async throws -> [SpikeClip] {
        let url = env.file(cacheName(population))
        if let data = try? Data(contentsOf: url) {
            return try JSONDecoder().decode([SpikeClip].self, from: data)
        }
        let all = try items(population, env: env)
        log("spike27 prepare: \(population.rawValue) \(all.count) takes")
        var out: [SpikeClip] = []
        var skipped: [String] = []
        let started = Date()
        try await withThrowingTaskGroup(of: (Int, SpikeClip?).self) { group in
            var next = 0
            func add() {
                guard next < all.count else { return }
                let index = next, item = all[index]
                next += 1
                group.addTask {
                    guard FileManager.default.fileExists(atPath: item.audio) else { return (index, nil) }
                    let samples = try WhisperKitTimestamper.samples(fromFileAt: URL(fileURLWithPath: item.audio))
                    let measured = try await FrontEnd.measure(samples)
                    let words = try item.words(env)
                    return (index, SpikeClip(id: item.id, speaker: item.speaker, population: item.population,
                                             phrase: item.phrase, audio: item.audio, measured: measured, words: words))
                }
            }
            for _ in 0..<max(1, env.jobs) { add() }
            var results: [Int: SpikeClip] = [:]
            var done = 0
            while let (index, clip) = try await group.next() {
                if let clip { results[index] = clip } else { skipped.append(all[index].id) }
                done += 1
                if done % 200 == 0 {
                    log(String(format: "spike27 prepare: %@ %d/%d (%.0f s)", population.rawValue, done, all.count,
                               Date().timeIntervalSince(started)))
                }
                add()
            }
            out = results.keys.sorted().map { results[$0]! }
        }
        if !skipped.isEmpty { log("spike27 prepare: \(population.rawValue) skipped \(skipped.count) (no audio): \(skipped.prefix(5))") }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(out).write(to: url)
        return out
    }
}
