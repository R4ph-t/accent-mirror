// The model-owning part of AMJudging: the installed model folder's manifest, Core ML loading and one take's forward
// pass. Everything on device; Core ML never touches the network.

// `MLModel` is not `Sendable` in the SDK. The one instance here is created inside `load` and then owned by the
// `SoundJudge` actor, which never hands it out, so it is never used from two places at once. Core ML documents
// `MLModel` predictions as thread-safe in any case.
@preconcurrency import CoreML
import AMCore
import Foundation

/// `manifest.json` in the model folder (written by sj-model's `tools/convert_judge_model.py`). Only the keys the
/// judge reads are required; the rest are decoded when present.
public struct SoundJudgeModelManifest: Codable, Sendable, Hashable {
    public struct Source: Codable, Sendable, Hashable {
        public var repo: String
        public var commit: String
        public var license: String?
        public var licenseEvidence: String?
    }

    public struct UpstreamFile: Codable, Sendable, Hashable {
        public var path: String
        public var size: Int?
        public var sha256: String
        public var url: String?
    }

    public struct PackageFile: Codable, Sendable, Hashable {
        public var path: String
        public var size: Int?
        public var sha256: String
    }

    public struct Conversion: Codable, Sendable, Hashable {
        public var script: String?
        public var requirements: String?
        public var python: String?
        public var precision: String?
        public var inputBucketsSeconds: [Double]
    }

    public var formatVersion: Int
    public var model: String
    public var source: Source
    public var upstream: [UpstreamFile]?
    public var conversion: Conversion
    public var package: String?
    public var packageFiles: [PackageFile]?
    public var packageSHA256: String
    public var compiled: String
    public var input: String
    public var output: String
    public var vocabulary: [String]
    public var blank: String
    public var sampleRate: Int
    public var samplesPerFrame: Int

    /// `model@commit#first-8-of-packageSHA256`.
    public var modelID: String { "\(model)@\(source.commit)#\(packageSHA256.prefix(8))" }

    /// The smallest bucket, in samples, that holds `count` samples; nil when the take is longer than every bucket.
    public func bucketSamples(for count: Int) -> Int? {
        conversion.inputBucketsSeconds.map { Int(($0 * Double(sampleRate)).rounded()) }.sorted().first { $0 >= count }
    }
}

extension SoundJudge {
    /// The longest take judged, in seconds (the largest input bucket).
    public static let maximumSeconds = 15.0
    /// The shortest take judged, in seconds.
    public static let minimumSeconds = 0.1

    /// Zero-pads raw samples to `bucket`, then normalises to zero mean, unit variance ((y − mean)/sqrt(var + 1e-7)),
    /// as the spike's padded runs did.
    static func modelInput(_ samples: [Float], bucket: Int) -> [Float] {
        var y = samples
        if y.count < bucket { y += [Float](repeating: 0, count: bucket - y.count) }
        var mean = 0.0
        for v in y { mean += Double(v) }
        mean /= Double(max(1, y.count))
        var variance = 0.0
        for v in y { let d = Double(v) - mean; variance += d * d }
        variance /= Double(max(1, y.count))
        let scale = 1 / (variance + 1e-7).squareRoot()
        return y.map { Float((Double($0) - mean) * scale) }
    }
}

