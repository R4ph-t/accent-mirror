import AMAlignment
import Foundation

/// The MFA word baseline (spec 03, Open question 5 default): Montreal Forced Aligner word alignments of the
/// evaluation clips, with the aligner and its models pinned. Written by `am-timestamps baseline`; its SHA-256 is the
/// report's label hash.
public struct WordBaseline: Codable, Sendable, Equatable {
    public struct Aligner: Codable, Sendable, Equatable {
        public var name: String
        public var version: String
        public var acousticModel: String
        public var acousticModelSHA256: String
        public var dictionary: String
        public var dictionarySHA256: String
        public var command: String

        public init(name: String, version: String, acousticModel: String, acousticModelSHA256: String,
                    dictionary: String, dictionarySHA256: String, command: String) {
            self.name = name
            self.version = version
            self.acousticModel = acousticModel
            self.acousticModelSHA256 = acousticModelSHA256
            self.dictionary = dictionary
            self.dictionarySHA256 = dictionarySHA256
            self.command = command
        }
    }

    public struct Clip: Codable, Sendable, Equatable {
        public var clipID: String
        public var words: [BaselineWord]

        public init(clipID: String, words: [BaselineWord]) {
            self.clipID = clipID
            self.words = words
        }
    }

    public var formatVersion: Int
    public var aligner: Aligner
    /// Where the audio came from and its licence.
    public var attribution: String
    public var clips: [Clip]

    public init(aligner: Aligner, attribution: String, clips: [Clip]) {
        self.formatVersion = 1
        self.aligner = aligner
        self.attribution = attribution
        self.clips = clips.sorted { $0.clipID < $1.clipID }
    }

    /// Pretty, sorted-key JSON with a trailing newline: the committed bytes the label hash is taken over.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self) + Data("\n".utf8)
    }
}

public enum MFAOutput {
    /// Word intervals from one MFA JSON alignment (`mfa align --output_format json`): the `words` tier's entries,
    /// `[start, end, label]`, without silence or empty labels.
    public static func words(fromJSON data: Data) throws -> [BaselineWord] {
        struct File: Decodable {
            struct Tier: Decodable { var entries: [Entry] }
            var tiers: [String: Tier]
        }
        struct Entry: Decodable {
            var start: Double, end: Double, label: String
            init(from decoder: Decoder) throws {
                var container = try decoder.unkeyedContainer()
                start = try container.decode(Double.self)
                end = try container.decode(Double.self)
                label = try container.decode(String.self)
            }
        }
        guard let tier = try JSONDecoder().decode(File.self, from: data).tiers["words"] else {
            throw MFAOutputError.noWordsTier
        }
        let silence: Set<String> = ["", "<eps>", "sil", "sp"]
        return tier.entries
            .filter { !silence.contains($0.label.trimmingCharacters(in: .whitespaces).lowercased()) }
            .map { BaselineWord(word: $0.label, start: decimal($0.start), end: decimal($0.end)) }
    }

    /// MFA writes float32 times as doubles (0.9599999785423279); keep the float's shortest decimal form (0.96).
    private static func decimal(_ value: Double) -> Double {
        Double(Float(value).description) ?? value
    }
}

public enum MFAOutputError: Error, Equatable {
    case noWordsTier
}
