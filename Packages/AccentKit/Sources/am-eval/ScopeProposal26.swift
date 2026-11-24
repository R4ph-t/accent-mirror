// Spec 26 §6: the scope proposal when acceptance 1 fails, with at least two cut shapes and their numbers, for CTO to
// route to Raph via CPO. Nothing is cut in code: every number is the suites' output with the cut applied after the
// fact. Shape (a): per-word stress verdicts only on count-matched, unambiguous words (P ∈ N_w, not
// `assignmentAmbiguous`, not nucleus-short), measured on `.nucleus` at the head's values. Shape (b): v1 without
// per-word stress verdicts (placement and contrast dropped; the phrase-level rhythm and intonation rows kept), on the
// shipped config. The suites' rows are cached per configDigest under eval-cache/nucleus-jitter/.

import AMAlignment
import AMCore
import AMEvaluation
import AMLibrary
import AMPipeline
import AMProsody
import Foundation

private func share(_ k: Int, _ n: Int) -> String {
    guard n > 0 else { return "–" }
    let w = Statistics.wilson(successes: k, n: n)
    return String(format: "%d/%d (%.2f%%, Wilson [%.2f, %.2f])", k, n, Double(k) / Double(n) * 100, w.lower * 100, w.upper * 100)
}

/// A word is in the confident subset: present, not nucleus-short, not ambiguous, P ∈ N_w.
func isConfident(_ word: SegmentedWord) -> Bool {
    guard word.kind == .present, let a = word.nucleusAssignment else { return false }
    return !a.short && a.ambiguous != true && (a.allowed ?? [a.dictionaryCount]).contains(a.available)
}

/// The shared detector with the subset applied after the fact: a word outside the confident subset keeps no
/// placement flag (it would get no per-word stress verdict).
struct SubsetPlacementDetector: PlacementDetector {
    let base: ReplayedPlacementDetector
    var id: String { base.id + "+confident-subset" }

    func placements(for utterance: DetectorUtterance, config: FoldConfig) async throws -> [String: PlacementOutcome] {
        let decided = Dictionary(utterance.words.map { ($0.index, $0) }, uniquingKeysWith: { first, _ in first })
        let words = utterance.transcript.enumerated().map { index, text in
            let word = decided[index]
            let phones = referencePhones(
                word.flatMap { base.refPhones[$0.id] }, base.corpus.phones(utterance: utterance.id, index: index),
                text: text, dictionary: base.dictionary)
            return PlacementFixtureItem.Word(
                id: word?.id, index: index, text: text, phones: phones,
                accepted: word.map { Array($0.accepted.primaries).sorted() })
        }
        let item = PlacementFixtureItem(
            item: utterance.id, corpus: "speechocean762", speaker: utterance.speaker, audio: utterance.audio.path,
            audioSHA256: try sha256(of: utterance.audio), words: words)
        let analysis = try await base.analyse(item, audio: utterance.audio, config: config.thresholds)
        let segmented = Dictionary(analysis.segmentation.words.map { ($0.phraseWord, $0) }, uniquingKeysWith: { a, _ in a })
        var outcomes: [String: PlacementOutcome] = [:]
        for result in analysis.words {
            guard let id = decided[result.word.rawValue]?.id else { continue }
            let confident = segmented[result.word].map(isConfident) ?? false
            outcomes[id] = confident
                ? PlacementOutcome(present: result.present, flaggedBeforeSuppression: result.flaggedBeforeSuppression,
                                   suppression: result.suppression.map(PlacementSuppression.init))
                : PlacementOutcome(present: result.present, flaggedBeforeSuppression: false, suppression: nil)
        }
        return outcomes
    }
}

struct Scope26Rows: Codable {
    var configDigest: String
    var a: [String]
    var b: [String]
}

