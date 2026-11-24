// Spec 25 §6: the positive-set and L2 rows with and without the proposed cut (no per-word stress-placement verdict on
// 2–3-syllable words), on the shipped config. Evaluation only: the cut is applied to the suites' outputs after the
// fact (a placement flag or row on a 2–3-syllable word is dropped); nothing is cut in code. Cached per configDigest
// under eval-cache/nucleus-jitter/ so re-writing the report doesn't re-run the suites.

import AMAlignment
import AMCore
import AMEvaluation
import Foundation

struct ScopeCutRows: Codable {
    var configDigest: String
    var lines: [String]
}

private let cutSyllables = 2...3

private func share(_ k: Int, _ n: Int) -> String {
    guard n > 0 else { return "–" }
    let w = Statistics.wilson(successes: k, n: n)
    return String(format: "%d/%d (%.2f%%, Wilson [%.2f, %.2f])", k, n, Double(k) / Double(n) * 100, w.lower * 100, w.upper * 100)
}

func scopeCutRows(root: URL) async throws -> [String] {
    let digest = try configDigest(harnessConfig())
    let cache = cacheURL(root, "eval-cache/nucleus-jitter/scope-cut-\(digest.prefix(8)).json")
    if let data = try? Data(contentsOf: cache), let rows = try? JSONDecoder().decode(ScopeCutRows.self, from: data),
       rows.configDigest == digest {
        print("scope-cut: reusing \(cache.path)")
        return rows.lines
    }
    let measurement = Thresholds.current.prominence.measurement.name
    var lines = ["Shipped config \(digest.prefix(8)) (`.\(measurement)` measurement, thresholds on main); the cut drops "
        + "every placement flag and placement row on a word with 2–3 dictionary syllables, after the fact."]

    // L2 (speechocean762, shared-detector mode, replayed word timings), as `suite --suite l2-shared` runs it.
    let labels = try loadLabels(Arguments(["", "--labels", root.appendingPathComponent(Paths.labels).path]), root: root)
    let sets = SpeechOceanSets(labels: labels)
    let corpusDir = cacheURL(root, Paths.so762Cache)
    let timingsDir = cacheURL(root, Paths.so762Timings)
    if FileManager.default.fileExists(atPath: corpusDir.appendingPathComponent("resource/text-phone").path),
       FileManager.default.fileExists(atPath: timingsDir.appendingPathComponent(ReplayManifest.fileName).path) {
        let corpus = try SpeechOceanCorpusFiles(root: corpusDir)
        let detector = ReplayedPlacementDetector(
            corpus: corpus, timings: try FixtureTimestamper(directory: timingsDir),
            refPhones: Dictionary(labels.words.map { ($0.id, $0.refPhones) }, uniquingKeysWith: { first, _ in first }),
            dictionary: try .bundled())
        let runner = SharedDetectorRunner(
            detector: detector, corpus: corpus, dictionary: SelectorPrimaryLookup(selector: try .bundled()))
        let config = try FoldConfig(identity: harnessConfig(), thresholds: .current)
        for (name, words) in [("L2 false positives, clean 1,400", sets.cleanFalsePositive),
                              ("L2 false positives, supplementary", sets.supplementaryFalsePositive),
                              ("L2 recall (stress-wrong words)", sets.recall)] {
            let results = try await runner.run(words, config: config)
            let flagged = results.rows.filter { $0.outcome?.flaggedAfterSuppression == true }
            let kept = flagged.filter { !cutSyllables.contains($0.word.syllableCount) }
            let left = words.count { !cutSyllables.contains($0.syllableCount) }
            lines.append("\(name), after suppression: without the cut \(share(flagged.count, words.count)); with the cut "
                + "\(share(kept.count, words.count)) over all \(words.count) words, \(share(kept.count, left)) over the "
                + "\(left) words that keep a placement verdict")
            print("scope-cut: \(lines.last!)")
        }
    } else {
        lines.append("L2 rows: NOT EVALUATED (no speechocean762 corpus or replayed timings in the cache)")
    }

    // Positive set (held-out VCTK pairs through the pipeline), as `suite --suite positive` runs it.
    if let positive = try await positiveResult(Arguments(["suite"]), root: root, prefix: "scope-cut: positive") {
        let manifest = try VCTKEvalSpeakersManifest.load(root.appendingPathComponent(Paths.evalSpeakers))
        let table = try VCTKSubPhraseTable.load(root.appendingPathComponent(Paths.subPhrases))
        let phrases = try PositivePhrases(root: root, manifest: manifest, table: table)
        var counts: [String: [Int]] = [:]
        func syllables(_ phrase: String) -> [Int] {
            if let known = counts[phrase] { return known }
            let words = phrases.text(of: phrase).map {
                phrases.selector.expectedPhrase(for: PhraseText(text: $0, origin: .starter)).words
                    .map { $0.pronunciation?.syllables.count ?? 0 }
            } ?? []
            counts[phrase] = words
            return words
        }
        let outcomes = positive.run.outcomes
        var placement = 0, placementCut = 0, any = 0, anyCut = 0
        for outcome in outcomes {
            guard case .verdict(.feedback(let rows, _)) = outcome.decision else { continue }
            let counts = syllables(outcome.phrase)
            let kept = rows.filter { row in
                guard row.kind == .placement, let word = row.word?.rawValue, word < counts.count else { return true }
                return !cutSyllables.contains(counts[word])
            }
            if rows.contains(where: { $0.kind == .placement }) { placement += 1 }
            if kept.contains(where: { $0.kind == .placement }) { placementCut += 1 }
            if !rows.isEmpty { any += 1 }
            if !kept.isEmpty { anyCut += 1 }
        }
        let n = outcomes.count
        lines.append("Positive set (\(positive.status.text)), placement-diff pairs: without the cut \(share(placement, n)); with the cut \(share(placementCut, n))")
        lines.append("Positive set, any-diff pairs: without the cut \(share(any, n)); with the cut \(share(anyCut, n)) "
            + "(rows removed only; the verdict's other rows are not re-ranked, so a row hidden behind the 3-row cap "
            + "is not surfaced)")
        print("scope-cut: \(lines[lines.count - 2])\nscope-cut: \(lines.last!)")
    } else {
        lines.append("Positive-set rows: NOT EVALUATED (no trimmed VCTK cache)")
    }

    try FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder().encode(ScopeCutRows(configDigest: digest, lines: lines)).write(to: cache)
    return lines
}
