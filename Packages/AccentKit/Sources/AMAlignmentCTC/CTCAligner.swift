// AMAlignmentCTC: evaluation tooling only (CTO ruling 2026-11-24 on #27). Only am-timestamps and the tests link it;
// nothing in AMPipeline's dependency closure does, and ShippedAlignerTests fails if that changes. The shipped aligner
// is `whisper`.
//
// ctc-w2v2b960-1 (spec 23, candidate b2): CTC forced alignment of the recognised words with
// facebook/wav2vec2-base-960h (Apache-2.0) in Core ML. The model is fetched and converted by scripts/fetch-ctc.sh,
// SHA-256 pinned in fixtures/models/wav2vec2-base-960h/manifest.json, and verified before every load. On device:
// no network.
//
// One forward pass gives character log-probabilities every 20 ms. A Viterbi pass over the CTC trellis of the words'
// letters (blank between them; the model's word separator `|` counts as blank, so a missing separator frame never
// breaks the path) aligns them, each word's letters allowed only within its recognised span ± `snapWindowMs`.
// Each word's start is its first letter frame and its end the frame after its last; `BoundarySearch` then applies the
// clamps. Words with no letter in the vocabulary, a take longer than the model accepts, or a band with no path
// leave the boundaries where the recogniser put them.

// `MLModel` is not `Sendable` in the SDK. The one instance here is created inside `load` and then owned by the
// `CTCAligner` actor, which never hands it out, so it is never used from two places at once. Core ML documents
// `MLModel` predictions as thread-safe in any case.
@preconcurrency import CoreML
import Foundation
import Synchronization
import AMAlignment
import AMCore

/// The pinned description of the CTC model: its upstream files, the conversion and the converted package.
public struct CTCModelManifest: Codable, Sendable, Equatable {
    public struct Source: Codable, Sendable, Equatable {
        public var repo: String
        public var commit: String
        public var license: String
        /// Where the licence was read at that commit.
        public var licenseEvidence: String
    }

    public struct Conversion: Codable, Sendable, Equatable {
        public var script: String
        public var requirements: String
        public var python: String
        public var precision: String
        public var minSamples: Int
        public var maxSamples: Int
    }

    public struct File: Codable, Sendable, Equatable {
        public var path: String
        public var size: Int
        public var sha256: String
        /// Upstream files only: the pinned download URL.
        public var url: String?
    }

    public var formatVersion: Int
    public var model: String
    public var aligner: String
    public var source: Source
    public var upstream: [File]
    public var conversion: Conversion
    /// The converted `.mlpackage`, relative to the fetched folder.
    public var package: String
    /// The package's files, relative to the package.
    public var packageFiles: [File]
    /// `Digest.listing` over `packageFiles`.
    public var packageSHA256: String
    /// The model's output labels, by index (from the pinned `vocab.json`).
    public var vocabulary: [String]
    public var blank: String
    public var wordSeparator: String
    /// Audio samples per output frame.
    public var samplesPerFrame: Int
    public var sampleRate: Double

    public init(contentsOf url: URL) throws {
        self = try JSONDecoder().decode(CTCModelManifest.self, from: Data(contentsOf: url))
    }

    /// Checks the manifest is self-consistent and the package in `folder` holds exactly the pinned bytes.
    public func verify(folder: URL) throws {
        let listed = Digest.listing(packageFiles.map { ($0.path, $0.sha256) })
        guard listed == packageSHA256 else {
            throw ModelVerificationError.manifestInconsistent(computed: listed, recorded: packageSHA256)
        }
        let root = folder.appending(path: package)
        let present = try Self.files(under: root)
        if let extra = present.first(where: { path in !packageFiles.contains { $0.path == path } }) {
            throw ModelVerificationError.mismatch(path: "\(package)/\(extra)", expected: "not present", actual: "present")
        }
        for file in packageFiles {
            let url = root.appending(path: file.path)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw ModelVerificationError.missing(path: "\(package)/\(file.path)")
            }
            let actual = try Digest.sha256(fileAt: url)
            guard actual == file.sha256 else {
                throw ModelVerificationError.mismatch(path: "\(package)/\(file.path)", expected: file.sha256, actual: actual)
            }
        }
    }

    static func files(under root: URL) throws -> [String] {
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])
        else { return [] }
        var paths: [String] = []
        let prefix = root.standardizedFileURL.path + "/"
        for case let url as URL in walker where try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
            paths.append(String(url.standardizedFileURL.path.dropFirst(prefix.count)))
        }
        return paths
    }
}