/// The suite-based rows of both shapes (L2, positive set, starter phrases), cached per configDigest.
func scope26SuiteRows(root: URL) async throws -> Scope26Rows {
    let digest = try configDigest(harnessConfig())
    let cache = cacheURL(root, "eval-cache/nucleus-jitter/scope26-\(digest.prefix(8)).json")
    if let data = try? Data(contentsOf: cache), let rows = try? JSONDecoder().decode(Scope26Rows.self, from: data),
       rows.configDigest == digest {
        print("scope26: reusing \(cache.path)")
        return rows
    }
    var nucleus = Thresholds.current
    nucleus.prominence.measurement = .nucleus
    var a: [String] = [], b: [String] = []

    // (a) Starter phrases (spec 15): each bundled recording analysed on `.nucleus` at the head's values.
    let manifest = try StarterManifest.load(from: root.appendingPathComponent("Resources/Starter"))
    let references = try StarterReferences(manifest: manifest, configuration: try .shipped(thresholds: nucleus))
    let selector = try PronunciationSelector.bundled()
    let dictionary = try PronouncingDictionary.bundled()
    var applicable = 0, confident = 0
    var affected: [String] = []
    for phrase in manifest.phrases {
        let input = try StarterReferences.input(phrase, selector: selector, dictionary: dictionary)
        let words = input.words.filter { $0.accepted != nil }
        var lacking: [String: Int] = [:]
        for recording in phrase.recordings {
            let source = StarterRecordingSource(
                phrase: phrase, recording: recording, audio: root.appendingPathComponent("Resources/Starter/\(recording.audio)"),
                timings: root.appendingPathComponent("Resources/Starter/\(recording.timings)"), asrModelID: manifest.asrModelID)
            let record = try await references.analyse(source)
            guard let l1 = DerivedCoding.value(L1Analysis.self, in: record, key: record.key) else { continue }
            let segmented = Dictionary(l1.analysis.segmentation.words.map { ($0.phraseWord, $0) }, uniquingKeysWith: { x, _ in x })
            for word in words {
                applicable += 1
                if segmented[word.index].map(isConfident) == true { confident += 1 } else { lacking[word.text, default: 0] += 1 }
            }
        }
        let voices = phrase.recordings.count
        let majority = lacking.filter { $0.value * 2 > voices }.keys.sorted()
        if !majority.isEmpty { affected.append("\(phrase.id.rawValue) (\(majority.joined(separator: ", ")))") }
    }
    a.append("Starter phrases (spec 15, \(manifest.phrases.count) phrases, every bundled voice, `.nucleus` at the head's values): "
        + "\(share(confident, applicable)) of the placement-applicable word recordings (words with an A(w)) are in the subset; "
        + "\(affected.count) of \(manifest.phrases.count) phrases have a placement-applicable word outside it in most voices: "
        + (affected.isEmpty ? "none" : affected.joined(separator: "; ")) + ".")
    print("scope26: \(a.last!)")

    // (a) L2 (speechocean762, shared-detector mode, replayed word timings) on `.nucleus` with the subset.
    let labels = try loadLabels(Arguments(["", "--labels", root.appendingPathComponent(Paths.labels).path]), root: root)
    let sets = SpeechOceanSets(labels: labels)
    let corpusDir = cacheURL(root, Paths.so762Cache)
    let timingsDir = cacheURL(root, Paths.so762Timings)
    if FileManager.default.fileExists(atPath: corpusDir.appendingPathComponent("resource/text-phone").path),
       FileManager.default.fileExists(atPath: timingsDir.appendingPathComponent(ReplayManifest.fileName).path) {
        let corpus = try SpeechOceanCorpusFiles(root: corpusDir)
        let base = ReplayedPlacementDetector(
            corpus: corpus, timings: try FixtureTimestamper(directory: timingsDir),
            refPhones: Dictionary(labels.words.map { ($0.id, $0.refPhones) }, uniquingKeysWith: { first, _ in first }),
            dictionary: try .bundled())
        let config = try FoldConfig(identity: harnessConfig(), thresholds: nucleus)
        let subset = SharedDetectorRunner(
            detector: SubsetPlacementDetector(base: base), corpus: corpus,
            dictionary: SelectorPrimaryLookup(selector: try .bundled()))
        for (name, words) in [("L2 recall (the stress-wrong words)", sets.recall),
                              ("L2 false positives, clean 1,400", sets.cleanFalsePositive)] {
            let results = try await subset.run(words, config: config)
            let flagged = results.rows.filter { $0.outcome?.flaggedAfterSuppression == true }
            a.append("\(name), `.nucleus` with the subset, after suppression: \(share(flagged.count, words.count))")
            print("scope26: \(a.last!)")
        }
    } else {
        a.append("L2 rows: NOT EVALUATED (no speechocean762 corpus or replayed timings in the cache)")
    }

    // (a) Positive set on `.nucleus`, placement rows on words outside the subset dropped after the fact.
    if let positive = try await positiveResult(Arguments(["suite"]), root: root, prefix: "scope26: positive (.nucleus)",
                                               thresholds: nucleus) {
        let outcomes = positive.run.outcomes
        var placement = 0, any = 0
        for outcome in outcomes {
            guard case .verdict(.feedback(let rows, _)) = outcome.decision else { continue }
            let outside = positive.run.nonConfident["\(outcome.speaker)_\(outcome.phrase)"] ?? []
            let kept = rows.filter { row in
                guard row.kind == .placement, let word = row.word?.rawValue else { return true }
                return !outside.contains(word)
            }
            if kept.contains(where: { $0.kind == .placement }) { placement += 1 }
            if !kept.isEmpty { any += 1 }
        }
        a.append("Positive set on `.nucleus` (\(positive.status.text)), with the subset: placement-diff pairs "
            + "\(share(placement, outcomes.count)); any-diff pairs \(share(any, outcomes.count)) (rows removed only)")
        print("scope26: \(a.last!)")
    } else {
        a.append("Positive-set rows (a): NOT EVALUATED (no trimmed VCTK cache)")
    }

    // (b) Positive set on the shipped config, placement and contrast rows dropped.
    if let positive = try await positiveResult(Arguments(["suite"]), root: root, prefix: "scope26: positive (shipped)") {
        let outcomes = positive.run.outcomes
        let dropped: Set<DiffKind> = [.placement, .contrast, .tooMuchContrast]
        var any = 0
        var byKind: [DiffKind: Int] = [:]
        for outcome in outcomes {
            guard case .verdict(.feedback(let rows, _)) = outcome.decision else { continue }
            let kept = rows.filter { !dropped.contains($0.kind) }
            if !kept.isEmpty { any += 1 }
            for kind in Set(kept.map(\.kind)) { byKind[kind, default: 0] += 1 }
        }
        b.append("Positive set on the shipped config (`.\(Thresholds.current.prominence.measurement.name)`, "
            + "\(positive.status.text)), placement, contrast and too-much-contrast rows dropped: any-diff pairs "
            + "\(share(any, outcomes.count)); pairs keeping each row: "
            + DiffKind.allCases.filter { !dropped.contains($0) }.map { "\($0.rawValue) \(byKind[$0] ?? 0)" }.joined(separator: ", ")
            + " (rows removed only; a row hidden behind the 3-row cap is not surfaced)")
        let kept = ["Weak length", "nPVI", "Band coverage", "Pitch range", "Final direction"]
        for line in positive.lines where kept.contains(where: { line.name.hasPrefix($0) }) {
            b.append("Positive-set row kept: \(line.name): n \(line.n), value \(line.value.map { String(format: "%.4f", $0) } ?? "–"), \(String(describing: line.status))")
        }
        for line in b { print("scope26: \(line)") }
    } else {
        b.append("Positive-set rows (b): NOT EVALUATED (no trimmed VCTK cache)")
    }

    // (b) Starter targets that lose their stress feedback: every target with a placement verdict (A(w)).
    var targets: [String] = []
    for phrase in manifest.phrases {
        let input = try StarterReferences.input(phrase, selector: selector, dictionary: dictionary)
        let lost = input.words.filter { phrase.targets.contains($0.index.rawValue) && $0.accepted != nil }.map(\.text)
        if !lost.isEmpty { targets.append("\(phrase.id.rawValue): \(lost.joined(separator: ", "))") }
    }
    b.append("Starter targets that lose their stress feedback (placement, and contrast for their phrase): "
        + "\(targets.count) of \(manifest.phrases.count) phrases: " + targets.joined(separator: "; ") + ".")

    let rows = Scope26Rows(configDigest: digest, a: a, b: b)
    try FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder().encode(rows).write(to: cache)
    return rows
}