/// The model-owning part: loads the bundled Core ML package once (off the main actor), then judges 16 kHz mono takes.
/// Cancellable: checks `Task.isCancelled` before the forward pass and before and after scoring.
public actor SoundJudge {
    /// The folder name under `Contents/Resources/Models/` and under `MODELS_CACHE`.
    public static let modelFolderName = "wav2vec2-lv-60-espeak-cv-ft"

    public nonisolated let modelID: String
    public nonisolated let manifest: SoundJudgeModelManifest
    nonisolated let vocabulary: TokenVocabulary
    private let model: MLModel

    init(manifest: SoundJudgeModelManifest, vocabulary: TokenVocabulary, model: MLModel) {
        self.modelID = manifest.modelID
        self.manifest = manifest
        self.vocabulary = vocabulary
        self.model = model
    }

    /// Loads the model in `folder` (the bundled `Models/wav2vec2-lv-60-espeak-cv-ft`): its `manifest.json` and the
    /// precompiled `LV60Int8.mlmodelc`, on the CPU and Neural Engine. A missing folder, manifest or compiled model
    /// is `modelNotInstalled`; a manifest that doesn't decode or lacks the judge's tokens, or a Core ML failure, is
    /// `modelFailed`.
    public static func load(folder: URL) async throws -> SoundJudge {
        let manifestURL = folder.appending(path: "manifest.json")
        guard let data = try? Data(contentsOf: manifestURL) else { throw SoundJudgeError.modelNotInstalled }
        let manifest: SoundJudgeModelManifest
        do {
            manifest = try JSONDecoder().decode(SoundJudgeModelManifest.self, from: data)
        } catch {
            throw SoundJudgeError.modelFailed("manifest.json: \(error)")
        }
        guard manifest.sampleRate == 16_000, manifest.samplesPerFrame == 320,
              !manifest.conversion.inputBucketsSeconds.isEmpty
        else { throw SoundJudgeError.modelFailed("manifest.json: unexpected sample rate, frame or buckets") }
        guard let vocabulary = TokenVocabulary(tokens: manifest.vocabulary, blank: manifest.blank) else {
            throw SoundJudgeError.modelFailed("manifest.json: the vocabulary lacks the blank or an English token")
        }
        let compiled = folder.appending(path: manifest.compiled)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: compiled.path(percentEncoded: false), isDirectory: &isDirectory),
              isDirectory.boolValue
        else { throw SoundJudgeError.modelNotInstalled }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndNeuralEngine
        do {
            let model = try await MLModel.load(contentsOf: compiled, configuration: configuration)
            return SoundJudge(manifest: manifest, vocabulary: vocabulary, model: model)
        } catch {
            throw SoundJudgeError.modelFailed("Core ML load: \(error.localizedDescription)")
        }
    }

    /// Normalises, pads to the compiled bucket, runs the model and scores. `samples` are 16 kHz mono floats.
    /// Shorter than 0.1 s or longer than the largest bucket (15 s) throws `takeOutOfRange`.
    public func judge(samples: [Float], words: [ExpectedWord]) async throws -> SoundJudgement {
        let seconds = Double(samples.count) / Double(manifest.sampleRate)
        guard seconds >= Self.minimumSeconds, seconds <= Self.maximumSeconds,
              let bucket = manifest.bucketSamples(for: samples.count)
        else { throw SoundJudgeError.takeOutOfRange(seconds: seconds) }
        let threshold = Thresholds.current.soundJudging.errorThreshold
        guard words.contains(where: { !$0.variants.isEmpty }) else {
            // Nothing to judge: skip the forward pass (the wire reports `nothingJudgeable`).
            return SoundJudgement(modelID: modelID, judgeID: SoundScorer.judgeID, errorThreshold: threshold,
                                  words: words.map(SoundScorer.unjudged))
        }
        try Task.checkCancellation()
        let posteriors = try await forward(Self.modelInput(samples, bucket: bucket))
        try Task.checkCancellation()
        let judged = SoundScorer.judge(posteriors, words: words, vocabulary: vocabulary, takeSeconds: seconds,
                                       errorThreshold: threshold)
        try Task.checkCancellation()
        return SoundJudgement(modelID: modelID, judgeID: SoundScorer.judgeID, errorThreshold: threshold, words: judged)
    }

    /// One forward pass: the model's log-softmax output as `LogPosteriors`.
    func forward(_ input: [Float]) async throws -> LogPosteriors {
        let output: MLShapedArray<Float>
        do {
            let provider = try MLDictionaryFeatureProvider(dictionary: [
                manifest.input: MLMultiArray(MLShapedArray<Float>(scalars: input, shape: [1, input.count])),
            ])
            let result = try await model.prediction(from: provider)
            guard let array = result.featureValue(for: manifest.output)?.multiArrayValue, array.shape.count == 3 else {
                throw SoundJudgeError.modelFailed("no \(manifest.output) output")
            }
            output = MLShapedArray<Float>(array)
        } catch let error as SoundJudgeError {
            throw error
        } catch {
            throw SoundJudgeError.modelFailed("Core ML prediction: \(error.localizedDescription)")
        }
        let frames = output.shape[1], classes = output.shape[2]
        guard classes == manifest.vocabulary.count, frames > 0 else {
            throw SoundJudgeError.modelFailed("output shape \(output.shape) doesn't match the vocabulary")
        }
        return LogPosteriors(frames: frames, vocabularySize: classes, values: output.scalars)
    }
}