public enum CTCAlignerError: Error, Equatable, Sendable {
    case vocabulary(String)
    case output(String)
}

/// The b2 refiner. Load once; `refine` may be called from any task. Cancelling a call never unloads the model.
public actor CTCAligner: WordBoundaryRefiner {
    public static let aligner = "ctc-w2v2b960-1"

    public nonisolated var id: String { Self.aligner }
    public nonisolated let manifest: CTCModelManifest
    public nonisolated let thresholds: Thresholds.WordBoundaries
    private let model: MLModel
    private let labels: [Character: Int]
    private let blank: Int
    private let separator: Int

    /// Verifies the package against the manifest, compiles it and loads it. Throws on any hash mismatch.
    public static func load(manifest: CTCModelManifest, folder: URL,
                            thresholds: Thresholds.WordBoundaries = Thresholds.current.wordBoundaries,
                            computeUnits: MLComputeUnits = .all) async throws -> CTCAligner {
        try manifest.verify(folder: folder)
        let compiled = try await MLModel.compileModel(at: folder.appending(path: manifest.package))
        defer { try? FileManager.default.removeItem(at: compiled) }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        let model = try MLModel(contentsOf: compiled, configuration: configuration)
        return try CTCAligner(manifest: manifest, model: model, thresholds: thresholds)
    }

    init(manifest: CTCModelManifest, model: MLModel, thresholds: Thresholds.WordBoundaries) throws {
        guard let blank = manifest.vocabulary.firstIndex(of: manifest.blank),
              let separator = manifest.vocabulary.firstIndex(of: manifest.wordSeparator)
        else { throw CTCAlignerError.vocabulary("no blank or word separator") }
        var labels: [Character: Int] = [:]
        for (index, label) in manifest.vocabulary.enumerated() where label.count == 1 && index != separator {
            labels[Character(label)] = index
        }
        self.manifest = manifest
        self.model = model
        self.thresholds = thresholds
        self.labels = labels
        self.blank = blank
        self.separator = separator
    }

    public func refine(_ words: [WordTimestamp], samples: [Float], sampleRate: Double) async throws -> [WordTimestamp] {
        try await align(words, samples: samples, sampleRate: sampleRate).map(\.word)
    }

    /// The refined words with each word's CTC confidence (`CTCForcedAlignment.Aligned.confidence`; 0 for a word the
    /// aligner could not place, whose boundaries stay Whisper's).
    public func align(_ words: [WordTimestamp], samples: [Float], sampleRate: Double) async throws -> [ConfidentWord] {
        try Task.checkCancellation()
        guard !words.isEmpty else { return [] }
        let duration = Double(samples.count) / sampleRate
        let window = thresholds.snapWindowMs / 1000
        var spans: [CTCForcedAlignment.Span?] = Array(repeating: nil, count: words.count)
        var confidences = [Double](repeating: 0, count: words.count)
        if sampleRate == manifest.sampleRate, samples.count <= manifest.conversion.maxSamples {
            let logProbs = try await logProbabilities(samples)
            try Task.checkCancellation()
            let secondsPerFrame = Double(manifest.samplesPerFrame) / sampleRate
            let tokens = words.map { word in word.word.uppercased().compactMap { labels[$0] } }
            let aligned = try CTCForcedAlignment.alignWithConfidence(
                logProbs: logProbs.values, frames: logProbs.frames, classes: logProbs.classes, tokens: tokens,
                bands: words.map { ((($0.start - window) / secondsPerFrame).rounded(.down),
                                    (($0.end + window) / secondsPerFrame).rounded(.up)) },
                blank: blank, separator: separator)
            spans = aligned.map { $0.map { CTCForcedAlignment.Span(start: $0.span.start * secondsPerFrame,
                                                                   end: $0.span.end * secondsPerFrame) } }
            confidences = aligned.map { $0?.confidence ?? 0 }
        }
        let refined = try BoundarySearch.refine(
            words, takeDuration: duration, windowSeconds: window,
            findStart: { index, _ in spans[index]?.start }, findEnd: { index, _ in spans[index]?.end })
        return zip(refined, confidences).map { ConfidentWord(word: $0, confidence: $1) }
    }

    /// Per-frame log-softmax of the model's logits, row-major `frames × classes`. Public for spec 27's arm C
    /// (character positions, report-only, evaluation tooling).
    public func logProbabilities(_ samples: [Float]) async throws -> (values: [Float], frames: Int, classes: Int) {
        var audio = CTCForcedAlignment.normalised(samples)
        if audio.count < manifest.conversion.minSamples {
            audio += [Float](repeating: 0, count: manifest.conversion.minSamples - audio.count)
        }
        let input = audio
        let model = model
        // One prediction can't be interrupted, so a cancel returns at once and the prediction's result is dropped
        // when it finishes. The model is never torn down.
        let logits = try await CancellableWork.run {
            let provider = try MLDictionaryFeatureProvider(
                dictionary: ["audio": MLMultiArray(MLShapedArray<Float>(scalars: input, shape: [1, input.count]))])
            let output = try await model.prediction(from: provider)
            guard let logits = output.featureValue(for: "logits")?.multiArrayValue, logits.shape.count == 3 else {
                throw CTCAlignerError.output("no logits")
            }
            return MLShapedArray<Float>(logits)
        }
        let frames = logits.shape[1], classes = logits.shape[2]
        var values = logits.scalars
        for t in 0..<frames {
            if t.isMultiple(of: 200) { try Task.checkCancellation() }
            let row = t * classes
            var peak = -Float.infinity
            for c in 0..<classes { peak = max(peak, values[row + c]) }
            var sum: Float = 0
            for c in 0..<classes { sum += exp(values[row + c] - peak) }
            let logSum = peak + log(sum)
            for c in 0..<classes { values[row + c] -= logSum }
        }
        return (values, frames, classes)
    }
}

