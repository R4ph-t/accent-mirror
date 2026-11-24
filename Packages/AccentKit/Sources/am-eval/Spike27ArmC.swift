// Spec 27 §3a: arm C, report-only. b2's character CTC (spec 23's wav2vec2-base-960h, evaluation tooling) under the
// known prompt text gives each word's vowel-letter positions; arm C scores them with arm B's frozen classifier and τ
// (the same features; nothing is refitted or chosen here). A pass alone is not a GO: it means a follow-up spec.

import AMAlignment
import AMAlignmentCTC
import AMCore
import AMEvaluation
import AMSpike27
import Foundation

enum SpikeArmC {
    /// Per take id → per prompt word index → the vowel groups' centre times (s).
    typealias Positions = [String: [Int: [Double]]]

    static func modelFolder() -> URL? {
        let base = ProcessInfo.processInfo.environment["MODELS_CACHE"].map(URL.init(fileURLWithPath:))
        let folder = base?.appendingPathComponent("wav2vec2-base-960h")
        return folder.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
    }

    /// Runs (or loads) the character alignment of every take.
    static func positions(_ clips: [SpikeClip], name: String, env: SpikeEnvironment) async throws -> Positions? {
        let url = env.file("armc-\(name).json")
        if let data = try? Data(contentsOf: url) { return try JSONDecoder().decode(Positions.self, from: data) }
        guard let folder = modelFolder() else { return nil }
        let manifest = try CTCModelManifest(contentsOf: env.root.appendingPathComponent("fixtures/models/wav2vec2-base-960h/manifest.json"))
        let aligner = try await CTCAligner.load(manifest: manifest, folder: folder)
        guard let blank = manifest.vocabulary.firstIndex(of: manifest.blank),
              let separator = manifest.vocabulary.firstIndex(of: manifest.wordSeparator) else { return nil }
        var labels: [Character: Int] = [:]
        for (i, label) in manifest.vocabulary.enumerated() where label.count == 1 && i != separator { labels[Character(label)] = i }
        let secondsPerFrame = Double(manifest.samplesPerFrame) / manifest.sampleRate
        var out: Positions = [:]
        let started = Date()
        for (n, clip) in clips.enumerated() {
            guard let text = clip.text else { continue }
            let samples = try WhisperKitTimestamper.samples(fromFileAt: URL(fileURLWithPath: clip.audio))
            guard samples.count <= manifest.conversion.maxSamples else { continue }
            let expected = env.expected(text)
            var words: [[Int]] = [], letters: [[Character]] = [], indices: [Int] = []
            for (i, word) in expected.words.enumerated() {
                let chars = word.text.uppercased().filter { labels[$0] != nil }
                guard !chars.isEmpty else { continue }
                words.append(chars.map { labels[$0]! })
                letters.append(Array(chars))
                indices.append(i)
            }
            let logProbs = try await aligner.logProbabilities(samples)
            guard let spans = ArmC.align(logProbs: logProbs.values, frames: logProbs.frames, classes: logProbs.classes,
                                         words: words, letters: letters, blank: blank, separator: separator) else { continue }
            var perWord: [Int: [Double]] = [:]
            for (w, word) in letters.enumerated() {
                let wordSpans = spans.filter { $0.word == w }
                guard wordSpans.count == word.count else { continue }
                perWord[indices[w]] = ArmC.vowelGroups(word).map { group in
                    let first = wordSpans[group.lowerBound].first, last = wordSpans[group.upperBound].last
                    return (Double(first + last + 1) / 2) * secondsPerFrame
                }
            }
            out[clip.id] = perWord
            if (n + 1) % 200 == 0 {
                spikeLog(String(format: "spike27 arm C: %@ %d/%d (%.0f s)", name, n + 1, clips.count, Date().timeIntervalSince(started)))
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(out).write(to: url)
        return out
    }

    /// Arm C's outcomes on the take's known-text (runtime) words, with arm B's classifier and τ.
    static func outcomes(_ clips: [SpikeClip], positions: Positions, classifier: StressClassifier, tau: Double,
                         where keep: (TimedWord) -> Bool = { _ in true }) -> [WordOutcome] {
        clips.flatMap { clip -> [WordOutcome] in
            guard let words = clip.words(.runtime) else { return [] }
            var selection: [Int: Result<[Int], AbstentionError>] = [:]
            for (j, word) in words.enumerated() where word.target != nil && keep(word) {
                if let centres = positions[clip.id]?[word.index],
                   let list = ArmC.select(clip.measured.nuclei, groupCentres: centres, syllables: word.syllables) {
                    selection[j] = .success(list)
                } else {
                    selection[j] = .failure(AbstentionError(.vowelPositions))
                }
            }
            return TakeScoring.score(clip.measured, words: words, selection: selection, classifier: classifier, tau: tau)
        }
    }
}
