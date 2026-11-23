import AMAlignment
import Foundation

// Report identity (plan §6.6). Spec 01 owns `ConfigIdentity`, `CanonicalJSON` and `configDigest` in AMCore; it has
// not landed, so this is the minimal local copy spec 01 says to replace ("If spec 03 lands first with its own copy,
// this spec moves callers to the AMCore one and deletes the copy").

/// The analysis configuration identity. IDs this spec does not own are the explicit placeholder `none`.
public struct ConfigIdentity: Codable, Sendable, Equatable {
    public var algorithmVersion: Int
    public var thresholdsVersion: Int
    public var contractVersion: Int
    public var asrModelID: String
    public var pitchTrackerID: String
    public var voicingID: String

    /// Versions are spec 01's initial values (1, 1, 1); pitch tracker (spec 04) and voicing (spec 05) are not built.
    public static func spec03(asrModelID: String) -> ConfigIdentity {
        ConfigIdentity(algorithmVersion: 1, thresholdsVersion: 1, contractVersion: 1,
                       asrModelID: asrModelID, pitchTrackerID: "none", voicingID: "none")
    }
}

/// JSON with sorted keys, no whitespace, unescaped slashes, and Swift's shortest round-trip number formatting.
public enum CanonicalJSON {
    public static func string<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
}

/// `configDigest`: SHA-256 of the canonical JSON of `ConfigIdentity` plus the thresholds.
/// Until spec 01's full `Thresholds` exists, the thresholds part is the spec 03 gate (`TimestampGate`).
public struct ConfigDigest: Codable, Sendable, Equatable {
    public var canonicalJSON: String
    public var sha256: String

    private struct Input: Encodable {
        var config: ConfigIdentity
        var thresholds: TimestampGate
    }

    public init(config: ConfigIdentity, thresholds: TimestampGate) throws {
        canonicalJSON = try CanonicalJSON.string(Input(config: config, thresholds: thresholds))
        sha256 = Digest.sha256(canonicalJSON)
    }
}

public enum SourceTree {
    /// Entries under this folder are left out of `sourceTreeHash`, so a report can sit in a descendant commit.
    public static let reportsFolder = "docs/agreement/reports/"

    /// The shell recipe, for recomputing by hand.
    public static let recipe =
        #"git ls-tree -r --full-tree <commit> | grep -v "$(printf '\t')docs/agreement/reports/" | LC_ALL=C sort | shasum -a 256"#

    /// `sourceTreeHash`: SHA-256 of the `git ls-tree -r --full-tree <commit>` lines, without entries under
    /// `docs/agreement/reports/`, sorted bytewise, each ending in a newline.
    public static func hash(lsTree output: String) -> String {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            .filter { line in
                guard let tab = line.firstIndex(of: "\t") else { return true }
                return !line[line.index(after: tab)...].hasPrefix(reportsFolder)
            }
            .sorted { Array($0.utf8).lexicographicallyPrecedes(Array($1.utf8)) }
        return Digest.sha256(lines.map { $0 + "\n" }.joined())
    }
}

public enum CorpusHash {
    /// The shell recipe, for recomputing by hand from the cache folder.
    public static let recipe = "shasum -a 256 <clip files> | cut -d' ' -f1 | LC_ALL=C sort | shasum -a 256"

    /// The corpus manifest hash: SHA-256 of the sorted file hashes, one per line, each ending in a newline.
    public static func hash(fileSHA256s: [String]) -> String {
        Digest.sha256(fileSHA256s.sorted().map { $0 + "\n" }.joined())
    }
}