/// A refined word and its CTC confidence, 0–1.
public struct ConfidentWord: Sendable, Equatable, Codable {
    public var word: WordTimestamp
    public var confidence: Double

    public init(word: WordTimestamp, confidence: Double) {
        self.word = word
        self.confidence = confidence
    }

    /// The probability the word carries into spec 07's `WordSpan` (CTO ruling 2026-11-23 14:05): 0 below
    /// `minimum`, so every syllable of the word is low confidence and the word is inconclusive; otherwise the
    /// recogniser's probability, unchanged.
    public func spanProbability(minimum: Double = Thresholds.current.wordBoundaries.ctcConfidenceMin) -> Double {
        confidence < minimum ? 0 : word.probability
    }
}

/// Runs work that can't stop part-way so that the caller still returns promptly on cancel: the caller gets
/// `CancellationError` as soon as its task is cancelled, and the work's result, when it comes, is dropped.
enum CancellableWork {
    /// Whichever comes first, the work's result or the cancel, is kept until the caller is waiting for it.
    private enum State<T: Sendable> {
        case idle
        case waiting(CheckedContinuation<T, any Error>)
        case finished(Result<T, any Error>)
        case done
    }

    static func run<T: Sendable>(_ work: @escaping @Sendable () async throws -> T) async throws -> T {
        try Task.checkCancellation()
        let state = Mutex<State<T>>(.idle)
        @Sendable func finish(_ result: Result<T, any Error>) {
            let continuation: CheckedContinuation<T, any Error>? = state.withLock { current in
                switch current {
                case .waiting(let continuation):
                    current = .done
                    return continuation
                case .idle:
                    current = .finished(result)
                    return nil
                case .finished, .done:
                    return nil
                }
            }
            continuation?.resume(with: result)
        }
        let worker = Task {
            do { finish(.success(try await work())) } catch { finish(.failure(error)) }
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let ready: Result<T, any Error>? = state.withLock { current in
                    if case .finished(let result) = current {
                        current = .done
                        return result
                    }
                    current = .waiting(continuation)
                    return nil
                }
                if let ready { continuation.resume(with: ready) }
            }
        } onCancel: {
            worker.cancel()
            finish(.failure(CancellationError()))
        }
    }
}

/// The pure parts of the CTC aligner: normalisation and the banded Viterbi.
public enum CTCForcedAlignment {
    /// A word's span in frames (`end` exclusive), or in seconds once scaled.
    public struct Span: Sendable, Equatable {
        public var start: Double
        public var end: Double
    }

