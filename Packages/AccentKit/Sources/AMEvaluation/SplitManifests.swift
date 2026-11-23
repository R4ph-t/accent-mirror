// Split manifests (`fixtures/splits/*.json`): seeds, fold assignments and set membership, hashed into every report.

import Foundation

/// Stable JSON for committed manifests: pretty, sorted keys, unescaped slashes, trailing newline. The manifest hash
/// is SHA-256 of exactly these bytes.
public enum ManifestJSON {
    public static func encode(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value) + Data("\n".utf8)
    }
}

/// `fixtures/splits/speechocean762.json`.
public struct SpeechOceanSplitManifest: Sendable, Hashable, Codable {
    public let version: Int
    public let corpus: String
    /// SHA-256 of `scores-detail.json`.
    public let labelHash: String
    /// SHA-256 of the committed label-only fixture the sets were built from.
    public let labelFixtureSHA256: String
    public let foldSeed: UInt64
    public let bootstrapSeed: UInt64
    public let outerFolds: [[String]]
    /// Set name → word ids, sorted.
    public let sets: [String: [String]]
    /// Monosyllabic stress-wrong word id → category.
    public let monosyllabicCategories: [String: String]

    public static let defaultFoldSeed: UInt64 = 20_261_123
    public static let defaultBootstrapSeed: UInt64 = 20_261_124

    public init(
        sets: SpeechOceanSets, folds: SpeechOceanFolds, labelFixtureSHA256: String, foldSeed: UInt64,
        bootstrapSeed: UInt64
    ) {
        func ids(_ words: [SpeechOceanWord]) -> [String] { words.map(\.id).sorted() }
        version = 1
        corpus = "speechocean762"
        labelHash = sets.labels.sourceSHA256
        self.labelFixtureSHA256 = labelFixtureSHA256
        self.foldSeed = foldSeed
        self.bootstrapSeed = bootstrapSeed
        outerFolds = folds.folds.map(\.speakers)
        self.sets = [
            "stressWrongPool": ids(sets.stressWrongPool),
            "recall": ids(sets.recall),
            "recallDiagnostic": ids(sets.recallDiagnostic),
            "cleanFalsePositive": ids(sets.cleanFalsePositive),
            "supplementaryFalsePositive": ids(sets.supplementaryFalsePositive),
            "tuningCorrect": ids(sets.tuningCorrect),
            "dissent": ids(sets.dissent),
            "unintelligible": ids(sets.unintelligible),
        ]
        monosyllabicCategories = Dictionary(
            uniqueKeysWithValues: sets.monosyllabicStressWrong.map { ($0.word.id, $0.category.rawValue) })
    }

    public func folds(for sets: SpeechOceanSets) -> SpeechOceanFolds {
        SpeechOceanFolds(sets: sets, folds: outerFolds.enumerated().map { OuterFold(index: $0, speakers: $1) })
    }
}

/// `fixtures/splits/vctk.json`.
public struct VCTKSplitManifest: Sendable, Hashable, Codable {
    public let version: Int
    /// SHA-256 of `fixtures/vctk/eval-speakers.json`.
    public let evalSpeakersSHA256: String
    public let foldSeed: UInt64
    public let bootstrapSeed: UInt64
    /// The VCTK CV estimate's 6 folds over the 18 tuning speakers.
    public let cvFolds: [[String]]
    public let tuning: [String]
    public let heldOut: [String]

    public static let defaultFoldSeed: UInt64 = 20_261_125
    public static let defaultBootstrapSeed: UInt64 = 20_261_126

    public init(evalSpeakers: VCTKEvalSpeakersManifest, evalSpeakersSHA256: String, foldSeed: UInt64, bootstrapSeed: UInt64) {
        version = 1
        self.evalSpeakersSHA256 = evalSpeakersSHA256
        self.foldSeed = foldSeed
        self.bootstrapSeed = bootstrapSeed
        cvFolds = VCTKFolds.make(evalSpeakers.tuningSpeakers, seed: foldSeed).map(\.speakers)
        tuning = evalSpeakers.tuningSpeakers.map(\.id).sorted()
        heldOut = evalSpeakers.heldOutSpeakers.map(\.id).sorted()
    }
}