/// The proposal: shapes (a) and (b), the harness numbers first, then the suites' rows.
func nucleusScope26(_ sets: [NucleusJitter.Set], root: URL) async throws -> NucleusScopeProposal {
    var a: [String] = []
    for set in sets {
        guard let n = set.comparison(NucleusJitter.gatedID, measurement: .nucleus)?.nucleus26 else {
            a.append("\(set.set): NOT EVALUATED (the run has no spec 26 fields)")
            continue
        }
        for g in [n.pooled] + n.groups {
            a.append("\(set.set), group \(g.bucket): subset \(share(g.confident, g.words)) of comparable words; "
                + "±40 ms flips in the subset \(share(g.confidentFlips, g.confident)); subset inconclusive unjittered "
                + "\(share(g.confidentOracleInconclusive, g.confident)), ±40 ms \(share(g.confidentCandidateInconclusive, g.confident))")
        }
    }
    let suites = try await scope26SuiteRows(root: root)
    return NucleusScopeProposal(shapes: [
        .init(name: "(a) Confident subset: per-word stress verdicts only on count-matched, unambiguous words "
              + "(P ∈ N_w, not assignmentAmbiguous, not nucleus-short)", lines: a + suites.a),
        .init(name: "(b) v1 without per-word stress verdicts: keep the phrase-level rhythm and intonation rows "
              + "(nPVI, weak length, band coverage, pitch range, final direction); drop placement and contrast", lines: suites.b),
    ])
}