    /// Zero mean, unit variance, as the model's feature extractor does (`do_normalize`, ε = 1e-7).
    public static func normalised(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return [] }
        let n = Double(samples.count)
        let mean = samples.reduce(0.0) { $0 + Double($1) } / n
        let variance = samples.reduce(0.0) { $0 + (Double($1) - mean) * (Double($1) - mean) } / n
        let scale = 1 / (variance + 1e-7).squareRoot()
        return samples.map { Float((Double($0) - mean) * scale) }
    }

    /// A word's frame span and its confidence: the mean posterior probability, over the frames the best path spends
    /// on the word's characters, of the character it is on there.
    public struct Aligned: Sendable, Equatable {
        public var span: Span
        public var confidence: Double
    }

    /// Viterbi over the CTC trellis of all words' tokens in order, blank between every token. A word's tokens may
    /// occupy only frames in its band `[lower, upper]`. Returns each word's frame span, nil for a word with no tokens,
    /// and all nil when no path fits the bands.
    public static func align(logProbs: [Float], frames: Int, classes: Int, tokens: [[Int]],
                             bands: [(Double, Double)], blank: Int, separator: Int) throws -> [Span?] {
        try alignWithConfidence(logProbs: logProbs, frames: frames, classes: classes, tokens: tokens, bands: bands,
                                blank: blank, separator: separator).map { $0?.span }
    }

    /// `align`, with each word's confidence.
    public static func alignWithConfidence(logProbs: [Float], frames: Int, classes: Int, tokens: [[Int]],
                                           bands: [(Double, Double)], blank: Int, separator: Int) throws -> [Aligned?] {
        var labels: [Int] = [], owner: [Int] = []
        for (word, letters) in tokens.enumerated() {
            labels += letters
            owner += Array(repeating: word, count: letters.count)
        }
        let none = [Aligned?](repeating: nil, count: tokens.count)
        let states = 2 * labels.count + 1
        guard !labels.isEmpty, frames > 0 else { return none }
        func label(_ s: Int) -> Int? { s % 2 == 1 ? labels[s / 2] : nil }
        func allowed(_ s: Int, _ t: Int) -> Bool {
            guard s % 2 == 1 else { return true }
            let band = bands[owner[s / 2]]
            return Double(t) >= band.0 && Double(t) <= band.1
        }
        func emission(_ s: Int, _ t: Int) -> Float {
            let row = t * classes
            if let label = label(s) { return logProbs[row + label] }
            let a = logProbs[row + blank], b = logProbs[row + separator]
            let m = max(a, b)
            return m + log(exp(a - m) + exp(b - m))
        }

        let impossible = -Float.infinity
        var score = [Float](repeating: impossible, count: states)
        var back = [UInt8](repeating: 0, count: frames * states)
        for s in 0..<min(2, states) where allowed(s, 0) { score[s] = emission(s, 0) }
        var next = score
        for t in 1..<max(frames, 1) {
            if t.isMultiple(of: 50) { try Task.checkCancellation() }
            for s in 0..<states {
                guard allowed(s, t) else {
                    next[s] = impossible
                    continue
                }
                var best = score[s], step: UInt8 = 0
                if s >= 1, score[s - 1] > best { best = score[s - 1]; step = 1 }
                if s >= 2, let l = label(s), l != label(s - 2), score[s - 2] > best { best = score[s - 2]; step = 2 }
                next[s] = best == impossible ? impossible : best + emission(s, t)
                back[t * states + s] = step
            }
            swap(&score, &next)
        }
        var s = states - 1
        if states >= 2, score[states - 2] > score[s] { s = states - 2 }
        guard score[s] > impossible else { return none }

        var spans = [Span?](repeating: nil, count: tokens.count)
        var posterior = [Double](repeating: 0, count: tokens.count), counts = [Int](repeating: 0, count: tokens.count)
        for t in stride(from: frames - 1, through: 0, by: -1) {
            if s % 2 == 1 {
                let word = owner[s / 2]
                let span = spans[word] ?? Span(start: Double(t), end: Double(t + 1))
                spans[word] = Span(start: Double(t), end: span.end)
                posterior[word] += Double(exp(logProbs[t * classes + labels[s / 2]]))
                counts[word] += 1
            }
            if t > 0 { s -= Int(back[t * states + s]) }
        }
        return spans.indices.map { word in
            spans[word].map { Aligned(span: $0, confidence: posterior[word] / Double(max(counts[word], 1))) }
        }
    }
}
